// Lab 2: portal-built hub-and-spoke connectivity lab, codified from an exported template.
// Step B applied: all three findings fixed (see FIXED comments). Evidence: docs/evidence/lab2-*.txt

@description('Region for all lab2 resources')
param location string = resourceGroup().location

@description('Admin username on both VMs (cannot be changed on an existing VM)')
param adminUsername string = 'azureadmin'

@description('SSH public key on vm-hub-lab2 (read from Azure at deploy time; must match the existing key)')
param hubSshPublicKey string

@description('SSH public key on vm-spoke-lab2 (read from Azure at deploy time; must match the existing key)')
param spokeSshPublicKey string

@description('Standard tags applied to every lab2 resource that supports them')
param tags object = {
  project: 'azure-hub-spoke-network'
  lab: 'lab2'
  environment: 'lab'
  owner: 'jeff'
  costCenter: 'CC-1001'
}

// ─── NSGs (defaults only; no custom rules) ──────────────────
// ─── Address plan (single source of truth for VNets and NSG rules) ─
var hubAddressSpace = '10.20.0.0/16'
var hubSubnetPrefix = '10.20.1.0/24'
var spokeAddressSpace = '10.21.0.0/16'
var spokeSubnetPrefix = '10.21.1.0/24'

// ─── NSGs (FIXED (B.5): least-privilege inbound rules replace defaults-only) ─
resource nsgHub 'Microsoft.Network/networkSecurityGroups@2025-09-01' = {
  name: 'nsg-hub-lab2'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-ICMP-From-Spoke'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Icmp'
          sourceAddressPrefix: spokeAddressSpace
          sourcePortRange: '*'
          destinationAddressPrefix: hubSubnetPrefix
          destinationPortRange: '*'
        }
      }
      {
        name: 'Allow-Intra-Subnet'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: hubSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: hubSubnetPrefix
          destinationPortRange: '*'
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

resource nsgSpoke 'Microsoft.Network/networkSecurityGroups@2025-09-01' = {
  name: 'nsg-spoke-lab2'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-From-Hub-Shared'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: hubSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: spokeSubnetPrefix
          destinationPortRange: '22'
        }
      }
      {
        name: 'Allow-ICMP-From-Hub'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Icmp'
          sourceAddressPrefix: hubAddressSpace
          sourcePortRange: '*'
          destinationAddressPrefix: spokeSubnetPrefix
          destinationPortRange: '*'
        }
      }
      {
        name: 'Allow-Intra-Subnet'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: spokeSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: spokeSubnetPrefix
          destinationPortRange: '*'
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

// ─── VNets (subnets inline; peerings as child resources to avoid cycles) ─
resource vnetHub 'Microsoft.Network/virtualNetworks@2025-09-01' = {
  name: 'vnet-hub-lab2'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubAddressSpace
      ]
    }
    subnets: [
      {
        name: 'snet-hub-shared'
        properties: {
          addressPrefixes: [
            hubSubnetPrefix
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
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        spokeAddressSpace
      ]
    }
    subnets: [
      {
        name: 'snet-spoke-workload'
        properties: {
          addressPrefixes: [
            spokeSubnetPrefix
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

// FIXED (B.3): peering names now describe direction from the VNet they live on
resource peeringOnHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2025-09-01' = {
  parent: vnetHub
  name: 'peer-hub-to-spoke'
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
  name: 'peer-spoke-to-hub'
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
  tags: tags
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
  tags: tags
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
  tags: tags
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
  tags: tags
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
