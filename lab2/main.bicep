// Lab 2: portal-built hub-and-spoke connectivity lab, codified from an exported template.
// Step A: describes the deployed state AS-IS, including known findings (marked FINDING).

@description('Region for all lab2 resources')
param location string = resourceGroup().location

@description('Admin username on both VMs (cannot be changed on an existing VM)')
param adminUsername string = 'azureadmin'

@description('SSH public key on vm-hub-lab2 (read from Azure at deploy time; must match the existing key)')
param hubSshPublicKey string

@description('SSH public key on vm-spoke-lab2 (read from Azure at deploy time; must match the existing key)')
param spokeSshPublicKey string

// ─── NSGs (defaults only; no custom rules) ──────────────────
resource nsgHub 'Microsoft.Network/networkSecurityGroups@2025-09-01' = {
  name: 'nsg-hub-lab2'
  location: location
  properties: {
    securityRules: []
  }
}

resource nsgSpoke 'Microsoft.Network/networkSecurityGroups@2025-09-01' = {
  name: 'nsg-spoke-lab2'
  location: location
  properties: {
    securityRules: []
  }
}

// ─── VNets (subnets inline; peerings as child resources to avoid cycles) ─
resource vnetHub 'Microsoft.Network/virtualNetworks@2025-09-01' = {
  name: 'vnet-hub-lab2'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.20.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-hub-shared'
        properties: {
          addressPrefixes: [
            '10.20.1.0/24'
          ]
          defaultOutboundAccess: false
          networkSecurityGroup: {
            id: nsgHub.id
          }
        }
      }
    ]
  }
}

resource vnetSpoke 'Microsoft.Network/virtualNetworks@2025-09-01' = {
  name: 'vnet-spoke-lab2'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.21.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-spoke-workload'
        properties: {
          addressPrefixes: [
            '10.21.1.0/24'
          ]
          defaultOutboundAccess: false
          networkSecurityGroup: {
            id: nsgSpoke.id
          }
        }
      }
    ]
  }
}

// FINDING: peering names are swapped (the hub-side peering is named "spoke-to-hub")
resource peeringOnHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2025-09-01' = {
  parent: vnetHub
  name: 'peer-spoke-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: vnetSpoke.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource peeringOnSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2025-09-01' = {
  parent: vnetSpoke
  name: 'peer-hub-to-spoke'
  properties: {
    remoteVirtualNetwork: {
      id: vnetHub.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// ─── NICs ───────────────────────────────────────────────────
// FIXED (B.1): NSG is applied at the subnet only; the duplicate NIC-level association was removed
resource nicHub 'Microsoft.Network/networkInterfaces@2025-09-01' = {
  name: 'vm-hub-lab2100'
  location: location
  properties: {
    enableIPForwarding: false
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          primary: true
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddress: '10.20.1.4'
          subnet: {
            id: '${vnetHub.id}/subnets/snet-hub-shared'
          }
        }
      }
    ]
  }
}

resource nicSpoke 'Microsoft.Network/networkInterfaces@2025-09-01' = {
  name: 'vm-spoke-lab2403'
  location: location
  properties: {
    enableIPForwarding: false
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          primary: true
          privateIPAllocationMethod: 'Dynamic'
          privateIPAddress: '10.21.1.4'
          subnet: {
            id: '${vnetSpoke.id}/subnets/snet-spoke-workload'
          }
        }
      }
    ]
  }
}

// ─── VMs ────────────────────────────────────────────────────
resource vmHub 'Microsoft.Compute/virtualMachines@2026-04-01' = {
  name: 'vm-hub-lab2'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    storageProfile: {
      imageReference: {
        publisher: 'canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: 'vm-hub-lab2_OsDisk_1_13cb237c47bd480c9f81873eb6d399df'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'vm-hub-lab2'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: hubSshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicHub.id
          properties: {
            deleteOption: 'Detach'
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'Standard'
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource vmSpoke 'Microsoft.Compute/virtualMachines@2026-04-01' = {
  name: 'vm-spoke-lab2'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    storageProfile: {
      imageReference: {
        publisher: 'canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: 'vm-spoke-lab2_OsDisk_1_21494d66c3b54adfaa7db655958f229f'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'vm-spoke-lab2'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: spokeSshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicSpoke.id
          properties: {
            deleteOption: 'Detach'
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'Standard'
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}
