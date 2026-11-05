// Lab 3: internal Standard Load Balancer in spoke1, in front of vm-web1 and vm-web2.
// Built in the portal first, then written here from the live configuration and
// checked with what-if. The VMs themselves are created with the CLI (see README).
// The two NICs are declared because NIC-based backend pool membership lives on the NIC.

param location string = resourceGroup().location

param tags object = {
  project: 'azure-hub-spoke-network'
  environment: 'lab'
  owner: 'jeff'
  costCenter: 'CC-1001'
  lab: 'lab3'
}

var lbName = 'lb-spoke1-web'
var subnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-spoke1', 'snet-workload')
var poolId = resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'be-web')

var backends = [
  { nic: 'nic-vm-web1', ip: '10.1.1.4' }
  { nic: 'nic-vm-web2', ip: '10.1.1.5' }
]

resource lb 'Microsoft.Network/loadBalancers@2024-05-01' = {
  name: lbName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'fe-web'
        zones: [ '1', '2', '3' ]
        properties: {
          privateIPAllocationMethod: 'Static' // the portal default was Dynamic (Lab 3 finding)
          privateIPAddress: '10.1.1.10'
          privateIPAddressVersion: 'IPv4'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'be-web'
      }
    ]
    probes: [
      {
        name: 'probe-web'
        properties: {
          protocol: 'Http'
          port: 443
          requestPath: '/'
          intervalInSeconds: 5
          probeThreshold: 1
          numberOfProbes: 1 // the portal set this legacy property to 1; undeclared it would revert to 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'rule-web-443'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'fe-web')
          }
          backendAddressPool: {
            id: poolId
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'probe-web')
          }
          protocol: 'Tcp'
          frontendPort: 443
          backendPort: 443
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          loadDistribution: 'Default' // 5-tuple hash, not round-robin
          disableOutboundSnat: true // portal-set; no effect on an internal frontend, declared to match live
        }
      }
    ]
  }
}

resource nics 'Microsoft.Network/networkInterfaces@2024-05-01' = [for b in backends: {
  name: b.nic
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          primary: true
          privateIPAllocationMethod: 'Static'
          privateIPAddress: b.ip
          subnet: {
            id: subnetId
          }
          loadBalancerBackendAddressPools: [
            {
              id: poolId
            }
          ]
        }
      }
    ]
  }
  dependsOn: [
    lb
  ]
}]

output frontendIp string = lb.properties.frontendIPConfigurations[0].properties.privateIPAddress
