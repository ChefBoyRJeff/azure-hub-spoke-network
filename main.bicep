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
