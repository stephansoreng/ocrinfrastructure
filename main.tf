terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.79"
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

#resource group
resource "azurerm_resource_group" "ocrdemorg" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

#Azure function
resource "azurerm_storage_account" "functionstorage" {
  name                     = "functionsappocrsa"
  resource_group_name      = azurerm_resource_group.ocrdemorg.name
  location                 = azurerm_resource_group.ocrdemorg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_app_service_plan" "ocrfunctionappserviceplan" {
  name                = "azure-functions-ocr-service-plan"
  location            = azurerm_resource_group.ocrdemorg.location
  resource_group_name = azurerm_resource_group.ocrdemorg.name
  kind                = "FunctionApp"

  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_function_app" "ocrfunction" {
  name                       = "ocr-functions"
  location                   = azurerm_resource_group.ocrdemorg.location
  resource_group_name        = azurerm_resource_group.ocrdemorg.name
  app_service_plan_id        = azurerm_app_service_plan.ocrfunctionappserviceplan.id
  storage_account_name       = azurerm_storage_account.functionstorage.name
  storage_account_access_key = azurerm_storage_account.functionstorage.primary_access_key
}

#App configuration
resource "azurerm_app_configuration" "appconf" {
  name                = "appConf1"
  resource_group_name = azurerm_resource_group.ocrdemorg.name
  location            = azurerm_resource_group.ocrdemorg.location
}

#Azure keyvault
resource "azurerm_key_vault" "ocrkeyvault" {
  name                        = "ocrkeyvault1001"
  location                    = azurerm_resource_group.ocrdemorg.location
  resource_group_name         = azurerm_resource_group.ocrdemorg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
    ]

    storage_permissions = [
      "Get",
    ]
  }
}
