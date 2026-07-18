terraform {
  required_version = ">= 1.6"

  required_providers {
    authentik = {
      source = "goauthentik/authentik"
      # EXACT pin. The consuming terragrunt unit gitignores .terraform.lock.hcl, so
      # this constraint string is the ONLY thing pinning the unit's provider
      # resolution; a range would let the lock-less unit drift to a breaking release.
      #
      # Coupling to the live authentik SERVER (2024.10.x): that server serializes
      # OAuth2Provider.redirect_uris as a plain STRING on GET (2024.10 shipped no
      # structured-redirect change). goauthentik/client-go is generated from
      # authentik's MAIN branch, so a client's version number does NOT track the
      # stable server: the bundled client's RedirectUris field flipped from *string
      # to []RedirectURI between api v3.2024100.2 and v3.2024102.6. Provider v2024.10.2
      # (released 2024-11-22) absorbed the structured client (api v3.2024104.1) via
      # dependabot and therefore fails to decode this server's string response
      # ("json: cannot unmarshal string ... into []api.RedirectURI").
      # v2024.10.1 bundles api v3.2024100.2 — the NEWEST provider whose client still
      # decodes redirect_uris as a string. Bump this pin in lockstep with the authentik
      # server upgrade (main.tf's redirect_uris expression changes with it).
      version = "= 2024.10.1"
    }
  }
}

provider "authentik" {
  url      = var.authentik_url
  token    = var.authentik_token
  insecure = var.authentik_insecure
}
