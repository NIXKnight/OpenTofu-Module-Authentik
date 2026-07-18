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

# Note: authentik_outpost (provider 2024.10.x) exposes no readable token attribute,
# so the outpost's auto-generated token cannot be surfaced as an output. Retrieve it
# from the authentik UI (Outposts view) after apply.
