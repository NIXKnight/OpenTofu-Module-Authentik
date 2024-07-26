locals {
  authentik_config = yamldecode(file("${var.authentik_config_file}"))
  enable_generic_ldap_provider = lookup(local.authentik_config, "enable_generic_ldap_provider", false)
  ldap_provider_base_dn = lookup(local.authentik_config, "ldap_provider_base_dn", "dc=ldap,dc=goauthentik,dc=io")
}
