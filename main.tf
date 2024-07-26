data "authentik_flow" "default_authorization_flow" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

# LDAP generic provider setup, as per Authentik documentation https://docs.goauthentik.io/docs/providers/ldap/generic_setup
resource "authentik_stage_user_login" "ldap_generic" {
  count = local.enable_generic_ldap_provider ? 1 : 0
  name  = "ldap-generic-user-login"
}

resource "authentik_stage_password" "ldap_generic" {
  count = local.enable_generic_ldap_provider ? 1 : 0
  name     = "ldap-generic-password"
  backends = [
    "authentik.core.auth.TokenBackend",
    "authentik.core.auth.InbuiltBackend",
    "authentik.sources.ldap.auth.LDAPBackend"
  ]
}

resource "authentik_stage_identification" "ldap_generic" {
  count          = local.enable_generic_ldap_provider ? 1 : 0
  name           = "ldap-generic-identification"
  user_fields    = ["username", "email"]
  password_stage = authentik_stage_password.ldap_generic[0].id
}

resource "authentik_flow" "ldap_generic" {
  count       = local.enable_generic_ldap_provider ? 1 : 0
  name        = "ldap-generic-flow"
  title       = "ldap-generic-flow"
  slug        = "ldap-generic-flow"
  designation = "authentication"
}

resource "authentik_flow_stage_binding" "ldap_generic_identification" {
  count  = local.enable_generic_ldap_provider ? 1 : 0
  stage  = authentik_stage_identification.ldap_generic[0].id
  target = authentik_flow.ldap_generic[0].uuid
  order  = 10
}

resource "authentik_flow_stage_binding" "ldap_generic_login" {
  count  = local.enable_generic_ldap_provider ? 1 : 0
  stage  = authentik_stage_user_login.ldap_generic[0].id
  target = authentik_flow.ldap_generic[0].uuid
  order  = 30
}

resource "authentik_provider_ldap" "generic" {
  count   = local.enable_generic_ldap_provider ? 1 : 0
  name    = "ldap-generic-provider"
  base_dn = local.ldap_provider_base_dn
  bind_flow = authentik_flow.ldap_generic[0].uuid
}

resource "authentik_application" "ldap_generic" {
  count            = local.enable_generic_ldap_provider ? 1 : 0
  name             = "ldap-generic"
  slug             = "ldap-generic"
  protocol_provider = authentik_provider_ldap.generic[0].id
}

resource "authentik_outpost" "ldap_generic" {
  count              = local.enable_generic_ldap_provider ? 1 : 0
  name               = "ldap-generic"
  type               = "ldap"
  protocol_providers = [authentik_provider_ldap.generic[0].id]
}

# Scope mapping
data "authentik_scope_mapping" "scope_mappings" {
  for_each = { for mapping in local.authentik_config.scope_mappings : mapping.name => mapping }
  managed_list = each.value.managed_list
}

# OAuth2 provider and application
resource "authentik_provider_oauth2" "oauth2_providers" {
  depends_on = [ data.authentik_scope_mapping.scope_mappings ]

  for_each          = { for provider in local.authentik_config.providers : provider.name => provider }
  name              = each.value.name
  client_id         = each.value.client_id
  client_secret     = each.value.client_secret
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  property_mappings = data.authentik_scope_mapping.scope_mappings[each.value.property_mappings].ids
  signing_key       = data.authentik_certificate_key_pair.default.id
  redirect_uris     = each.value.redirect_uris
}

resource "authentik_application" "applications" {
  for_each          = { for app in local.authentik_config.applications : app.name => app }
  name              = each.value.name
  slug              = each.value.slug
  protocol_provider = authentik_provider_oauth2.oauth2_providers[each.value.provider].id
}

# Users and groups
resource "authentik_user" "users" {
  for_each = { for user in local.authentik_config.users : user.username => user }
  username = each.value.username
  email    = each.value.email
  name     = each.value.name
  password = each.value.password
  type     = lookup(each.value, "type", "internal")

  lifecycle {
    ignore_changes = [
      password
    ]
  }
}

resource "authentik_group" "groups" {
  for_each = { for group in local.authentik_config.groups : group.name => group }
  name     = each.value.name
  users    = [for user in each.value.users : authentik_user.users[user].id]
}
