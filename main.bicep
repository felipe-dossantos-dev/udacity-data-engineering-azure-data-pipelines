param location string = resourceGroup().location
@description('The name of the SQL logical server.')
param serverName string = uniqueString('sql', resourceGroup().id)

@description('The name of the SQL Database.')
param sqlDbName string = 'payroll'

@description('The administrator username of the SQL logical server.')
param administratorLogin string = 'udacity'

param synapseSqlPoolName string = 'sql0'
param blobDataContributorRoleId string = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

@description('The administrator password of the SQL logical server.')
@secure()
param administratorLoginPassword string
param principalId string
param myIp string

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: 'ldfdatalake'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_ZRS'
  }
}

resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: 'ldf-sw'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      resourceId: storageAccount.id
      createManagedPrivateEndpoint: true
      accountUrl: storageAccount.properties.primaryEndpoints.dfs
      filesystem: 'root'
    }
    managedVirtualNetwork: 'default'
    sqlAdministratorLogin: administratorLogin
    sqlAdministratorLoginPassword: administratorLoginPassword
  }
}

resource blobDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: blobDataContributorRoleId
  scope: subscription()
}


resource synapseRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('')
  properties: {
    principalId: principalId
    roleDefinitionId: blobDataContributorRoleDefinition.id
  }
}

resource synapseSqlPool 'Microsoft.Synapse/workspaces/sqlPools@2021-06-01' = {
  parent: synapseWorkspace
  location: location
  name: synapseSqlPoolName
  sku: {
    name: 'DW100c'
  }
  properties: {
    createMode: 'Default'
  }
}

resource synapseFirewallAzureServicesAllow 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = {
  parent: synapseWorkspace
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource synapseFirewallMeAllow 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = {
  parent: synapseWorkspace
  name: 'me'
  properties: {
    startIpAddress: myIp
    endIpAddress: myIp
  }
}

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: 'ldf-data-factory'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
}

resource sqlServer 'Microsoft.Sql/servers@2021-08-01-preview' = {
  name: serverName
  location: location
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
  }
}

resource sqlServerAllowMeIp 'Microsoft.Sql/servers/firewallRules@2022-05-01-preview' = {
  parent: sqlServer
  name: 'me'
  properties: {
    startIpAddress: myIp
    endIpAddress: myIp
  }
}

resource sqlServerAllowAzureIp 'Microsoft.Sql/servers/firewallRules@2022-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2021-08-01-preview' = {
  parent: sqlServer
  name: sqlDbName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
}

resource dataFactoryLinkedSql 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name : 'sql-server-linked-service'
  properties: {
    type: 'AzureSqlDatabase'
    typeProperties: {
      connectionString: 'Server=${sqlServer.properties.fullyQualifiedDomainName};Initial Catalog=${sqlDbName};Persist Security Info=False;User ID=${administratorLogin};Password=${administratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
    }
  }
}

resource dataFactoryLinkedBlob 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: 'blob-linked-service'
  properties: {
    type: 'AzureBlobStorage'
    typeProperties: {
      connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value}'
    }
  }
}

resource dataFactoryLinkedSynapse 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name : 'synapse-linked-service'
  properties: {
    type: 'AzureSqlDW'
    typeProperties: {
      connectionString: 'Server=${synapseWorkspace.name}.sql.azuresynapse.net,1433;Initial Catalog=${synapseSqlPoolName};User ID=${administratorLogin}@${synapseWorkspace.name};Password=${administratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
    }
  }
}

resource dataSetInCsvPayroll 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'in-csv-nycpayroll'
  properties: {
    linkedServiceName: {
      referenceName: dataFactoryLinkedBlob.name
      type: 'LinkedServiceReference'
    }
    type: 'Binary'
    typeProperties: {
      location: {
        type: 'AzureBlobStorageLocation'
        container: 'adlsnycpayroll-felipe-s'
        folderPath: 'dirpayrollfiles'
        fileName: 'nycpayroll_2021.csv'
      }
    }
  }
}

resource dataSetInCsvTitleMaster 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'in-csv-title-master'
  properties: {
    linkedServiceName: {
      referenceName: dataFactoryLinkedBlob.name
      type: 'LinkedServiceReference'
    }
    type: 'Binary'
    typeProperties: {
      location: {
        type: 'AzureBlobStorageLocation'
        container: 'adlsnycpayroll-felipe-s'
        folderPath: 'dirpayrollfiles'
        fileName: 'TitleMaster.csv'
      }
    }
  }
}

resource dataSetInCsvEmpMaster 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'in-csv-emp-master'
  properties: {
    linkedServiceName: {
      referenceName: dataFactoryLinkedBlob.name
      type: 'LinkedServiceReference'
    }
    type: 'Binary'
    typeProperties: {
      location: {
        type: 'AzureBlobStorageLocation'
        container: 'adlsnycpayroll-felipe-s'
        folderPath: 'dirpayrollfiles'
        fileName: 'EmpMaster.csv'
      }
    }
  }
}

resource dataSetInCsvAgencyMaster 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'in-csv-agency-master'
  properties: {
    linkedServiceName: {
      referenceName: dataFactoryLinkedBlob.name
      type: 'LinkedServiceReference'
    }
    type: 'Binary'
    typeProperties: {
      location: {
        type: 'AzureBlobStorageLocation'
        container: 'adlsnycpayroll-felipe-s'
        folderPath: 'dirpayrollfiles'
        fileName: 'AgencyMaster.csv'
      }
    }
  }
}

resource dataSetOutTransctionalSql 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'ds-sql-payroll-data'
  properties: {
    linkedServiceName: {
      referenceName: dataFactoryLinkedSql.name
      type: 'LinkedServiceReference'
    }
    type:'AzureSqlTable'
    typeProperties:{
      schema: 'dbo'
      table: 'NYC_Payroll_Data'
    }
  }
}

resource dataSetOutSynapseEmp 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'out-synapse-emp-md'
  properties: {
    linkedServiceName: {
      referenceName: dataFactoryLinkedSynapse.name
      type: 'LinkedServiceReference'
    }
    type:'AzureSqlDWTable'
    typeProperties:{
      schema: 'dbo'
      table: 'NYC_Payroll_EMP_MD'
    }
  }
}

resource dataSetOutSynapseTitle 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'out-synapse-title-md'
  properties: {
    linkedServiceName: {
      referenceName: dataFactoryLinkedSynapse.name
      type: 'LinkedServiceReference'
    }
    type:'AzureSqlDWTable'
    typeProperties:{
      schema: 'dbo'
      table: 'NYC_Payroll_TITLE_MD'
    }
  }
}

resource dataSetOutSynapseAgency 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'out-synapse-agency-md'
  properties: {
    linkedServiceName: {
      referenceName: dataFactoryLinkedSynapse.name
      type: 'LinkedServiceReference'
    }
    type:'AzureSqlDWTable'
    typeProperties:{
      schema: 'dbo'
      table: 'NYC_Payroll_AGENCY_MD'
    }
  }
}

resource dataSetOutSynapsePayroll 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'out-synapse-payroll-md'
  properties: {
    linkedServiceName: {
      referenceName: dataFactoryLinkedSynapse.name
      type: 'LinkedServiceReference'
    }
    type:'AzureSqlDWTable'
    typeProperties:{
      schema: 'dbo'
      table: 'NYC_Payroll_Data'
    }
  }
}
