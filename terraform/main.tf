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

# Generate a random password for the Postgres database automatically
resource "random_password" "n8n_db_pass" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Add the generated password to Key Vault
resource "azurerm_key_vault_secret" "db_password" {
  name         = "n8n-postgres-password"
  value        = random_password.n8n_db_pass.result
  key_vault_id = azurerm_key_vault.aks-cluster-vault.id
}

resource "cloudflare_zero_trust_tunnel" "prod_tunnel" {
  account_id = var.cloudflare_account_id
  name       = "app-production-tunnel"
  secret     = var.tunnel_secret
}

# Store the token for Cloudflare Tunnel in the key vault
resource "azurerm_key_vault_secret" "tunnel_token" {
  name         = "cloudflare-tunnel-token"
  value        = cloudflare_zero_trust_tunnel.prod_tunnel.tunnel_token
  key_vault_id = azurerm_key_vault.aks-cluster-vault.id
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

    ssh_private_key_base64 = base64encode(var.flux_ssh_key)
  }

  kustomizations {
    name = "cluster-bootstrap"
    path = "./kubernetes/clusters/staging"
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

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

resource "kubernetes_config_map_v1" "flux_vars" {
  metadata {
    name      = "cluster-vars"
    namespace = "flux-system"
  }

  data = {
    ESO_CLIENT_ID = azurerm_user_assigned_identity.eso_identity.client_id
    TENANT_ID     = data.azurerm_client_config.current.tenant_id
  }
}

