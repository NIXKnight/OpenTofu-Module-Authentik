# ---------------------------------------------------------------------------
# Provider connection
# ---------------------------------------------------------------------------

variable "authentik_url" {
  description = "authentik API endpoint, e.g. https://authentik.example.com."
  type        = string
}

variable "authentik_token" {
  description = "authentik API token used by the provider."
  type        = string
  sensitive   = true
}

variable "authentik_insecure" {
  description = "Skip TLS verification when talking to the authentik API."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Shared flow / signing-key lookups
# ---------------------------------------------------------------------------

variable "authorization_flow_slug" {
  description = "Slug of the authorization flow bound to every provider."
  type        = string
  default     = "default-provider-authorization-implicit-consent"
}

variable "invalidation_flow_slug" {
  description = "Slug of the invalidation flow bound to every provider (required by provider >= 2024.10)."
  type        = string
  default     = "default-provider-invalidation-flow"
}

variable "signing_key_name" {
  description = "Name of the certificate-key-pair used as the OAuth2 signing key."
  type        = string
  default     = "authentik Self-signed Certificate"
}

# ---------------------------------------------------------------------------
# Applications (app-centric: each entry carries its provider config inline)
# ---------------------------------------------------------------------------

variable "applications" {
  description = <<-EOT
    Map of authentik applications keyed by a stable application key (e.g. "jenkins").
    The map key is the for_each key for both the application and its provider, so
    existing keys ("jenkins", "grafana") must be preserved to avoid a replacement.

    Each entry carries its provider configuration inline, discriminated by `type`:
      - "oauth2": OAuth2/OIDC provider-backed application.
      - "proxy" : Proxy provider-backed application, served by an outpost.

    OAuth2 `scopes` are managed scope-mapping identifiers, e.g.
    "goauthentik.io/providers/oauth2/scope-openid". `client_secret` relies on the
    provider's built-in sensitive marking; source it from a sensitive backend.
  EOT

  type = map(object({
    type = string

    # Application-level fields (authentik_application).
    name               = string
    slug               = string
    group              = optional(string)
    meta_description   = optional(string)
    meta_publisher     = optional(string)
    meta_launch_url    = optional(string)
    meta_icon          = optional(string)
    open_in_new_tab    = optional(bool, false)
    policy_engine_mode = optional(string, "any")

    # OAuth2 provider fields (type = "oauth2").
    client_id     = optional(string)
    client_secret = optional(string)
    scopes        = optional(list(string), [])
    redirect_uris = optional(list(object({
      url           = string
      matching_mode = optional(string, "strict")
      # authentik 2026.5 echoes this back on read (post-logout redirect URIs);
      # carry it so state matches config. Free-form: server values beyond
      # "authorization" are not confirmed in provider docs, so no enum validation.
      redirect_uri_type = optional(string, "authorization")
    })), [])
    client_type                = optional(string, "confidential")
    sub_mode                   = optional(string)
    include_claims_in_id_token = optional(bool)
    issuer_mode                = optional(string)
    access_code_validity       = optional(string)
    access_token_validity      = optional(string)
    refresh_token_validity     = optional(string)
    # authentik 2026.5+ requires explicit grant selection; the API default for
    # newly created providers is EMPTY (nothing allowed), so an unset grant_types
    # bounces every authorize request with invalid_request before any login. Tight
    # default covers the standard code+refresh flow; widen per-app when a use case
    # needs it (known server values: authorization_code, refresh_token, implicit,
    # hybrid, client_credentials, password,
    # urn:ietf:params:oauth:grant-type:device_code — no validation enum, the server
    # may extend the set).
    grant_types = optional(list(string), ["authorization_code", "refresh_token"])

    # Proxy provider fields (type = "proxy").
    mode                         = optional(string, "proxy")
    external_host                = optional(string)
    internal_host                = optional(string)
    intercept_header_auth        = optional(bool, true)
    internal_host_ssl_validation = optional(bool)
    skip_path_regex              = optional(string)
  }))

  default = {}

  validation {
    condition     = alltrue([for k, a in var.applications : contains(["oauth2", "proxy"], a.type)])
    error_message = "Each application `type` must be one of: oauth2, proxy."
  }

  validation {
    condition     = alltrue([for k, a in var.applications : a.type != "oauth2" || a.client_id != null])
    error_message = "oauth2 applications require `client_id`."
  }

  validation {
    condition     = alltrue([for k, a in var.applications : a.type != "proxy" || a.external_host != null])
    error_message = "proxy applications require `external_host`."
  }

  validation {
    condition = alltrue([
      for k, a in var.applications :
      a.type != "proxy" || contains(["proxy", "forward_single", "forward_domain"], a.mode)
    ])
    error_message = "proxy application `mode` must be one of: proxy, forward_single, forward_domain."
  }

  validation {
    condition = alltrue([
      for k, a in var.applications :
      a.type != "oauth2" || contains(["confidential", "public"], a.client_type)
    ])
    error_message = "oauth2 application `client_type` must be one of: confidential, public."
  }

  validation {
    condition = alltrue(flatten([
      for k, a in var.applications : [
        for r in a.redirect_uris : contains(["strict", "regex"], r.matching_mode)
      ]
    ]))
    error_message = "redirect_uris `matching_mode` must be one of: strict, regex."
  }
}

# ---------------------------------------------------------------------------
# Directory: users, groups, service accounts
# ---------------------------------------------------------------------------

variable "users" {
  description = <<-EOT
    Map of authentik users keyed by username. The map key is used as the username
    and as the for_each key, preserving existing authentik_user.users[...] addresses.
  EOT

  type = map(object({
    name       = string
    email      = optional(string)
    password   = optional(string)
    type       = optional(string, "internal")
    path       = optional(string)
    is_active  = optional(bool, true)
    attributes = optional(string) # JSON string; use jsonencode() at the call site.
  }))

  default = {}

  validation {
    condition = alltrue([
      for k, u in var.users :
      contains(["internal", "external", "service_account", "internal_service_account"], u.type)
    ])
    error_message = "user `type` must be one of: internal, external, service_account, internal_service_account."
  }
}

variable "groups" {
  description = <<-EOT
    Map of authentik groups keyed by group name (the for_each key, preserving
    existing authentik_group.groups[...] addresses). `members` lists user or
    service-account keys.
  EOT

  type = map(object({
    members      = optional(list(string), [])
    is_superuser = optional(bool, false)
    attributes   = optional(string) # JSON string; use jsonencode() at the call site.
  }))

  default = {}
}

variable "service_accounts" {
  description = <<-EOT
    Map of service accounts keyed by a stable key. Each creates a service_account
    user plus a non-expiring app-password token; the token key is exposed via the
    `service_account_app_passwords` output (sensitive).
  EOT

  type = map(object({
    name             = string
    username         = optional(string) # defaults to the map key.
    token_identifier = optional(string) # defaults to "<key>-app-password".
  }))

  default = {}
}

# ---------------------------------------------------------------------------
# Proxy outposts
# ---------------------------------------------------------------------------

variable "outposts" {
  description = <<-EOT
    Map of proxy outposts keyed by outpost name. `applications` lists the proxy
    application keys whose providers this outpost serves. The outpost container is
    deployed externally and connects with a token (no service_connection).
  EOT

  type = map(object({
    applications = list(string)
    config = optional(object({
      authentik_host          = optional(string) # defaults to var.authentik_url.
      authentik_host_insecure = optional(bool, false)
      authentik_host_browser  = optional(string, "")
      log_level               = optional(string, "info")
    }), {})
  }))

  default = {}
}

# ---------------------------------------------------------------------------
# Policy bindings
# ---------------------------------------------------------------------------

variable "policy_bindings" {
  description = <<-EOT
    List of policy bindings. Each binds an application (by key) to exactly one of a
    group (by group key) or a user/service-account (by key), with an order.
  EOT

  type = list(object({
    application    = string
    group          = optional(string)
    user           = optional(string)
    order          = optional(number, 0)
    enabled        = optional(bool, true)
    negate         = optional(bool, false)
    failure_result = optional(bool, false)
  }))

  default = []

  validation {
    condition     = alltrue([for b in var.policy_bindings : (b.group != null) != (b.user != null)])
    error_message = "Each policy binding must set exactly one of `group` or `user`."
  }
}
