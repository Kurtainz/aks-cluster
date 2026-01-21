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
  name                      = "experiment-cluster"
  location                  = azurerm_resource_group.aks_rg.location
  resource_group_name       = azurerm_resource_group.aks_rg.name
  sku_tier                  = "Free"
  dns_prefix                = "aks-test"
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_A2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_user_assigned_identity" "eso_identity" {
  name                = "id-eso-secrets-manager"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
}

resource "azurerm_role_assignment" "eso_kv_secrets" {
  scope                = azurerm_key_vault.aks-cluster-vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.eso_identity.principal_id
}

resource "azurerm_federated_identity_credential" "eso_federated" {
  name                = "eso-federated-credential"
  resource_group_name = azurerm_resource_group.aks_rg.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.eso_identity.id
  subject             = "system:serviceaccount:external-secrets:external-secrets-sa"
}

resource "azurerm_kubernetes_cluster_extension" "flux" {
  name           = "flux"
  cluster_id     = azurerm_kubernetes_cluster.aks.id
  extension_type = "microsoft.flux"
}

resource "azurerm_kubernetes_flux_configuration" "aks_sync" {
  name       = "aks-system"
  cluster_id = azurerm_kubernetes_cluster.aks.id
  namespace  = "flux-system"
  scope      = "cluster"

  git_repository {
    url             = "https://github.com/Kurtainz/aks-cluster"
    reference_type  = "branch"
    reference_value = "main"

    ssh_private_key_base64 = base64encode(file("~/.ssh/aks-cluster"))
  }

  kustomizations {
    name                      = "infra-controllers"
    path                      = "./kubernetes/infrastructure/controllers/staging"
    sync_interval_in_seconds  = 300
  }

  kustomizations {
    name                      = "infra-configs"
    path                      = "./kubernetes/infrastructure/configs/staging"
    sync_interval_in_seconds  = 300
    depends_on                = ["infra-controllers"]
  }

  kustomizations {
    name                      = "apps"
    path                      = "./kubernetes/apps/staging"
    sync_interval_in_seconds  = 300
    # This ensures infra (Ingress/Cert-Manager) is ready before apps deploy
    depends_on                = ["infra-configs"]
  }

  depends_on = [azurerm_kubernetes_cluster_extension.flux]
}

## Key vault

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "aks-cluster-vault" {
  name                = "kv-aks-cluster-staging"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  enable_rbac_authorization = true
  depends_on                 = [azurerm_kubernetes_cluster.aks]
}

resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.aks-cluster-vault.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

