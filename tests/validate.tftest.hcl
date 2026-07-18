# Validate-only test. Exercises variable typing, validation rules, and resource
# expansion for both application types plus users, groups, service accounts,
# outposts and policy bindings. The authentik provider plugin is downloaded by
# `tofu init`, but every API call is mocked, so no live authentik server is needed.

# authentik's `id` attributes are String-typed but feed Number-typed fields
# (protocol_provider, user, protocol_providers). Live, the id is a numeric string
# that coerces cleanly; the mock otherwise emits non-numeric strings, so pin numeric
# ids for the resources whose id crosses into a number field.
mock_provider "authentik" {
  mock_resource "authentik_provider_oauth2" {
    defaults = { id = "1" }
  }
  mock_resource "authentik_provider_proxy" {
    defaults = { id = "2" }
  }
  mock_resource "authentik_user" {
    defaults = { id = "3" }
  }
  # Outpost id is the outpost UUID (dashed); the SA-username lookup strips the dashes to
  # the .hex form, so pin a realistic dashed UUID here.
  mock_resource "authentik_outpost" {
    defaults = { id = "550e8400-e29b-41d4-a716-446655440000" }
  }
  # authentik_user is also read as a DATA source (outpost service-account lookup); its
  # String id feeds the Number `user` field on authentik_token, so pin a numeric id.
  mock_data "authentik_user" {
    defaults = { id = "9" }
  }
}

variables {
  authentik_url   = "https://authentik.example.com"
  authentik_token = "mock-token"

  applications = {
    jenkins = {
      type          = "oauth2"
      name          = "Jenkins"
      slug          = "jenkins"
      client_id     = "jenkins"
      client_secret = "mock-secret"
      scopes = [
        "goauthentik.io/providers/oauth2/scope-openid",
        "goauthentik.io/providers/oauth2/scope-email",
        "goauthentik.io/providers/oauth2/scope-profile",
      ]
      redirect_uris = [
        { url = "https://jenkins.example.com/securityRealm/finishLogin" },
      ]
    }
    portainer = {
      type          = "proxy"
      name          = "Portainer"
      slug          = "portainer"
      external_host = "https://portainer.example.com"
      mode          = "forward_single"
    }
  }

  users = {
    admin = {
      name  = "Admin User"
      email = "admin@example.com"
    }
  }

  groups = {
    administrators = {
      members = ["admin"]
    }
  }

  service_accounts = {
    automation = {
      name = "Automation Service Account"
    }
  }

  outposts = {
    "proxy-outpost" = {
      applications = ["portainer"]
    }
  }

  policy_bindings = [
    {
      application = "jenkins"
      group       = "administrators"
      order       = 0
    },
  ]
}

run "plan_both_application_types" {
  command = plan

  assert {
    condition     = authentik_provider_oauth2.oauth2_providers["jenkins"].client_id == "jenkins"
    error_message = "oauth2 provider for jenkins should be planned with client_id=jenkins."
  }

  assert {
    condition     = authentik_application.proxy_applications["portainer"].slug == "portainer"
    error_message = "proxy application for portainer should be planned."
  }

  assert {
    condition     = length(authentik_outpost.proxy["proxy-outpost"].protocol_providers) == 1
    error_message = "proxy outpost should reference exactly one proxy provider."
  }

  assert {
    condition     = authentik_token.service_accounts["automation"].intent == "app_password"
    error_message = "service-account token should use the app_password intent."
  }
}

# Apply against mocks so the outpost is "created" before the service-account data
# source reads (the depends_on defers it at plan), exercising the new outpost API
# token path end to end: data source lookup, token resource, and sensitive output.
run "outpost_api_token_minted" {
  command = apply

  assert {
    condition     = data.authentik_user.outpost_sa["proxy-outpost"].username == "ak-outpost-550e8400e29b41d4a716446655440000"
    error_message = "outpost SA lookup should be ak-outpost-<outpost uuid.hex> (dashless)."
  }

  assert {
    condition     = authentik_token.outpost_api["proxy-outpost"].identifier == "proxy-outpost-tf-api"
    error_message = "outpost API token identifier should be <outpost name>-tf-api."
  }

  assert {
    condition     = authentik_token.outpost_api["proxy-outpost"].intent == "api"
    error_message = "outpost API token should use the api intent."
  }

  assert {
    condition     = authentik_token.outpost_api["proxy-outpost"].expiring == false
    error_message = "outpost API token should be non-expiring."
  }

  assert {
    condition     = length(output.outpost_tokens) == 1
    error_message = "outpost_tokens output should expose one token key per outpost."
  }
}
