# ---------------------------------------------------------------------------
# Data sources (re-read every plan; no destroy risk)
# ---------------------------------------------------------------------------

data "authentik_flow" "authorization" {
  slug = var.authorization_flow_slug
}

# Provider >= 2024.10 requires invalidation_flow on every provider resource.
data "authentik_flow" "invalidation" {
  slug = var.invalidation_flow_slug
}

data "authentik_certificate_key_pair" "signing" {
  name = var.signing_key_name
}

# OAuth2 scope property-mappings, resolved per application from managed identifiers.
data "authentik_property_mapping_provider_scope" "oauth2" {
  for_each     = { for k, a in local.oauth2_applications : k => a if length(a.scopes) > 0 }
  managed_list = each.value.scopes
}

# ---------------------------------------------------------------------------
# OAuth2 applications + providers
# for_each key = application map key ("jenkins"/"grafana"), preserving the
# existing authentik_provider_oauth2.oauth2_providers[...] state addresses.
# ---------------------------------------------------------------------------

resource "authentik_provider_oauth2" "oauth2_providers" {
  for_each = local.oauth2_applications

  name               = each.value.name
  client_id          = each.value.client_id
  client_secret      = each.value.client_secret
  client_type        = each.value.client_type
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id
  signing_key        = data.authentik_certificate_key_pair.signing.id
  property_mappings  = length(each.value.scopes) > 0 ? try(data.authentik_property_mapping_provider_scope.oauth2[each.key].ids, null) : null

  # Provider 2026.5.0 takes the structured allowed_redirect_uris API (list of
  # {url, matching_mode}), mapping directly onto the public variable's {url,
  # matching_mode?} shape so per-URI matching_mode is now honored.
  allowed_redirect_uris = [for r in each.value.redirect_uris : { url = r.url, matching_mode = r.matching_mode }]

  sub_mode                   = each.value.sub_mode
  include_claims_in_id_token = each.value.include_claims_in_id_token
  issuer_mode                = each.value.issuer_mode
  access_code_validity       = each.value.access_code_validity
  access_token_validity      = each.value.access_token_validity
  refresh_token_validity     = each.value.refresh_token_validity
}

resource "authentik_application" "oauth2_applications" {
  for_each = local.oauth2_applications

  name               = each.value.name
  slug               = each.value.slug
  protocol_provider  = authentik_provider_oauth2.oauth2_providers[each.key].id
  group              = each.value.group
  meta_description   = each.value.meta_description
  meta_publisher     = each.value.meta_publisher
  meta_launch_url    = each.value.meta_launch_url
  meta_icon          = each.value.meta_icon
  open_in_new_tab    = each.value.open_in_new_tab
  policy_engine_mode = each.value.policy_engine_mode
}

# State preservation: authentik_application.applications was renamed to
# authentik_application.oauth2_applications. This whole-resource move keeps every
# instance key (e.g. "jenkins", "grafana") without a destroy/replace and is a
# no-op for fresh consumers that never had the old address.
moved {
  from = authentik_application.applications
  to   = authentik_application.oauth2_applications
}

# ---------------------------------------------------------------------------
# Proxy applications + providers
# Separate resource blocks so the OAuth2-backed addresses above stay untouched.
# ---------------------------------------------------------------------------

resource "authentik_provider_proxy" "proxy_providers" {
  for_each = local.proxy_applications

  name                         = each.value.name
  authorization_flow           = data.authentik_flow.authorization.id
  invalidation_flow            = data.authentik_flow.invalidation.id
  external_host                = each.value.external_host
  internal_host                = each.value.internal_host
  mode                         = each.value.mode
  intercept_header_auth        = each.value.intercept_header_auth
  internal_host_ssl_validation = each.value.internal_host_ssl_validation
  skip_path_regex              = each.value.skip_path_regex
}

resource "authentik_application" "proxy_applications" {
  for_each = local.proxy_applications

  name               = each.value.name
  slug               = each.value.slug
  protocol_provider  = authentik_provider_proxy.proxy_providers[each.key].id
  group              = each.value.group
  meta_description   = each.value.meta_description
  meta_publisher     = each.value.meta_publisher
  meta_launch_url    = each.value.meta_launch_url
  meta_icon          = each.value.meta_icon
  open_in_new_tab    = each.value.open_in_new_tab
  policy_engine_mode = each.value.policy_engine_mode
}

# ---------------------------------------------------------------------------
# Directory: users, groups, service accounts
# ---------------------------------------------------------------------------

