// ****************************************
// Azure Bicep Deployment
// This deployemnt will the below components for Private AKS deployment.
//RG, vNet, Subnet
//Route table and association the subnet as per PRivate AKS requeriments the next hope will be my NVA (Azure Firewall)
//Private AKS 
// ****************************************

targetScope = 'subscription'
param baseName string = 'test'
param pubkeydata string = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNsgSFo+DDl5OvQXX1HQ/h7i9TsKId+QwanGjJFjI5+9nrQL94xsZiYfZTot3xpF9xKUjswvck/QZ0tv6hu6m58tXXlX+qm5IQTdQrI1CoKkLWjkuZoKy8Ai/P4QN7vWpzVAq+6yEfd9p9URkTPEmiThjQclsdbVgTfqxcrtQUkV6OrcVxp6DsQ7azjDZP2+wbq3fghZXkoD3z6dEdOy0FlkR/9BBed98QNv4qwigmQZNkASOqMo+4VqF0dZHSp2eMUzJSP7L8NbbuAoaE52i/1ACll7dRSXKM+47PDWNN+szlKlPV+dbrtcwEGCHXYMvspoEVUFX6GdnjZeMTvAWS4+2DFULkENNzR8Gl63oTbTNbTG29Scd4RtsBkGu/q9ye/QJ1JubbaZAArgTVZwfjy6C5VPuNY8B1jyjcaIyGFZrcSXa5WMYDvBBfVbFVHD2sUXIihrCuD0nomTXxKxXsQ1TYL8MJVkaRu6OLKTcvwIiHOBLV2hXckbHcfgSFA/aT6l99yN4H/6g3LrkQdMMzKSm3SOb+v9jtWzwUERVxqNdxy3l0MJQAFBa5/QEeh94b6rQ2DyCSVc0jfknmLhiUTkeTv8qb03n+Y1F04sqOzpQvJAKAg4tr4GDAXYtk7octoV/uuxEQFkRCxIW023mwMx+mPRPZfedOnBG7QxzZ5w=='
param script64 string = 'saddsadsa'

param location string = 'centralindia'
var rgName          = 'aks-test-rg'

var acrName = '${uniqueString(rgName)}acr'

param hubVNETaddPrefixes array = [
  '10.0.0.0/16'
]
param hubVNETdefaultSubnet object = {
  properties: {
    addressPrefix: '10.0.0.0/24'
  }
  name: 'default'
}
param hubVNETfirewalSubnet object = {
  properties: {
    addressPrefix: '10.0.1.0/24'
  }
  name: 'AzureFirewallSubnet'
}
param hubVNETVMSubnet object = {
  properties: {
    addressPrefix: '10.0.2.0/28'
  }
  name: 'vmsubnet'
}
param hubVNETBastionSubnet object = {
  properties: {
    addressPrefix: '10.0.3.0/27'
  }
  name: 'AzureBastionSubnet'
}

param spokeVNETaddPrefixes array = [
  '10.1.0.0/16'
]
param spokeVNETdefaultSubnet object = {
  properties: {
    addressPrefix: '10.1.0.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
  name: 'default'
}

//Resource group
resource rg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: rgName
  location: location
}

//Hub Vnet
module vnethub './modules/vnet/vnet.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'Hub-VNet'
  params: {
    vnetAddressSpace: {
        addressPrefixes: hubVNETaddPrefixes
    }
    vnetNamePrefix: 'hub'
    subnets: [
      hubVNETdefaultSubnet
      hubVNETfirewalSubnet
      hubVNETVMSubnet
      hubVNETBastionSubnet
    ]
  }  
}

//Spoke Vnet
module vnetspoke './modules/vnet/vnet.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'spoke-VNet'
  params: {
    vnetAddressSpace: {
        addressPrefixes: spokeVNETaddPrefixes
    }
    vnetNamePrefix: 'spoke'
    subnets: [
      spokeVNETdefaultSubnet
      {
        properties: {
          addressPrefix: '10.1.2.0/23'
          privateEndpointNetworkPolicies: 'Disabled'
          routeTable: {
            id: routetable.outputs.routetableID
          }          
        }
        name: 'AKS'
      }
    ]
  }  
}

module vnetpeeringhub './modules/vnet/vnetpeering.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'vnetpeering'
  params: {
    peeringName: 'HUB-to-Spoke'
    vnetName: vnethub.outputs.vnetName
    properties: {
      allowVirtualNetworkAccess: true
      allowForwardedTraffic: true
      remoteVirtualNetwork: {
        id: vnetspoke.outputs.vnetId
      }
    }    
  }
}

