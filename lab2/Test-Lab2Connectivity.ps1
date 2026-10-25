<#
.SYNOPSIS
  Lab 2 connectivity test matrix. Starts both VMs, runs positive and negative tests
  against the expected NSG design, then ALWAYS deallocates both VMs.
.DESCRIPTION
  Reachability tests run inside each VM through Azure Run Command (no public IPs or Bastion).
  Every test has an expected result, and the summary reports PASS or FAIL for each one.
  A blocked TCP test passes only if the connection TIMED OUT (dropped by an NSG). "Connection
  refused" means the packet reached the VM and nothing was listening, so it is reported
  separately. Network Watcher IP flow verify names the NSG rule behind each TCP decision.
.NOTES
  Billable while running: two Standard_B1s VMs (about $0.0104/hr each).
  Writes a second file next to -OutFile with the raw effective-NSG JSON (sanitize before committing).
.EXAMPLE
  .\lab2\Test-Lab2Connectivity.ps1 -OutFile docs\evidence\lab2-20-connectivity-b5.txt
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$OutFile,
  [string]$ResourceGroup = 'rg-hubspoke-vms'
)

$hub   = @{ Name = 'vm-hub-lab2';   Nic = 'vm-hub-lab2100';   Ip = '10.20.1.4' }
$spoke = @{ Name = 'vm-spoke-lab2'; Nic = 'vm-spoke-lab2403'; Ip = '10.21.1.4' }
$vms = @($hub, $spoke)

# Reachability tests, run inside the source VM. Expect 'open' or 'blocked'.
$tests = @(
  @{ Id = 1; From = $hub;   To = $spoke; Kind = 'ping'; Port = 0;    Expect = 'open';    Rule = 'spoke 110 Allow-ICMP-From-Hub' }
  @{ Id = 2; From = $hub;   To = $spoke; Kind = 'tcp';  Port = 22;   Expect = 'open';    Rule = 'spoke 100 Allow-SSH-From-Hub-Shared' }
  @{ Id = 3; From = $hub;   To = $spoke; Kind = 'tcp';  Port = 8080; Expect = 'blocked'; Rule = 'spoke 4000 Deny-VNet-Inbound' }
  @{ Id = 4; From = $spoke; To = $hub;   Kind = 'ping'; Port = 0;    Expect = 'open';    Rule = 'hub 100 Allow-ICMP-From-Spoke' }
  @{ Id = 5; From = $spoke; To = $hub;   Kind = 'tcp';  Port = 22;   Expect = 'blocked'; Rule = 'hub 4000 Deny-VNet-Inbound' }
)

# IP flow verify cases (TCP only; the tool does not test ICMP).
$flows = @(
  @{ Target = $spoke; Port = 22;   Remote = $hub;   Expect = 'Allow'; Rule = 'Allow-SSH-From-Hub-Shared' }
  @{ Target = $spoke; Port = 8080; Remote = $hub;   Expect = 'Deny';  Rule = 'Deny-VNet-Inbound' }
  @{ Target = $hub;   Port = 22;   Remote = $spoke; Expect = 'Deny';  Rule = 'Deny-VNet-Inbound' }
)

$results = New-Object System.Collections.Generic.List[object]

function Log([string]$Message) { $Message | Tee-Object -FilePath $OutFile -Append }

function Add-Result([string]$Name, [string]$Expected, [string]$Actual, [string]$Detail) {
  $status = if ($Expected -eq $Actual) { 'PASS' } else { 'FAIL' }
  $results.Add([pscustomobject]@{ Status = $status; Test = $Name; Expected = $Expected; Actual = $Actual; Detail = $Detail })
}

