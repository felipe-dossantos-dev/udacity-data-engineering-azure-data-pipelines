# udacity-data-engineering-data-pipelines

az deployment group create -g learning-data-factory -f main.bicep -p main.parameters.json

- get roles definitions
az role definition list -g learning-data-factory > output.json

- get my principal id:
az ad signed-in-user show