module vnetpeeringspoke './modules/vnet/vnetpeering.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'vnetpeeringspoke'
  params: {
    peeringName: 'Spoke-to-HUB'
    vnetName: vnetspoke.outputs.vnetName
    properties: {
      allowVirtualNetworkAccess: true
      allowForwardedTraffic: true
      remoteVirtualNetwork: {
        id: vnethub.outputs.vnetId
      }
    }    
  }
}

module publicipfw './modules/vnet/publicip.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'publicipfw'
  params: {
    publicipName: 'fw-pip'
    publicipproperties: {
      publicIPAllocationMethod: 'Static'      
    }
    publicipsku: {
      name: 'Standard'
      tier: 'Regional'      
    }
  } 
}

resource subnetfw 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' existing = {
  scope: resourceGroup(rg.name)
  name: '${vnethub.name}/AzureFirewallSubnet'
  /*parent: vnethub*/
}

module azfirewall 'modules/vnet/firewall.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'azfirewall'
  params: {
    fwname: 'azfirewall'    
    fwipConfigurations: [
      {
        name: 'fwPublicIP'
        properties: {
          subnet: {
            id: subnetfw.id
          }
          publicIPAddress: {
            id: publicipfw.outputs.publicipId
          }
        }
      }
    ]
    fwapplicationRuleCollections: [
      {
        name: 'Helper-tools'
        properties: {
          priority: 101
          action: {
            type: 'Allow'
          }
          rules: [
            {
              name: 'Allow-ifconfig'
              protocols: [
                {
                  port: 80
                  protocolType: 'Http'
                }
                {
                  port: 443
                  protocolType: 'Https'
                }                
              ]
              targetFqdns: [
                'ifconfig.co' 
                'api.snapcraft.io' 
                'jsonip.com' 
                'kubernaut.io' 
                'motd.ubuntu.com'
              ]
              sourceAddresses: [
                '10.0.0.0/16'
                '10.1.0.0/16'
              ]
            }
          ]
        }
      }      
      {
        name: 'AKS-egress-application'
        properties: {
          priority: 102
          action: {
            type: 'Allow'
          }
          rules: [
            {
              name: 'Egress'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }                
              ]
              targetFqdns: [
                '*.azmk8s.io' 
                'aksrepos.azurecr.io'
                '*.blob.core.windows.net' 
                'mcr.microsoft.com' 
                '*.cdn.mscr.io' 
                'management.azure.com' 
                'login.microsoftonline.com' 
                'packages.azure.com' 
                'acs-mirror.azureedge.net' 
                '*.opinsights.azure.com' 
                '*.monitoring.azure.com' 
                'dc.services.visualstudio.com'
              ]
              sourceAddresses: [
                '10.0.0.0/16'
                '10.1.0.0/16'
              ]
            }
            {
              name: 'Registries'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }                
              ]
              targetFqdns: [
                '*.data.mcr.microsoft.com' 
                '*.azurecr.io' 
                '*.gcr.io' 
                'gcr.io' 
                'storage.googleapis.com' 
                '*.docker.io' 
                'quay.io' 
                '*.quay.io' 
                '*.cloudfront.net' 
                'production.cloudflare.docker.com'
              ]
              sourceAddresses: [
                '10.0.0.0/16'
                '10.1.0.0/16'
              ]
            }
            {
              name: 'Additional-Usefull-Address'
              protocols: [
                {
                  port: 443
                  protocolType: 'Https'
                }                
              ]
              targetFqdns: [
                'grafana.net' 
                'grafana.com' 
                'stats.grafana.org' 
                'github.com' 
                'raw.githubusercontent.com' 
                'security.ubuntu.com' 
                'security.ubuntu.com' 
                'packages.microsoft.com' 
                'azure.archive.ubuntu.com' 
                'security.ubuntu.com' 
                'hack32003.vault.azure.net' 
                '*.letsencrypt.org' 
                'usage.projectcalico.org' 
                'gov-prod-policy-data.trafficmanager.net' 
                'vortex.data.microsoft.com'
              ]
              sourceAddresses: [
                '10.0.0.0/16'
                '10.1.0.0/16'
              ]
            }  
            {
              name: 'AKS-FQDN-TAG'
              protocols: [
                {
                  port: 80
                  protocolType: 'Http'
                }                
                {
                  port: 443
                  protocolType: 'Https'
                }                
              ]
              targetFqdns: []
              fqdnTags: [
                'AzureKubernetesService'
              ]
              sourceAddresses: [
                '10.0.0.0/16'
                '10.1.0.0/16'
              ]
            }                                   
          ]
        }
      }            
    ]
    fwnatRuleCollections: []
    fwnetworkRuleCollections: [
      {
        name: 'AKS-egress'
        properties: {
          priority: 200
          action: {
            type: 'Allow'
          }
          rules: [
            {
              name: 'NTP'
              protocols: [
                'UDP'
              ]
              sourceAddresses: [
                '10.0.0.0/16'
                '10.1.0.0/16'
              ]
              destinationAddresses: [
                '*'
              ]
              destinationPorts: [
                '123'
              ]
            }
          ]
        }
      }      
    ]
  } 
}

