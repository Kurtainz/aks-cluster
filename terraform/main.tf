terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "aks_rg" {
  name     = "aks-test"
  location = "uksouth"
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "experiment-cluster"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  sku_tier            = "Free"
  dns_prefix          = "aks-test"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_A2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}
