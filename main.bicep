param location string = resourceGroup().location

// ─── Address plan ───────────────────────────────────────────
var hubAddressSpace = '10.0.0.0/16'
var hubSharedSubnetPrefix = '10.0.1.0/26'
var hubGatewaySubnetPrefix = '10.0.2.0/27'
var nvaIpAddress = '10.0.1.4'

var spokes = [
  {
    name: 'spoke1'
    addressSpace: '10.1.0.0/16'
    workloadSubnetPrefix: '10.1.1.0/25'
  }
  {
    name: 'spoke2'
    addressSpace: '10.2.0.0/16'
    workloadSubnetPrefix: '10.2.1.0/25'
  }
]

// ─── Hub VNet ───────────────────────────────────────────────
resource hubVnet 'Microsoft.Network/virtualNetworks@2026-03-01' = {
  name: 'vnet-hub'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubAddressSpace
      ]
    }
    subnets: [
      {
        name: 'snet-shared'
        properties: {
          addressPrefix: hubSharedSubnetPrefix
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: hubGatewaySubnetPrefix
        }
      }
    ]
  }
}

// ─── Spokes (one module per spoke) ──────────────────────────
@batchSize(1)
module spokeModules 'modules/spoke.bicep' = [for spoke in spokes: {
  name: 'deploy-${spoke.name}'
  params: {
    location: location
    spokeName: spoke.name
    addressSpace: spoke.addressSpace
    workloadSubnetPrefix: spoke.workloadSubnetPrefix
    hubVnetId: hubVnet.id
    hubAddressSpace: hubAddressSpace
    hubSharedSubnetPrefix: hubSharedSubnetPrefix
    nvaIpAddress: nvaIpAddress
  }
}]

// ─── Peering: Hub → each Spoke ──────────────────────────────
@batchSize(1)
resource hubToSpokePeerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2026-03-01' = [for (spoke, i) in spokes: {
  parent: hubVnet
  name: 'peer-hub-to-${spoke.name}'
  properties: {
    remoteVirtualNetwork: {
      id: spokeModules[i].outputs.vnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}]
