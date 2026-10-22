// Deploys the lab VMs into their own resource group, attached to the
// existing hub-and-spoke network. Delete this resource group to tear down.
param location string = resourceGroup().location

@description('SSH public key for the lab admin user (passed at deploy time; never committed)')
param sshPublicKey string

@description('Admin username on every VM')
param adminUsername string = 'labadmin'

@description('VM size. B1s chosen because Basv2 family quota is 0 on this subscription')
param vmSize string = 'Standard_B1s'

@description('Availability zone. Zone 2 is restricted for this size on this subscription')
param zone string = '1'

@description('Resource group that holds the hub-and-spoke network')
param networkResourceGroup string = 'rg-hubspoke-lab'

@description('IP forwarding on the hub NVA NIC (off by default for the routing scenario)')
param nvaIpForwarding bool = false

@description('Tags applied to every taggable resource')
param tags object = {
  project: 'azure-hub-spoke-network'
  environment: 'lab'
  owner: 'jeff'
  costCenter: 'CC-1001'
}

// ─── Existing network (in the network resource group) ───────
resource hubVnet 'Microsoft.Network/virtualNetworks@2026-01-01' existing = {
  name: 'vnet-hub'
  scope: resourceGroup(networkResourceGroup)
}
resource hubShared 'Microsoft.Network/virtualNetworks/subnets@2026-01-01' existing = {
  parent: hubVnet
  name: 'snet-shared'
}
resource spoke1Vnet 'Microsoft.Network/virtualNetworks@2026-01-01' existing = {
  name: 'vnet-spoke1'
  scope: resourceGroup(networkResourceGroup)
}
resource spoke1Subnet 'Microsoft.Network/virtualNetworks/subnets@2026-01-01' existing = {
  parent: spoke1Vnet
  name: 'snet-workload'
}
resource spoke2Vnet 'Microsoft.Network/virtualNetworks@2026-01-01' existing = {
  name: 'vnet-spoke2'
  scope: resourceGroup(networkResourceGroup)
}
resource spoke2Subnet 'Microsoft.Network/virtualNetworks/subnets@2026-01-01' existing = {
  parent: spoke2Vnet
  name: 'snet-workload'
}

// ─── VM definitions ─────────────────────────────────────────
var vms = [
  {
    name: 'vm-nva'
    subnetId: hubShared.id
    privateIp: '10.0.1.4'
    ipForwarding: nvaIpForwarding
  }
  {
    name: 'vm-app1'
    subnetId: spoke1Subnet.id
    privateIp: '10.1.1.4'
    ipForwarding: false
  }
  {
    name: 'vm-app2'
    subnetId: spoke2Subnet.id
    privateIp: '10.2.1.4'
    ipForwarding: false
  }
]

module vmModules 'modules/vm.bicep' = [for vm in vms: {
  name: 'deploy-${vm.name}'
  params: {
    location: location
    tags: tags
    vmName: vm.name
    vmSize: vmSize
    zone: zone
    subnetId: vm.subnetId
    privateIp: vm.privateIp
    enableIpForwarding: vm.ipForwarding
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
  }
}]
