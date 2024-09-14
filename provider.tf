terraform {
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = ">= 2024.6.0, < 2024.8.0"
    }
  }
}
