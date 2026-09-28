// ─── Parameters ─────────────────────────────────────────────
@description('Azure region for all spoke resources')
param location string

@description('Short spoke name, used to build resource names (e.g. spoke1)')
param spokeName string

@description('Address space for the spoke VNet')
param addressSpace string

@description('Prefix for the spoke workload subnet')
param workloadSubnetPrefix string

@description('Resource ID of the hub VNet to peer with')
param hubVnetId string

@description('Hub VNet address space, allowed HTTPS into the workload subnet')
param hubAddressSpace string

@description('Hub shared services subnet, allowed SSH/RDP into the workload subnet')
param hubSharedSubnetPrefix string

@description('Private IP of the hub firewall/NVA used as next hop for egress')
param nvaIpAddress string

// ─── NSG ────────────────────────────────────────────────────
resource nsg 'Microsoft.Network/networkSecurityGroups@2026-03-01' = {
  name: 'nsg-${spokeName}-workload'
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
          sourceAddressPrefix: hubAddressSpace
          sourcePortRange: '*'
          destinationAddressPrefix: workloadSubnetPrefix
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
          sourceAddressPrefix: hubSharedSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: workloadSubnetPrefix
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

// ─── Route table ────────────────────────────────────────────
resource routeTable 'Microsoft.Network/routeTables@2026-03-01' = {
  name: 'rt-${spokeName}-workload'
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'Default-To-Hub-NVA'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: nvaIpAddress
        }
      }
    ]
  }
}

// ─── Spoke VNet ─────────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2026-03-01' = {
  name: 'vnet-${spokeName}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpace
      ]
    }
    subnets: [
      {
        name: 'snet-workload'
        properties: {
          addressPrefix: workloadSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          routeTable: {
            id: routeTable.id
          }
        }
      }
    ]
  }
}

// ─── Peering: Spoke → Hub ───────────────────────────────────
resource spokeToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2026-03-01' = {
  parent: vnet
  name: 'peer-${spokeName}-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// ─── Outputs ────────────────────────────────────────────────
output vnetId string = vnet.id
output vnetName string = vnet.name
