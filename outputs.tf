output "service_account_app_passwords" {
  description = "App-password token keys per service account, keyed by service-account map key."
  sensitive   = true
  value       = { for k, t in authentik_token.service_accounts : k => t.key }
}

output "application_slugs" {
  description = "Slug of every managed application, keyed by application map key."
  value = merge(
    { for k, a in authentik_application.oauth2_applications : k => a.slug },
    { for k, a in authentik_application.proxy_applications : k => a.slug },
  )
}

output "outpost_ids" {
  description = "IDs of managed proxy outposts, keyed by outpost name."
  value       = { for k, o in authentik_outpost.proxy : k => o.id }
}

output "outpost_tokens" {
  description = "Module-minted API token keys per proxy outpost service account, keyed by outpost name."
  sensitive   = true
  value       = { for k, t in authentik_token.outpost_api : k => t.key }
}

# Note: authentik_outpost (provider 2024.10.x) exposes no readable attribute for the
# outpost's OWN auto-generated token, so that token cannot be surfaced directly. The
# `outpost_tokens` output above instead mints a parallel API token on the same service
# account; retrieve the auto-generated one from the authentik UI if it is needed.

output "oauth2_client_credentials" {
  description = "Client ID and secret per OAuth2 application map key."
  sensitive   = true
  value = {
    for k, p in authentik_provider_oauth2.oauth2_providers :
    k => {
      client_id     = p.client_id
      client_secret = p.client_secret
    }
  }
}
