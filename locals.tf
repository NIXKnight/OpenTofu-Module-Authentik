locals {
  # Decompose the app-centric `applications` map into provider-typed subsets.
  # The map key is preserved as the for_each key of each downstream resource,
  # keeping existing state addresses (e.g. ["jenkins"], ["grafana"]) intact.
  oauth2_applications = { for k, a in var.applications : k => a if a.type == "oauth2" }
  proxy_applications  = { for k, a in var.applications : k => a if a.type == "proxy" }

  # Application UUIDs (policy-binding targets), keyed by application key.
  application_uuids = merge(
    { for k, a in local.oauth2_applications : k => authentik_application.oauth2_applications[k].uuid },
    { for k, a in local.proxy_applications : k => authentik_application.proxy_applications[k].uuid },
  )

  # Proxy provider ids keyed by application key (for outpost protocol_providers).
  proxy_provider_ids = {
    for k, a in local.proxy_applications : k => authentik_provider_proxy.proxy_providers[k].id
  }

  # authentik auto-creates a service account named "ak-outpost-<outpost name>" for
  # each outpost. Centralized here so a provider-side naming change is a one-line edit.
  outpost_sa_prefix = "ak-outpost-"

  # Group ids keyed by group key.
  group_ids = { for k, g in var.groups : k => authentik_group.groups[k].id }

  # Combined user pks (regular users + service accounts) keyed by their map key.
  user_pks = merge(
    { for k, u in var.users : k => authentik_user.users[k].id },
    { for k, s in var.service_accounts : k => authentik_user.service_accounts[k].id },
  )

  # Stable-keyed policy bindings for for_each (a list variable needs a set of keys).
  policy_bindings = {
    for b in var.policy_bindings :
    "${b.application}:${b.group != null ? "group" : "user"}:${coalesce(b.group, b.user)}:${b.order}" => b
  }
}
