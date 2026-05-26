# Kontfix Identity Auth Server Integration

## Goal

Add `kontfix.identity.<region>.<serverName>` support to Kontfix, generating four Terraform resource types from the Kong Konnect provider.

## Terraform Resources

| Resource | Required Fields | Key Optional Fields |
|---|---|---|
| `konnect_identity_auth_server` | `audience`, `name` | `description`, `force_destroy`, `labels`, `signing_algorithm` (default RS256), `trusted_origins` |
| `konnect_identity_auth_server_claim` | `auth_server_id`, `name`, `value` | `enabled` (default true), `include_in_all_scopes` (default false), `include_in_scopes` (scope IDs), `include_in_token` (default false) |
| `konnect_identity_auth_server_client` | `auth_server_id`, `grant_types`, `name`, `response_types` | `access_token_duration` (default 300), `allow_all_scopes`, `allow_scopes` (scope IDs), `client_secret`, `id` (OAuth client_id), `id_token_duration` (default 300), `labels`, `login_uri`, `redirect_uris`, `token_endpoint_auth_method` (default client_secret_post) |
| `konnect_identity_auth_server_scope` | `auth_server_id`, `name` | `default` (default false), `description`, `enabled` (default true), `include_in_metadata` (default false) |

Provider: `konnect.${region}` for all four.

## Module Structure

```
identity/
├── default.nix       # imports options.nix + config.nix
├── options.nix        # option schema
└── config.nix         # resource generation
```

Follows the same split pattern as `groups/` (options.nix + config.nix + default.nix aggregator).

## Files Changed

| File | Change |
|---|---|
| `default.nix` | Add `./identity` to imports |
| `defaults/options.nix` | Add `defaults.identity.signing_algorithm` enum (RS256/RS384/RS512/PS256/PS384/PS512, default RS256) |
| `providers.nix` | Extend konnect provider aliases to include identity-only regions. Gate provider block on `cps != {} \|\| identity != {}` |

## No Shared Context

Identity is standalone (not coupled to control planes). No changes required to `lib/utils.nix` or `defaults/config.nix`. Module reads directly from `config.kontfix.identity`.

## UX Options

The four resources have inter-dependencies: scopes are referenced by claims (`include_in_scopes`) and clients (`allow_scopes`). The question is how much abstraction Kontfix applies on top.

### Option A: 1:1 Terraform Mapping

Users declare all four resource types explicitly. Lowest abstraction, most flexibility, most verbose.

```nix
kontfix.identity.us.auth = {
  audience = "https://api.example.com";

  scopes.read = { description = "Read access"; };
  scopes.write = { description = "Write access"; };

  claims.email = {
    value = "$${email}";
    include_in_token = true;
    include_in_scopes = [ "read" "write" ];    # references scope names
  };

  clients.api = {
    grant_types = [ "client_credentials" ];
    response_types = [ "none" ];
    allow_scopes = [ "read" ];                  # references scope names
  };
};
```

Scopes reusable across clients. Claims and clients both reference scopes by Nix name, resolved to Terraform IDs at generation time.

Pros:
- Maximum flexibility
- Scopes can be shared across clients
- Full access to all Terraform resource fields

Cons:
- Users must manually specify `grant_types` and `response_types` (easy to get wrong)
- No OAuth2 guidance from the structure

### Option B: Client-Centric (Scopes Nested Under Clients)

Scopes and claims live under each client. A `type` field auto-derives OAuth2 settings.

```nix
kontfix.identity.us.auth = {
  audience = "https://api.example.com";

  clients.api = {
    type = "machine_to_machine";    # auto: grant_types=[client_credentials], response_types=[none]
    scopes.read = {
      description = "Read access";
      claims.email = { value = "$${email}"; include_in_token = true; };
    };
    scopes.write = { description = "Write access"; };
  };

  clients.dashboard = {
    type = "web_application";       # auto: grant_types=[authorization_code,refresh_token], response_types=[code]
    login_uri = "https://app.example.com/login";
    redirect_uris = [ "https://app.example.com/callback" ];
    scopes.profile = { description = "User profile"; };
  };
};
```

`type` values and auto-derived settings:
- `machine_to_machine` → `grant_types = ["client_credentials"]`, `response_types = ["none"]`
- `web_application` → `grant_types = ["authorization_code" "refresh_token"]`, `response_types = ["code"]`

Pros:
- Structure guides correct OAuth2 usage
- No manual grant/response type wiring needed
- Scopes and claims co-located with consuming client

Cons:
- Scopes cannot be shared across clients (each client defines its own)

### Option C: Top-Level Categorisation (m2m / webapp at Region Level)

`m2m` and `webapp` are top-level children under the auth server. Each category auto-derives correct settings. Scopes and claims nest under these.

```nix
kontfix.identity.us.auth = {
  audience = "https://api.example.com";

  m2m.api-service = {
    scopes.read = { description = "..."; claims.email = { ... }; };
    scopes.write = { description = "..."; };
  };

  webapp.dashboard = {
    login_uri = "https://app.example.com/login";
    redirect_uris = [ "https://app.example.com/callback" ];
    scopes.profile = { description = "..."; };
    scopes.admin = { description = "..."; claims.role = { ... }; };
  };
};
```

Pros:
- Structure is declarative: `m2m` vs `webapp` is the intent, no `type` field needed
- Each category auto-gets correct grant/response types

Cons:
- Same scope-sharing limitation as Option B
- Slightly deeper structure (extra level: m2m/webapp)

## Resource Naming Convention

Terraform resource names follow the pattern:

| Terraform Type | Resource Name |
|---|---|
| `konnect_identity_auth_server` | `${region}-${serverName}` |
| `konnect_identity_auth_server_claim` | `${region}-${serverName}-${claimName}` |
| `konnect_identity_auth_server_client` | `${region}-${serverName}-${clientName}` |
| `konnect_identity_auth_server_scope` | `${region}-${serverName}-${scopeName}` |

## Defaults

```nix
defaults.identity = {
  signing_algorithm = mkOption {
    type = types.enum ["RS256" "RS384" "RS512" "PS256" "PS384" "PS512"];
    default = "RS256";
    description = "Default signing algorithm for identity auth servers";
  };
};
```

## Provider Changes

In `providers.nix`, extend the konnect provider alias generation to include regions that have identity auth servers but no control planes:

```nix
allRegions = unique ((attrNames config.kontfix.controlPlanes) ++ (attrNames config.kontfix.identity));
```

Also update the gate from `mkIf (cps != { })` to `mkIf (cps != {} || config.kontfix.identity != {})`.

## Testing

| Test Case | Coverage |
|---|---|
| `tests/cases/identity-basic.nix` | Minimal auth server: audience + name only |
| `tests/cases/identity-full.nix` | Auth server with all optional fields, claims, clients, scopes |
| `tests/cases/identity-multi-region.nix` | Multiple auth servers across regions |
| `tests/expected-results/` | JSON snapshots for each test case |

## Implementation Order

1. Create `identity/default.nix`, `identity/options.nix`
2. Create `identity/config.nix` (shape depends on chosen UX option)
3. Update `default.nix` imports
4. Update `defaults/options.nix` with `defaults.identity`
5. Update `providers.nix` for identity regions
6. Write test cases and generate snapshots
7. Run full test suite (`nix run ./tests#test-all`)

## Open Decision

UX approach (Option A, B, or C) must be selected before implementation. This determines the shape of `identity/options.nix` and `identity/config.nix`. The scaffolding (imports, defaults, providers) is identical regardless.
