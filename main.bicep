param location string = resourceGroup().location

// ─── Hub VNet ───────────────────────────────────────────────
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

// ─── NSG for spoke workload subnet ──────────────────────────
resource nsgWorkload 'Microsoft.Network/networkSecurityGroups@2026-03-01' = {
  name: 'nsg-snet-workload'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-From-Hub'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.0.0.0/16'
          sourcePortRange: '*'
          destinationAddressPrefix: '10.1.1.0/25'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-Mgmt-From-Shared'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '10.0.1.0/26'
          sourcePortRange: '*'
          destinationAddressPrefix: '10.1.1.0/25'
          destinationPortRanges: [
            '22'
            '3389'
          ]
        }
      }
      {
        name: 'Deny-VNet-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ─── Route table for spoke workload subnet ──────────────────
resource rtWorkload 'Microsoft.Network/routeTables@2026-03-01' = {
  name: 'rt-snet-workload'
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'Default-To-Hub-NVA'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: '10.0.1.4'
        }
      }
    ]
  }
}

// ─── Spoke VNet ─────────────────────────────────────────────
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
          networkSecurityGroup: {
            id: nsgWorkload.id
          }
          routeTable: {
            id: rtWorkload.id
          }
        }
      }
    ]
  }
}

// ─── Peering: Hub → Spoke ───────────────────────────────────
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

// ─── Peering: Spoke → Hub ───────────────────────────────────
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
