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