resource "authentik_user" "users" {
  # Keyed by username to preserve existing authentik_user.users[...] addresses.
  for_each = var.users

  username   = each.key
  name       = each.value.name
  email      = each.value.email
  password   = each.value.password
  type       = each.value.type
  path       = each.value.path
  is_active  = each.value.is_active
  attributes = each.value.attributes

  lifecycle {
    # Password lifecycle is owned by authentik; never reconciled after create.
    ignore_changes = [password]
  }
}

resource "authentik_group" "groups" {
  # Keyed by group name to preserve existing authentik_group.groups[...] addresses.
  for_each = var.groups

  name         = each.key
  is_superuser = each.value.is_superuser
  attributes   = each.value.attributes
  users        = [for m in each.value.members : local.user_pks[m]]
}

resource "authentik_user" "service_accounts" {
  for_each = var.service_accounts

  username = coalesce(each.value.username, each.key)
  name     = each.value.name
  type     = "service_account"
}

resource "authentik_token" "service_accounts" {
  for_each = var.service_accounts

  identifier   = coalesce(each.value.token_identifier, "${each.key}-app-password")
  user         = authentik_user.service_accounts[each.key].id
  intent       = "app_password"
  expiring     = false
  retrieve_key = true
}

# ---------------------------------------------------------------------------
# Proxy outposts (container deployed externally, connects with a token)
# ---------------------------------------------------------------------------

resource "authentik_outpost" "proxy" {
  for_each = var.outposts

  name               = each.key
  type               = "proxy"
  protocol_providers = [for appkey in each.value.applications : local.proxy_provider_ids[appkey]]

  config = jsonencode({
    authentik_host          = coalesce(each.value.config.authentik_host, var.authentik_url)
    authentik_host_insecure = each.value.config.authentik_host_insecure
    authentik_host_browser  = each.value.config.authentik_host_browser
    log_level               = each.value.config.log_level
  })

  lifecycle {
    # authentik enriches the outpost config with server-managed defaults
    # (kubernetes_* fields, object_naming_template, ...) not expressed here,
    # which otherwise produce a perpetual diff. Config is applied on create and
    # ignored thereafter; change it in the authentik UI or temporarily lift this.
    ignore_changes = [config]
  }
}

# Module-minted outpost API tokens.
# authentik auto-generates a token for each outpost's service account, but provider
# 2024.10.x exposes no readable attribute for it. This mints a PARALLEL, non-expiring
# API token on the same service account ("ak-outpost-<uuid.hex>") so the outpost
# connection credential is retrievable via `terragrunt output`. The auto-generated token
# stays in authentik untouched; this token authenticates the same service account and is
# expected to be accepted by the external proxy via the user<->outpost association
# (verified operationally in Phase 4; fallback is the UI-issued token).
data "authentik_user" "outpost_sa" {
  for_each = var.outposts

  # authentik names each outpost's service account "ak-outpost-<uuid.hex>" (dashless).
  # authentik_outpost.id is the outpost UUID (dashed string, set from the API Pk), so
  # strip the dashes to get the .hex form. Referencing the outpost id directly also
  # creates the implicit dependency, deferring this read until the id is known.
  username = "${local.outpost_sa_prefix}${replace(authentik_outpost.proxy[each.key].id, "-", "")}"
}

resource "authentik_token" "outpost_api" {
  for_each = var.outposts

  identifier = "${each.key}-tf-api"

  # `user` is a Number; the data source's `id` is a numeric String that OpenTofu coerces
  # to the field type, matching the existing authentik_token.service_accounts idiom.
  # (`.pk` is a native Number alternative, but `.id` keeps the two token resources
  # consistent.)
  user         = data.authentik_user.outpost_sa[each.key].id
  intent       = "api"
  expiring     = false
  retrieve_key = true
  description  = "Terraform-managed API token for the ${each.key} proxy outpost (parallel to authentik's auto-generated outpost token)."
}

# ---------------------------------------------------------------------------
# Policy bindings
# ---------------------------------------------------------------------------

resource "authentik_policy_binding" "bindings" {
  for_each = local.policy_bindings

  target         = local.application_uuids[each.value.application]
  group          = each.value.group != null ? local.group_ids[each.value.group] : null
  user           = each.value.user != null ? local.user_pks[each.value.user] : null
  order          = each.value.order
  enabled        = each.value.enabled
  negate         = each.value.negate
  failure_result = each.value.failure_result
}
