terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.79"
    }
    random = {
      source = "hashicorp/random"
    }
  }

  required_version = ">= 0.14.9"
}

data "azurerm_client_config" "current" {}
# Configure Azure Provider
provider "azurerm" {
  # Version is optional
  # Terraform recommends to pin to a specific version of provider
  #version = "=2.35.0"
  #version = "~>2.35.0"
  #version = "~> 2.37.0"
  features {}
}

provider "random" {
  # Version is optional
  # Terraform recommends to pin to a specific version of provider
  #version = "=2.35.0"
}

resource "random_integer" "ri" {
  min = 10000
  max = 99999
}

#resource group
resource "azurerm_resource_group" "ocrdemorg" {
  name     = "${var.resource_group_name}-${random_integer.ri.result}"
  location = var.resource_group_location
}

#Azure function
resource "azurerm_storage_account" "functionstorage" {
  name                     = "functionsappocrsa${random_integer.ri.result}"
  resource_group_name      = azurerm_resource_group.ocrdemorg.name
  location                 = azurerm_resource_group.ocrdemorg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_app_service_plan" "ocrfunctionappserviceplan" {
  name                = "azure-functions-ocr-service-plan${random_integer.ri.result}"
  location            = azurerm_resource_group.ocrdemorg.location
  resource_group_name = azurerm_resource_group.ocrdemorg.name
  kind                = "FunctionApp"

  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_function_app" "ocrfunction" {
  name                       = "ocr-functions${random_integer.ri.result}"
  location                   = azurerm_resource_group.ocrdemorg.location
  resource_group_name        = azurerm_resource_group.ocrdemorg.name
  app_service_plan_id        = azurerm_app_service_plan.ocrfunctionappserviceplan.id
  storage_account_name       = azurerm_storage_account.functionstorage.name
  storage_account_access_key = azurerm_storage_account.functionstorage.primary_access_key
  version                    = "~3"

  identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_cognitive_account.cognitiveservices,
    azurerm_storage_account.ocrblobstorage
  ]

  app_settings = {
    OcrApiKey                       = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.ocrkeyvault.vault_uri}secrets/${azurerm_key_vault_secret.ocrkey.name}/${azurerm_key_vault_secret.ocrkey.version})",
    OcrEndPoint                     = "${azurerm_cognitive_account.cognitiveservices.endpoint}vision/v2.0/ocr",
    simpleocrstorage_STORAGE        = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.ocrkeyvault.vault_uri}secrets/${azurerm_key_vault_secret.storageprimaryconstring.name}/${azurerm_key_vault_secret.storageprimaryconstring.version})"
    CosmosDbConnectionString        = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.ocrkeyvault.vault_uri}secrets/${azurerm_key_vault_secret.cosmosdbconstring.name}/${azurerm_key_vault_secret.cosmosdbconstring.version})"
    WEBSITE_ENABLE_SYNC_UPDATE_SITE = true
    WEBSITE_RUN_FROM_PACKAGE        = 1
  }
}

