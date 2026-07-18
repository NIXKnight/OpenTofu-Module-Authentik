terraform {
  required_version = ">= 1.6"

  required_providers {
    authentik = {
      source = "goauthentik/authentik"
      # Pinned to the 2024.10.x series to match the live authentik server (2024.10.1).
      # `~> 2024.10.0` resolves to ">= 2024.10.0, < 2024.11.0" (newest in series: 2024.10.2).
      # A bare `~> 2024.10` widens to "< 2025.0.0" and would pull 2024.12.x, whose provider
      # assumes newer server APIs; that series is intentionally excluded.
      version = "~> 2024.10.0"
    }
  }
}

provider "authentik" {
  url      = var.authentik_url
  token    = var.authentik_token
  insecure = var.authentik_insecure
}
