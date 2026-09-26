param location string = resourceGroup().location

resource hubVnet 'Microsoft.Network/virtualNetworks@2026-03-01' = {
  name: 'vnet-hub'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-shared'
        properties: {
          addressPrefix: '10.0.1.0/26'
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: '10.0.2.0/27'
        }
      }
    ]
  }
}

resource spokeVnet 'Microsoft.Network/virtualNetworks@2026-03-01' = {
  name: 'vnet-spoke'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-workload'
        properties: {
          addressPrefix: '10.1.1.0/25'
        }
      }
    ]
  }
}

// Hub → Spoke
resource hubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2026-03-01' = {
  parent: hubVnet
  name: 'peer-hub-to-spoke'
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// Spoke → Hub
resource spokeToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2026-03-01' = {
  parent: spokeVnet
  name: 'peer-spoke-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}
