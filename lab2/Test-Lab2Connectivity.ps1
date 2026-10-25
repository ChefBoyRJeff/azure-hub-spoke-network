<#
.SYNOPSIS
  Lab 2 connectivity retest. Starts both VMs, checks effective NSGs, effective routes,
  hub<->spoke reachability and IP flow verify, then ALWAYS deallocates both VMs.
.NOTES
  Billable while running: two Standard_B1s VMs (about $0.0104/hr each).
  No public IPs or Bastion are used; tests run through Azure Run Command.
#>
[CmdletBinding()]
param(
  [string]$ResourceGroup = 'rg-hubspoke-vms',
  [string]$OutFile = 'docs\evidence\lab2-16-connectivity-retest.txt'
)

$vms = @(
  @{ Name = 'vm-hub-lab2';   Nic = 'vm-hub-lab2100';   Ip = '10.20.1.4'; Peer = '10.21.1.4' },
  @{ Name = 'vm-spoke-lab2'; Nic = 'vm-spoke-lab2403'; Ip = '10.21.1.4'; Peer = '10.20.1.4' }
)

function Log([string]$Message) { $Message | Tee-Object -FilePath $OutFile -Append }

Set-Content -Path $OutFile -Value "Lab2 connectivity retest, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$started = Get-Date

try {
  foreach ($v in $vms) {
    Log "Starting $($v.Name)..."
    az vm start -g $ResourceGroup -n $v.Name -o none
    if ($LASTEXITCODE -ne 0) { throw "Failed to start $($v.Name)" }
  }
  Log '=== Power state after start ==='
  az vm list -d -g $ResourceGroup -o json | ConvertFrom-Json | ForEach-Object { Log "$($_.name): $($_.powerState)" }

  foreach ($v in $vms) {
    Log "=== Effective NSGs on $($v.Nic) (expect ONE entry, associated via subnet) ==="
    $eff = az network nic list-effective-nsg -g $ResourceGroup -n $v.Nic -o json | ConvertFrom-Json
    foreach ($e in $eff.value) {
      Log ('NSG={0}  subnet={1}  nic={2}' -f ($e.networkSecurityGroup.id -split '/')[-1],
        ($e.association.subnet.id -split '/')[-1], ($e.association.networkInterface.id -split '/')[-1])
    }

    Log "=== Effective routes on $($v.Nic) (expect a VNetPeering route to the other VNet) ==="
    $rt = az network nic show-effective-route-table -g $ResourceGroup -n $v.Nic -o json | ConvertFrom-Json
    foreach ($r in $rt.value) {
      Log ('{0,-8} {1,-22} {2,-16} {3}' -f $r.source, ($r.addressPrefix -join ','), $r.nextHopType, $r.state)
    }
  }

  foreach ($v in $vms) {
    Log "=== From $($v.Name) ($($v.Ip)) to $($v.Peer): ping and TCP 22 (expect success) ==="
    $script = "ping -c 4 -W 2 $($v.Peer); nc -zv -w 3 $($v.Peer) 22; echo nc_exit=`$?"
    $msg = az vm run-command invoke -g $ResourceGroup -n $v.Name --command-id RunShellScript --scripts $script --query 'value[0].message' -o json | ConvertFrom-Json
    Log $msg
  }

  Log '=== IP flow verify: inbound TCP 22 to spoke from hub (expect Allow) ==='
  $flow = az network watcher test-ip-flow -g $ResourceGroup --vm vm-spoke-lab2 --nic vm-spoke-lab2403 --direction Inbound --protocol TCP --local 10.21.1.4:22 --remote 10.20.1.4:60000 -o json | ConvertFrom-Json
  if ($LASTEXITCODE -eq 0) { Log ('access={0}  rule={1}' -f $flow.access, $flow.ruleName) }
  else { Log 'IP flow verify did not run (see the error above); other results are still valid.' }
}
finally {
  foreach ($v in $vms) {
    Log "Deallocating $($v.Name)..."
    az vm deallocate -g $ResourceGroup -n $v.Name -o none
  }
  Log '=== Final power state (expect VM deallocated) ==='
  az vm list -d -g $ResourceGroup -o json | ConvertFrom-Json | ForEach-Object { Log "$($_.name): $($_.powerState)" }
  Log ('Elapsed from start to deallocated: {0} min' -f [math]::Round(((Get-Date) - $started).TotalMinutes, 1))
}