terraform {
  required_version = ">= 1.6"

  required_providers {
    authentik = {
      source = "goauthentik/authentik"
      # EXACT pin. The consuming terragrunt unit gitignores .terraform.lock.hcl, so
      # this constraint string is the ONLY thing pinning provider resolution; a range
      # would let the lock-less unit drift to a breaking release. goauthentik/authentik
      # provider versions track the live authentik SERVER release, so bump this pin in
      # lockstep with every server upgrade (server currently 2026.5.5). Historical note:
      # the 2024.10.x era decoded redirect_uris as a flat string; the 2026.5 line takes
      # the structured allowed_redirect_uris API instead (see main.tf).
      version = "= 2026.5.0"
    }
  }
}

provider "authentik" {
  url      = var.authentik_url
  token    = var.authentik_token
  insecure = var.authentik_insecure
}