$rawFile = [IO.Path]::ChangeExtension($OutFile, $null).TrimEnd('.') + '-effective-nsg-raw.txt'
Set-Content -Path $OutFile -Value "Lab2 connectivity test matrix, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Set-Content -Path $rawFile -Value "Raw effective-NSG JSON, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
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
    Log "=== Effective NSG associations on $($v.Nic) (expect one NSG, via subnet) ==="
    $json = (az network nic list-effective-nsg -g $ResourceGroup -n $v.Nic -o json) -join "`n"
    Add-Content -Path $rawFile -Value "##### $($v.Nic)"
    Add-Content -Path $rawFile -Value $json
    $eff = $json | ConvertFrom-Json
    foreach ($e in $eff.value) {
      Log ('NSG={0}  subnet={1}  nic={2}  effectiveRules={3}' -f ($e.networkSecurityGroup.id -split '/')[-1],
        ($e.association.subnet.id -split '/')[-1], ($e.association.networkInterface.id -split '/')[-1],
        @($e.effectiveSecurityRules).Count)
    }

    Log "=== VNet routes on $($v.Nic) (VnetLocal and VNetPeering only) ==="
    $rt = (az network nic show-effective-route-table -g $ResourceGroup -n $v.Nic -o json) -join "`n" | ConvertFrom-Json
    $vnetRoutes = @($rt.value | Where-Object { $_.nextHopType -in 'VnetLocal', 'VNetPeering' })
    foreach ($r in $vnetRoutes) {
      Log ('{0,-8} {1,-18} {2,-12} {3}' -f $r.source, ($r.addressPrefix -join ','), $r.nextHopType, $r.state)
    }
    Log ('(+{0} platform default routes not shown)' -f (@($rt.value).Count - $vnetRoutes.Count))
  }

  foreach ($src in $vms) {
    $mine = @($tests | Where-Object { $_.From.Name -eq $src.Name })
    $cmds = foreach ($t in $mine) {
      if ($t.Kind -eq 'ping') { "ping -c 3 -W 2 -q $($t.To.Ip); echo RESULT_$($t.Id)=`$?" }
      else { "nc -zv -w 3 $($t.To.Ip) $($t.Port); echo RESULT_$($t.Id)=`$?" }
    }
    Log "=== Reachability tests from $($src.Name) ($($src.Ip)) ==="
    $msg = [string](az vm run-command invoke -g $ResourceGroup -n $src.Name --command-id RunShellScript --scripts ($cmds -join '; ') --query 'value[0].message' -o json | ConvertFrom-Json)
    Log $msg

    foreach ($t in $mine) {
      $m = [regex]::Match($msg, "RESULT_$($t.Id)=(\d+)")
      $actual = if (-not $m.Success) { 'no-result' } elseif ($m.Groups[1].Value -eq '0') { 'open' } else { 'blocked' }
      if ($t.Kind -eq 'tcp' -and $actual -eq 'blocked' -and
          $msg -match "$([regex]::Escape($t.To.Ip)) port $($t.Port) \(tcp\) failed: Connection refused") {
        $actual = 'refused'
      }
      $label = if ($t.Kind -eq 'ping') { 'ping' } else { "TCP $($t.Port)" }
      Add-Result "$($t.Id). $($src.Name) -> $($t.To.Name) $label" $t.Expect $actual $t.Rule
    }
  }

  Log '=== IP flow verify ==='
  foreach ($f in $flows) {
    $name = "IPflow: TCP $($f.Port) into $($f.Target.Name) from $($f.Remote.Name)"
    $flow = (az network watcher test-ip-flow -g $ResourceGroup --vm $f.Target.Name --nic $f.Target.Nic --direction Inbound --protocol TCP --local "$($f.Target.Ip):$($f.Port)" --remote "$($f.Remote.Ip):60000" -o json) -join "`n" | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $flow) {
      Log "$name : did not run (see the error above)"
      Add-Result $name "$($f.Expect)/$($f.Rule)" 'did-not-run' ''
      continue
    }
    Log ('{0} : access={1} rule={2}' -f $name, $flow.access, $flow.ruleName)
    Add-Result $name "$($f.Expect)/$($f.Rule)" "$($flow.access)/$(($flow.ruleName -split '/')[-1])" $flow.ruleName
  }
}
finally {
  foreach ($v in $vms) {
    Log "Deallocating $($v.Name)..."
    az vm deallocate -g $ResourceGroup -n $v.Name -o none
  }
  Log '=== Final power state (expect VM deallocated) ==='
  az vm list -d -g $ResourceGroup -o json | ConvertFrom-Json | ForEach-Object { Log "$($_.name): $($_.powerState)" }
  Log ('Elapsed from start to deallocated: {0} min' -f [math]::Round(((Get-Date) - $started).TotalMinutes, 1))

  Log '=== Summary ==='
  Log ($results | Format-Table -AutoSize | Out-String -Width 220).TrimEnd()
  $passed = @($results | Where-Object { $_.Status -eq 'PASS' }).Count
  Log ('Result: {0} of {1} PASS' -f $passed, $results.Count)
}
