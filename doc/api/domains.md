# Postal API: Management Domains

This page documents domain endpoints under `/api/v1/manage/domains`.

## Endpoints

- `GET /api/v1/manage/domains`
- `POST /api/v1/manage/domains`
- `GET /api/v1/manage/domains/:uuid`
- `PATCH /api/v1/manage/domains/:uuid`
- `PUT /api/v1/manage/domains/:uuid`
- `DELETE /api/v1/manage/domains/:uuid`
- `POST /api/v1/manage/domains/:uuid/verify`

## Authentication and Authorization

Every request needs a management API key in the header:

```http
X-Management-API-Key: <management_api_key>
```

Management keys are bound to admin users and have global management scope.
Requests with only `X-Server-API-Key` are rejected.

## Response Format

```json
{
  "status": "success|error|parameter-error",
  "time": 0.012,
  "flags": {},
  "data": {}
}
```

## Common Error Codes

| Code | Meaning |
|---|---|
| `AccessDenied` | Missing auth or wrong header type |
| `InvalidManagementAPIKey` | API key does not exist |
| `ManagementAPIKeyRevoked` | API key has been revoked |
| `DomainNotFound` | UUID is missing or outside current visibility scope |
| `ServerNotFound` | Provided `server_id` does not exist |
| `OrganizationNotFound` | Provided `organization_id` does not exist |
| `DomainVerificationFailed` | DNS verification execution failed |

`parameter-error` is used for malformed/invalid input.

---

## Domain Object

The API returns domain data including scope, DNS expectations, and verification metadata.

Top-level fields include:
- `id` / `uuid`
- `internal_id` (Postal's integer primary key; use this as `domain_id` when creating routes)
- `name`
- `scope` (`server` or `organization`)
- `server_id`
- `organization_id`
- `status` (`pending`, `pending_dns`, `verified`, `failed`)
- `status_reason`
- `verification_method`
- `outgoing`, `incoming`, `use_for_any`
- `last_verification_at`, timestamps

Detailed responses (`show`, `create`, `update`, `verify`) also include:
- `dns` (`spf`, `dkim`, `return_path`, `dmarc` expected records)
- `verification` (`last_result`, `details`)
- owner context (`server`/`organization` hashes)

---

## `GET /api/v1/manage/domains`

Returns all visible domains.

Optional filters:
- `scope`: `server` or `organization`
- `status`: `pending`, `pending_dns`, `verified`, `failed`
- `server_id`: integer
- `organization_id`: integer
- `page` (default `1`)
- `per_page` (default `50`, max `100`)

Success payload:
- `data.domains` array
- `data.total` count
- `data.pagination` metadata

---

## `GET /api/v1/manage/domains/:uuid`

Returns one domain with full details.

Out-of-scope or unknown UUID:

```json
{
  "status": "error",
  "data": {
    "code": "DomainNotFound"
  }
}
```

---

## `POST /api/v1/manage/domains`

Creates a domain.

Important behavior:
- management API keys are admin-bound
- newly created domains skip the ownership-verification step that non-admin UI users go through
- the create response includes `ownership_verification_skipped: true`
- the created domain starts in status `pending_dns because` the management API create flow sets verified_at immediately and no DNS checks have run yet; this mirrors the existing admin UI flow, which skips the ownership-verification step for admins

### Request body

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | lowercase letters, digits, `-`, `.` |
| `server_id` | integer | no | target server scope |
| `organization_id` | integer | no | target organization scope |
| `scope` | string | no | `server` or `organization` (optional hint) |

Rules:
- `server_id` and `organization_id` are mutually exclusive.
- if neither is provided, the request fails with `server_id or organization_id must be provided`.
- verification method is fixed to `DNS` on create.

Create success response additionally includes:
- `data.domain.ownership_verification_skipped` (boolean)

---

## `PATCH/PUT /api/v1/manage/domains/:uuid`

Updates an existing domain.

Supported fields:
- `name`
- `verification_method`
- `outgoing`
- `incoming`
- `use_for_any`
- `rotate_dkim_key` (boolean)
- `cancel_pending_dkim_key` (boolean)

`rotate_dkim_key=true` generates a new DKIM keypair for the domain, the same way as the web UI:

- If the current DKIM record is not verified (`dkim_status` is not `OK`), the new key replaces the current key immediately. Publish the new `dns.dkim.expected_value` and verify the domain.
- If the current DKIM record is verified, the new key is stored as a pending key with a new selector. Postal continues to sign with the current key. The response includes `dns.dkim.pending` (`selector`, `record_name`, `record_type`, `public_key`, `expected_value`). Publish that record in addition to the current one, then call `POST /verify`. When the pending record is found, Postal makes the new key active and `dns.dkim.pending` becomes `null`. Keep the old record published while messages signed with the old key can still be queued, held or redelivered.
- If a rotation is already pending, the request fails with error code `DKIMRotationInProgress` and nothing changes.

`cancel_pending_dkim_key=true` discards a pending key. The current key stays active.

Sending both `rotate_dkim_key=true` and `cancel_pending_dkim_key=true` returns a `parameter-error`. Key changes are applied only if the other fields are valid.

---

## `POST /api/v1/manage/domains/:uuid/verify`

Triggers DNS checks (SPF, DKIM, MX, return-path) and updates verification details.

Optional body:
- `force` (boolean, accepted for compatibility)

Success returns updated domain details including `verification`.

---

## `DELETE /api/v1/manage/domains/:uuid`

Deletes a domain.

Out-of-scope or unknown UUID returns `DomainNotFound`.
