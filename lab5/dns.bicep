// Lab 5 (Azure DNS): private zone with VNet links and manual records, plus a public zone (not delegated).
// Built in the portal first (M1, M2, M4), then written here and checked with what-if against the portal build.
//
//   az deployment group what-if -g rg-dns-lab -f lab5/dns.bicep
//
// Not declared on purpose: the auto-registered A record for vm-dns-hub (Azure creates and deletes it with the
// VM, because link-hub has registration enabled), the SOA records, and the public zone's NS record set
// (Azure creates them with the zone). Incremental mode leaves undeclared records alone.
targetScope = 'resourceGroup'

@description('Resource group of the Project 1 VNets')
param networkResourceGroup string = 'rg-hubspoke-lab'

@description('Private DNS zone name. .internal is reserved by ICANN for private use')
param privateZoneName string = 'hubspoke.internal'

@description('Public DNS zone name (not delegated: no domain was bought; queried directly against Azure name servers)')
param publicZoneName string = 'hubspoke-7m2p9q.com'

@description('Standard tags for the zones')
param tags object = {
  project: 'azure-hub-spoke-network'
  environment: 'lab'
  owner: 'jeff'
  costCenter: 'CC-1001'
  lab: 'lab5'
}

// VNet links. Only one link per VNet may have registration enabled across all private zones;
// the hub registers its VMs automatically, spoke1 can only resolve (its VMs need manual records).
var links = [
  {
    name: 'link-hub'
    vnetName: 'vnet-hub'
    registrationEnabled: true
  }
  {
    name: 'link-spoke1'
    vnetName: 'vnet-spoke1'
    registrationEnabled: false
  }
]

// --- Private zone -------------------------------------------------------------
resource privateZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateZoneName
  location: 'global'
  tags: tags
}

resource vnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for link in links: {
  parent: privateZone
  name: link.name
  location: 'global'
  properties: {
    registrationEnabled: link.registrationEnabled
    virtualNetwork: {
      id: resourceId(networkResourceGroup, 'Microsoft.Network/virtualNetworks', link.vnetName)
    }
  }
}]

// Manual A record: vm-dns-spoke1 is in a resolution-only VNet, so it doesn't auto-register
resource spokeVmRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateZone
  name: 'vm-dns-spoke1'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: '10.1.1.30'
      }
    ]
  }
}

// Friendly service name; clients follow the CNAME, so the target can change without touching them
resource appCname 'Microsoft.Network/privateDnsZones/CNAME@2020-06-01' = {
  parent: privateZone
  name: 'app'
  properties: {
    ttl: 300
    cnameRecord: {
      cname: '${spokeVmRecord.name}.${privateZoneName}'
    }
  }
}

// --- Public zone (not delegated) ------------------------------------------------
resource publicZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: publicZoneName
  location: 'global'
  tags: tags
  properties: {
    zoneType: 'Public'
  }
}

resource wwwRecord 'Microsoft.Network/dnsZones/A@2018-05-01' = {
  parent: publicZone
  name: 'www'
  properties: {
    TTL: 300
    ARecords: [
      {
        ipv4Address: '203.0.113.10' // TEST-NET-3 (RFC 5737): documentation range, never a real server
      }
    ]
  }
}

resource publicAppCname 'Microsoft.Network/dnsZones/CNAME@2018-05-01' = {
  parent: publicZone
  name: 'app'
  properties: {
    TTL: 300
    CNAMERecord: {
      cname: '${wwwRecord.name}.${publicZoneName}'
    }
  }
}

resource apexTxt 'Microsoft.Network/dnsZones/TXT@2018-05-01' = {
  parent: publicZone
  name: '@'
  properties: {
    TTL: 300
    TXTRecords: [
      {
        value: [
          'lab5-verification'
        ]
      }
    ]
  }
}

output publicZoneNameServers array = publicZone.properties.nameServers