module routetable './modules/vnet/routetable.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aks-udr'
  params: {
    rtName: 'aks-udr'
  } 
}

module routetableroutes 'modules/vnet/routetableroutes.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aks-udr-route'
  params: {
    routetableName: 'aks-udr'
    routeName: 'aks-udr-route'
    properties: {
      nextHopType: 'VirtualAppliance'
      nextHopIpAddress: azfirewall.outputs.fwPrivateIP
      addressPrefix: '0.0.0.0/0'      
    }
  }
}

module acrDeploy 'modules/acr/acr.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'acrDeploy'
  params: {
    acrName: acrName
  }
}

resource subnetacrpvt 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' existing = {
  scope: resourceGroup(rg.name)
  name: '${vnetspoke.name}/default'
}

module acrpvtEndpoint 'modules/vnet/privateendpoint.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'acrpvtEndpoint'
  params: {
    privateEndpointName: 'acrpvtEndpoint'
    privateLinkServiceConnections: [
      {
        name: 'acrpvtEndpointConnection'
        properties: {
          privateLinkServiceId: acrDeploy.outputs.acrid
          groupIds: [
            'registry'
          ]
        }
      }
    ]
    subnetid: {
      id: subnetacrpvt.id
    }
  }
}

module privatednsACRZone 'modules/vnet/privatednszone.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'privatednsACRZone'
  params: {
    privateDNSZoneName: 'privatelink.azurecr.io'
  }
}

module privateDNS 'modules/vnet/privatedns.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'privateDNS'
  params: {
    privateDNSZoneName: privatednsACRZone.outputs.privateDNSZoneName
    privateEndpointName: acrpvtEndpoint.outputs.privateEndpointName
    virtualNetworkid: vnetspoke.outputs.vnetId
    privateDNSZoneId: privatednsACRZone.outputs.privateDNSZoneId
  }
}

module akslaworkspace 'modules/laworkspace/la.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'akslaworkspace'
  params: {
    basename: baseName
  }
}

resource subnetaks 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' existing = {
  scope: resourceGroup(rg.name)
  name: '${vnetspoke.name}/AKS'
  /*parent: vnetspoke*/
}

module privatednsAKSZone 'modules/vnet/privatednszone.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'privatednsAKSZone'
  params: {
    privateDNSZoneName: 'privatelink.${deployment().location}.azmk8s.io'
  }
}

module aksHubLink 'modules/vnet/privatdnslink.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aksHubLink'
  params: {
    privateDnsZoneName: privatednsAKSZone.outputs.privateDNSZoneName
    vnetId: vnethub.outputs.vnetId
  }
  
}

module aksIdentity 'modules/Identity/userassigned.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aksIdentity'
  params: {
    basename: baseName
  }
}

resource pvtdnsAKSZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: 'privatelink.${deployment().location}.azmk8s.io'
  scope: resourceGroup(rg.name)
}

module aksCluster 'modules/aks/privateaks.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aksCluster'
  params: {
    aadGroupdIds: [
      'd3fa35e2-6615-40ac-8235-b4339f04a366'
    ]
    basename: baseName
    logworkspaceid: akslaworkspace.outputs.laworkspaceId
    privateDNSZoneId: privatednsAKSZone.outputs.privateDNSZoneId
    subnetId: subnetaks.id
    identity: {
      '${aksIdentity.outputs.identityid}' : {}
    }
    principalId: aksIdentity.outputs.principalId
  }
}

resource subnetVM 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' existing = {
  scope: resourceGroup(rg.name)
  name: '${vnethub.name}/vmsubnet'
  /*parent: vnethub*/
}

module jumpbox 'modules/VM/virtualmachine.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'jumpbox'
  params: {
    subnetId: subnetVM.id
    publicKey: pubkeydata
    script64: script64
  }
}

module publicipbastion 'modules/vnet/publicip.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'publicipbastion'
  params: {
    publicipName: 'bastion-pip'
    publicipproperties: {
      publicIPAllocationMethod: 'Static'      
    }
    publicipsku: {
      name: 'Standard'
      tier: 'Regional'      
    }
  } 
}

resource subnetbastion 'Microsoft.Network/virtualNetworks/subnets@2020-11-01' existing = {
  scope: resourceGroup(rg.name)
  name: '${vnethub.name}/AzureBastionSubnet'
  /*parent: vnethub*/
}

module bastion 'modules/VM/bastion.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'bastion'
  params: {
    bastionpipId: publicipbastion.outputs.publicipId
    subnetId: subnetbastion.id
  }
}
