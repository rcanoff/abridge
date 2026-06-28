# Config Validation Contract — Design

**Date:** 2026-06-27  
**Status:** Approved  
**Approach:** B — validation matrix in architecture guide  
**Related:** `docs/conventions.md`, `docs/architecture-bootstrap-guide.md` §5

---

## Problem

Provider ID shape rules (lowercase, no spaces) live in `docs/conventions.md`, but PR 2a spec and `validate_config()` only enforced blank/duplicate checks. Implementers following the PR spec could pass review while violating conventions.

Host validation had the same drift (wildcard rejection vs loopback allowlist). This design centralizes the operational contract so PR specs, code, and reviews align.

## Decision

Replace the bullet-list validation rules in **architecture guide §5** with a single matrix. PR specs reference matrix rows by PR column instead of re-listing rules. `docs/conventions.md` keeps naming philosophy; it points to the matrix for field validation.

## Validation matrix (canonical)

Implemented in `validate_config()` at `create_server()` — not lazily on first request.

| Field | Rule | Error message | PR |
|-------|------|---------------|-----|
| `host` | Non-blank after trim | `host must not be blank` | 2a |
| `host` | Loopback allowlist: `127.0.0.1`, `localhost`, `::1` | `host must be loopback` | 2a |
| `port` | `> 0` | `port must not be 0` | 2a |
| `enabled_providers[].name` | Non-blank after trim | `provider name must not be blank` | 2a |
| `enabled_providers[].name` | Lowercase, no whitespace (per conventions § Providers) | `invalid provider name: {name}` | 2a |
| `enabled_providers[].name` | Unique after trim | `duplicate provider name: {name}` | 2a |
| `bearer_token` | Non-empty | `bearer token must not be empty` | 2d |
| `enabled_providers` | At least one enabled (if app requires) | TBD | later |

### Request-time validation (not config)

`ProviderRequest.provider` and `.operation` shape checks run at routing/dispatch (PR 2b+), not in `validate_config()`.

## Implementation (PR 2a follow-up)

- `config.rs`: add `is_valid_provider_name()` — non-empty, `name == name.to_lowercase()`, no `char::is_whitespace`
- Tests: `rejects_uppercase_provider_name`, `rejects_provider_name_with_spaces`

## Doc updates

| File | Change |
|------|--------|
| `docs/architecture-bootstrap-guide.md` | Matrix in §5; stale validation bullets → matrix pointer |
| `docs/conventions.md` | Cross-reference to architecture guide §5 matrix |
| PR 2a spec | Validation section references matrix; add provider shape tests |

## Success criteria

- [ ] Matrix in architecture guide §5
- [ ] PR 2a spec points at matrix
- [ ] `validate_config()` satisfies all PR 2a rows
- [ ] Tests cover provider ID shape failures
- [ ] `cargo test --locked` and clippy pass