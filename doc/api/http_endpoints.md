# Postal API: Management HTTP Endpoints

This page documents HTTP endpoint endpoints under `/api/v1/manage/http_endpoints`.

HTTP endpoints are read-only over the management API. They exist so callers
(such as HideMail's provisioning flow) can resolve the UUID of an existing
HTTP endpoint — for example the `postal - web` endpoint that receives inbound
mail — instead of hardcoding it.

## Endpoints

- `GET /api/v1/manage/http_endpoints`
- `GET /api/v1/manage/http_endpoints/:uuid`

## Authentication and Authorization

Every request needs a management API key in the header:

```http
X-Management-API-Key: <management_api_key>
```

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
| `HttpEndpointNotFound` | UUID is missing or outside current visibility scope |
| `ServerNotFound` | Provided `server_id` does not exist |

---

## HTTP Endpoint Object

Top-level fields:
- `id` / `uuid`
- `name`
- `server_id`
- `url`
- `encoding` (`BodyAsJSON`, `FormData`)
- `format` (`Hash`, `RawMessage`)
- `strip_replies`
- `include_attachments`
- `timeout`
- `last_used_at`
- `disabled_until`
- `created_at`, `updated_at`

Detailed responses (`show`) also include:
- `server` (`id`/`uuid`/`name`/`permalink`)

---

## `GET /api/v1/manage/http_endpoints`

Returns all visible HTTP endpoints.

Optional filters:
- `server_id`: integer
- `name`: string
- `page` (default `1`)
- `per_page` (default `50`, max `100`)

Success payload:
- `data.http_endpoints` array
- `data.total` count
- `data.pagination` metadata

---

## `GET /api/v1/manage/http_endpoints/:uuid`

Returns one HTTP endpoint with server details.

Out-of-scope or unknown UUID:

```json
{
  "status": "error",
  "data": {
    "code": "HttpEndpointNotFound"
  }
}
```
