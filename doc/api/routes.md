# Postal API: Management Routes

This page documents route endpoints under `/api/v1/manage/routes`.

Routes map incoming addresses (`name@domain`) to an endpoint or a built-in
action (Accept/Hold/Bounce/Reject). A catch-all route uses `name = "*"`.

## Endpoints

- `GET /api/v1/manage/routes`
- `POST /api/v1/manage/routes`
- `GET /api/v1/manage/routes/:uuid`
- `PATCH /api/v1/manage/routes/:uuid`
- `PUT /api/v1/manage/routes/:uuid`
- `DELETE /api/v1/manage/routes/:uuid`

## Authentication and Authorization

Every request needs a management API key in the header:

```http
X-Management-API-Key: <management_api_key>
```

Management keys are bound to admin users and have global management scope.

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
| `ManagementAPIKeyRevoked` | API key has been revoked or owner is no longer admin |
| `RouteNotFound` | UUID is missing or outside current visibility scope |
| `ServerNotFound` | Provided `server_id` does not exist |
| `DomainNotFound` | Provided `domain_id` does not exist |
| `EndpointNotFound` | Provided endpoint cannot be found |

`parameter-error` is used for malformed/invalid input.

---

## Route Object

Top-level fields:
- `id` / `uuid`
- `name` (local part, `*` for catch-all, `__returnpath__` for return-path routes)
- `server_id`
- `domain_id`
- `mode` (`Endpoint`, `Accept`, `Hold`, `Bounce`, `Reject`)
- `spam_mode` (`Mark`, `Quarantine`, `Fail`)
- `token`
- `description`
- `wildcard` (boolean)
- `endpoint` (`null` when mode is not `Endpoint`)
  - `type` (`SMTPEndpoint`, `HTTPEndpoint`, `AddressEndpoint`)
  - `uuid`
  - `name`
- `created_at`, `updated_at`

Detailed responses (`show`, `create`, `update`) also include:
- `domain` (`id`/`uuid`/`name`) when the route is bound to a domain

---

## `GET /api/v1/manage/routes`

Returns all visible routes.

Optional filters:
- `server_id`: integer
- `domain_id`: integer
- `name`: string (e.g. `*`)
- `page` (default `1`)
- `per_page` (default `50`, max `100`)

Success payload:
- `data.routes` array
- `data.total` count
- `data.pagination` metadata

---

## `GET /api/v1/manage/routes/:uuid`

Returns one route with full details.

Out-of-scope or unknown UUID:

```json
{
  "status": "error",
  "data": {
    "code": "RouteNotFound"
  }
}
```

---

## `POST /api/v1/manage/routes`

Creates a route.

### Request body

| Field | Type | Required | Notes |
|---|---|---|---|
| `server_id` | integer | yes | target server |
| `domain_id` | integer | no | required for normal delivery routes; omitted only for return-path routes |
| `name` | string | no | local part; defaults to `*` (catch-all) |
| `endpoint_type` | string | no | `SMTPEndpoint`, `HTTPEndpoint`, `AddressEndpoint` |
| `endpoint_uuid` | string | no | UUID of the endpoint; required when `endpoint_type` is provided |
| `spam_mode` | string | no | `Mark` (default), `Quarantine`, `Fail` |
| `mode` | string | no | one of `Endpoint`, `Accept`, `Hold`, `Bounce`, `Reject`; inferred as `Endpoint` when an endpoint is provided |

Rules:
- `endpoint_type` and `endpoint_uuid` must both be provided together.
- The endpoint and domain must belong to the chosen server (or its organization).
- Route name uniqueness per domain is enforced (Postal validation).

---

## `PATCH/PUT /api/v1/manage/routes/:uuid`

Updates an existing route.

Supported fields:
- `name`
- `spam_mode`
- `domain_id`
- `endpoint_type` + `endpoint_uuid` (re-points the route at a new endpoint)
- `mode` (switch between endpoint and built-in actions)

---

## `DELETE /api/v1/manage/routes/:uuid`

Deletes a route.

Out-of-scope or unknown UUID returns `RouteNotFound`.
