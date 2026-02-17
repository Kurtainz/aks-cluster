variable "cloudflare_api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "flux_ssh_key" {
  description = "SSH Private Key for FluxCD Git sync"
  type        = string
  sensitive   = true
}