#Blob storage
resource "azurerm_storage_account" "ocrblobstorage" {
  name                     = "ocrblobstorage${random_integer.ri.result}"
  resource_group_name      = azurerm_resource_group.ocrdemorg.name
  location                 = azurerm_resource_group.ocrdemorg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "ocrstoragecontainer" {
  name                  = var.storage_containername
  storage_account_name  = azurerm_storage_account.ocrblobstorage.name
  container_access_type = "private"
}

#Cosmos db
resource "azurerm_cosmosdb_account" "ocrcosmosdbaccount" {
  name                = "ocr-cosmos-db-${random_integer.ri.result}"
  location            = azurerm_resource_group.ocrdemorg.location
  resource_group_name = azurerm_resource_group.ocrdemorg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "BoundedStaleness"
  }

  geo_location {
    location          = azurerm_resource_group.ocrdemorg.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "ocrcosmossqldb" {
  name                = "db2"
  resource_group_name = azurerm_cosmosdb_account.ocrcosmosdbaccount.resource_group_name
  account_name        = azurerm_cosmosdb_account.ocrcosmosdbaccount.name
  throughput          = 400
}

resource "azurerm_cosmosdb_sql_container" "ocrcontainer" {
  name                  = "Container2"
  resource_group_name   = azurerm_cosmosdb_account.ocrcosmosdbaccount.resource_group_name
  account_name          = azurerm_cosmosdb_account.ocrcosmosdbaccount.name
  database_name         = azurerm_cosmosdb_sql_database.ocrcosmossqldb.name
  partition_key_path    = "/id"
  partition_key_version = 1
  throughput            = 400

  indexing_policy {
    indexing_mode = "Consistent"

    included_path {
      path = "/*"
    }
  }
}

resource "azurerm_cognitive_account" "cognitiveservices" {
  name                = "cognitiveservices${random_integer.ri.result}"
  location            = azurerm_resource_group.ocrdemorg.location
  resource_group_name = azurerm_resource_group.ocrdemorg.name
  kind                = "ComputerVision"

  sku_name = "F0"
}

#Azure keyvault
resource "azurerm_key_vault" "ocrkeyvault" {
  name                        = "ocrkeyvault${random_integer.ri.result}"
  location                    = azurerm_resource_group.ocrdemorg.location
  resource_group_name         = azurerm_resource_group.ocrdemorg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"
}
output "cosmosdb_connectionstrings" {
  value     = azurerm_cosmosdb_account.ocrcosmosdbaccount.connection_strings
  sensitive = true
}

resource "azurerm_key_vault_secret" "cosmosdbconstring" {
  name         = "CosmosDbConnectionString"
  value        = azurerm_cosmosdb_account.ocrcosmosdbaccount.connection_strings[0]
  key_vault_id = azurerm_key_vault.ocrkeyvault.id
  depends_on = [
    azurerm_cosmosdb_account.ocrcosmosdbaccount,
    azurerm_key_vault_access_policy.accesspolicydefault
  ]
}

resource "azurerm_key_vault_secret" "ocrkey" {
  name         = "OcrApiKey"
  value        = azurerm_cognitive_account.cognitiveservices.primary_access_key
  key_vault_id = azurerm_key_vault.ocrkeyvault.id
  depends_on = [
    azurerm_cognitive_account.cognitiveservices,
    azurerm_key_vault_access_policy.accesspolicydefault
  ]
}

resource "azurerm_key_vault_secret" "storageprimaryconstring" {
  name         = "PrimaryStorageConString"
  value        = azurerm_storage_account.ocrblobstorage.primary_connection_string
  key_vault_id = azurerm_key_vault.ocrkeyvault.id
  depends_on = [
    azurerm_storage_account.ocrblobstorage,
    azurerm_key_vault_access_policy.accesspolicydefault
  ]
}

resource "azurerm_key_vault_secret" "cosmosdbprimarykey" {
  name         = "CosmosDBPrimaryKey"
  value        = azurerm_cosmosdb_account.ocrcosmosdbaccount.primary_key
  key_vault_id = azurerm_key_vault.ocrkeyvault.id
  depends_on = [
    azurerm_cosmosdb_account.ocrcosmosdbaccount,
    azurerm_key_vault_access_policy.accesspolicydefault
  ]
}

resource "azurerm_key_vault_access_policy" "accesspolicydefault" {
  key_vault_id = azurerm_key_vault.ocrkeyvault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
    "Backup",
    "Restore",
    "Purge"
  ]
}

resource "azurerm_key_vault_access_policy" "accesspolicywebapp" {
  key_vault_id = azurerm_key_vault.ocrkeyvault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_app_service.ocrwebapp.identity.0.principal_id
  depends_on = [
    azurerm_app_service.ocrwebapp,
    azurerm_key_vault_access_policy.accesspolicydefault
  ]

  secret_permissions = [
    "Get",
    "List"
  ]
}

resource "azurerm_key_vault_access_policy" "accesspolicyocrfunction" {
  key_vault_id = azurerm_key_vault.ocrkeyvault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_function_app.ocrfunction.identity.0.principal_id
  depends_on = [
    azurerm_function_app.ocrfunction,
    azurerm_key_vault_access_policy.accesspolicydefault
  ]

  secret_permissions = [
    "Get",
    "List"
  ]
}

#App service (web app)
resource "azurerm_app_service_plan" "webappserviceplan" {
  name                = "ocrwebapp-appserviceplan${random_integer.ri.result}"
  location            = azurerm_resource_group.ocrdemorg.location
  resource_group_name = azurerm_resource_group.ocrdemorg.name
  //kind = "Linux"
  //reserved = true


  sku {
    tier = "Free"
    size = "F1"
  }
}

resource "azurerm_app_service" "ocrwebapp" {
  name                = "ocrwebapp-service${random_integer.ri.result}"
  location            = azurerm_resource_group.ocrdemorg.location
  resource_group_name = azurerm_resource_group.ocrdemorg.name
  app_service_plan_id = azurerm_app_service_plan.webappserviceplan.id
  
  app_settings = {
    "CosmosDb:DatabaseName" = var.cosmosdb_dbname,
    "CosmosDb:ContainerName" = var.cosmosdb_containername,
    "CosmosDb:Key" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.ocrkeyvault.vault_uri}secrets/${azurerm_key_vault_secret.cosmosdbprimarykey.name}/${azurerm_key_vault_secret.cosmosdbprimarykey.version})",
    "CosmosDb:Account" = azurerm_cosmosdb_account.ocrcosmosdbaccount.endpoint
  }
  
  identity {
    type = "SystemAssigned"
  }

  /*
  connection_string {
    name  = "AppConfig"
    type  = "Custom"
    value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.ocrkeyvault.vault_uri}secrets/${azurerm_key_vault_secret.appconfconstring.name}/${azurerm_key_vault_secret.appconfconstring.version})"

  }
  */
}