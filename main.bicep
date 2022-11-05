param location string = resourceGroup().location
@description('The name of the SQL logical server.')
param serverName string = uniqueString('sql', resourceGroup().id)

@description('The name of the SQL Database.')
param sqlDbName string = 'payroll'

@description('The administrator username of the SQL logical server.')
param administratorLogin string = 'udacity'

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
  name: 'sql0'
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
      connectionString: 'Server=${sqlServer.properties.fullyQualifiedDomainName};Initial Catalog=payroll;Persist Security Info=False;User ID=udacity;Password=${administratorLoginPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
    }
  }
}
