resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "prod_tunnel" {
  account_id        = var.cloudflare_account_id
  name              = "app-production-tunnel"
  tunnel_secret     = random_id.tunnel_secret.b64_std
  config_src        = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "prod_tunnel_token" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.prod_tunnel.id
}

# Store the token for Cloudflare Tunnel in the key vault
resource "azurerm_key_vault_secret" "tunnel_token" {
  name         = "cloudflare-tunnel-token"
  value        = data.cloudflare_zero_trust_tunnel_cloudflared_token.prod_tunnel_token.token
  key_vault_id = azurerm_key_vault.aks-cluster-vault.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "n8n_config" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.prod_tunnel.id

  config {
    ingress_rule {
      hostname = "n8n.kclabcloud.com"
      service  = "http://n8n.n8n.svc.cluster.local:5678"
    }

    # Catch-all rule: This is REQUIRED by Cloudflare.
    # It returns a 404 for any traffic that doesn't match the hostname above.
    ingress_rule {
      service = "http_status:404"
    }
  }
}

resource "cloudflare_dns_record" "n8n_dns" {
  zone_id = var.cloudflare_zone_id
  name    = "n8n"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.prod_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}
