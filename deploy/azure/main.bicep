@description('Azure region selected by the operator after reviewing availability and pricing.')
param location string

@description('VM name. Use a new, non-production staging name.')
@minLength(1)
@maxLength(64)
param vmName string = 'learning-calculator-stage'

@description('Linux administrator account. Password authentication is disabled.')
@minLength(1)
param adminUsername string

@description('Exact Canonical Ubuntu 24.04 image version selected by the operator; do not use latest.')
@minLength(1)
param ubuntuImageVersion string

@description('SSH public key for the administrator account; never provide a private key.')
@minLength(1)
param adminSshPublicKey string

@description('Non-overlapping private address range selected for this VNet.')
@minLength(1)
param vnetAddressPrefix string

@description('Subnet range contained in vnetAddressPrefix, selected by the operator.')
@minLength(1)
param subnetAddressPrefix string

@description('VM size selected by the operator after reviewing pricing and encryption-at-host support.')
@minLength(1)
param vmSize string

@description('OS managed-disk SKU selected by the operator.')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param osDiskSku string

@description('Separate SQLite data managed-disk SKU selected by the operator.')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param dataDiskSku string

@description('Optional approved private management CIDR for SSH. Leave empty to deny all inbound traffic.')
param managementSourceAddressPrefix string = ''

@description('SQLite data-disk capacity in GiB, selected by the operator.')
@minValue(4)
param dataDiskSizeGiB int

var vnetName = '${vmName}-vnet'
var subnetName = 'service'
var nsgName = '${vmName}-nsg'
var nicName = '${vmName}-nic'
var dataDiskName = '${vmName}-data'

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  tags: {
    purpose: 'staging'
    dataClass: 'no-learner-data'
  }
  properties: {
    securityRules: empty(managementSourceAddressPrefix)
      ? [
          {
            name: 'deny-all-inbound'
            properties: {
              priority: 100
              direction: 'Inbound'
              access: 'Deny'
              protocol: '*'
              sourcePortRange: '*'
              destinationPortRange: '*'
              sourceAddressPrefix: '*'
              destinationAddressPrefix: '*'
            }
          }
        ]
      : [
          {
            name: 'allow-private-management-ssh'
            properties: {
              priority: 100
              direction: 'Inbound'
              access: 'Allow'
              protocol: 'Tcp'
              sourcePortRange: '*'
              destinationPortRange: '22'
              sourceAddressPrefix: managementSourceAddressPrefix
              destinationAddressPrefix: '*'
            }
          }
          {
            name: 'deny-all-other-inbound'
            properties: {
              priority: 4096
              direction: 'Inbound'
              access: 'Deny'
              protocol: '*'
              sourcePortRange: '*'
              destinationPortRange: '*'
              sourceAddressPrefix: '*'
              destinationAddressPrefix: '*'
            }
          }
        ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: {
    purpose: 'staging'
    dataClass: 'no-learner-data'
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  tags: {
    purpose: 'staging'
    dataClass: 'no-learner-data'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'primary'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'
          }
        }
      }
    ]
  }
}

resource dataDisk 'Microsoft.Compute/disks@2023-10-02' = {
  name: dataDiskName
  location: location
  sku: {
    name: dataDiskSku
  }
  tags: {
    purpose: 'staging'
    dataClass: 'no-learner-data'
    backup: 'excluded'
  }
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: dataDiskSizeGiB
    encryption: {
      type: 'EncryptionAtRestWithPlatformKey'
    }
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-10-02' = {
  name: vmName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  tags: {
    purpose: 'staging'
    dataClass: 'no-learner-data'
    backup: 'os-disk-only'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    securityProfile: {
      encryptionAtHost: true
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: ubuntuImageVersion
      }
      osDisk: {
        name: '${vmName}-os'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskSku
        }
      }
      dataDisks: [
        {
          lun: 0
          name: dataDiskName
          createOption: 'Attach'
          caching: 'None'
          managedDisk: {
            id: dataDisk.id
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

output vmId string = vm.id
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output dataDiskId string = dataDisk.id
