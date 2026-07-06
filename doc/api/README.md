# Postal API Documentation

Complete API reference for Postal mail server.

## Available APIs

### Management API (`/api/v1/manage/*`)
- [User Management API](./users.md) - Create, read, update, and delete users
- [Server Management API](./servers.md) - Create, read, update, and delete servers
- [Credential Management API](./credentials.md) - Create, read, update, and delete credentials
- [Organization Management API](./organizations.md) - Create, read, update, and delete organizations
- [Domain Management API](./domains.md) - Create, read, update, verify, and delete domains
- [Route Management API](./routes.md) - Create, read, update, and delete routes
- [HTTP Endpoint Management API](./http_endpoints.md) - List and read HTTP endpoints

### Legacy Send API (`/api/v1/*`)
- Send Messages via `/api/v1/send/*`
- Query Messages via `/api/v1/messages/*`

## API Split

The v1 API is now split into two route groups:

- Management endpoints live under `/api/v1/manage/*`.
- Legacy send/query endpoints stay on `/api/v1/send/*` and `/api/v1/messages/*`.

This keeps send traffic and management traffic on separate URL spaces while preserving the existing send endpoints.

## Authentication

Postal now uses two different API key types:

### Management API authentication

Management endpoints under `/api/v1/manage/*` require:

```http
X-Management-API-Key: your_management_api_key_here
```

Management keys are:
- global-only
- bound to an internal admin user
- created in the Postal web admin user screen
- valid only on `/api/v1/manage/*`

Requests to `/api/v1/manage/*` with only `X-Server-API-Key` are rejected.

### Send and message authentication

Send and query endpoints keep the legacy server credential header:

```http
X-Server-API-Key: your_server_api_key_here
```

This applies to:
- `/api/v1/send/*`
- `/api/v1/messages/*`

`X-Management-API-Key` does not grant access to send or message endpoints.

This is the intended split:
- management changes use admin-bound management keys
- send/query traffic keeps using server credentials

### Getting a Management API Key

1. Log into the Postal web interface as an admin user.
2. Open `Users`.
3. Edit the admin user that should own the key.
4. Create a `Management API Key`.
5. Copy the generated key immediately. It is shown only once.

## Migration Note

This is a hard authentication cut for the management API:
- `/api/v1/manage/*` no longer accepts server API credentials
- internal clients must switch to `X-Management-API-Key`
- `/api/v1/send/*` and `/api/v1/messages/*` remain unchanged
- Postman/Newman management collections must send `X-Management-API-Key`
- management write requests now require explicit IDs such as `organization_id` and `server_id`

## API Response Format

All API responses follow this structure:

```json
{
  "status": "success|error|parameter-error",
  "time": 0.042,
  "flags": {},
  "data": {
    // Response data or error details
  }
}
```

Management API list endpoints are paginated with query params:
- `page` (default `1`)
- `per_page` (default `50`, max `100`)

### Status Codes

- `success` - Request completed successfully
- `error` - Request failed due to business logic error
- `parameter-error` - Invalid parameters provided

**Note**: HTTP status code is always `200 OK`. Check the `status` field for actual result.

## Endpoint Summary

| Category        | Endpoint                    | Description                |
|-----------------|----------------------------|----------------------------|
| Users           | `GET /api/v1/manage/users`        | List all users             |
| Users           | `POST /api/v1/manage/users`       | Create new user            |
| Users           | `GET /api/v1/manage/users/:uuid`  | Get user details           |
| Users           | `PATCH /api/v1/manage/users/:uuid`| Update user                |
| Users           | `DELETE /api/v1/manage/users/:uuid`| Delete user               |
| Servers         | `GET /api/v1/manage/servers`      | List visible servers       |
| Servers         | `POST /api/v1/manage/servers`     | Create new server          |
| Servers         | `GET /api/v1/manage/servers/:uuid`| Get server details         |
| Servers         | `PATCH /api/v1/manage/servers/:uuid`| Update server            |
| Servers         | `DELETE /api/v1/manage/servers/:uuid`| Delete server           |
| Credentials     | `GET /api/v1/manage/credentials`      | List visible credentials  |
| Credentials     | `POST /api/v1/manage/credentials`     | Create new credential     |
| Credentials     | `GET /api/v1/manage/credentials/:uuid`| Get credential details    |
| Credentials     | `PATCH /api/v1/manage/credentials/:uuid`| Update credential      |
| Credentials     | `DELETE /api/v1/manage/credentials/:uuid`| Delete credential     |
| Organizations   | `GET /api/v1/manage/organizations`        | List organizations         |
| Organizations   | `POST /api/v1/manage/organizations`       | Create organization        |
| Organizations   | `GET /api/v1/manage/organizations/:uuid`  | Get organization details   |
| Organizations   | `PATCH /api/v1/manage/organizations/:uuid`| Update organization        |
| Organizations   | `DELETE /api/v1/manage/organizations/:uuid`| Delete organization       |
| Domains         | `GET /api/v1/manage/domains`        | List visible domains       |
| Domains         | `POST /api/v1/manage/domains`       | Create new domain          |
| Domains         | `GET /api/v1/manage/domains/:uuid`  | Get domain details         |
| Domains         | `PATCH /api/v1/manage/domains/:uuid`| Update domain              |
| Domains         | `DELETE /api/v1/manage/domains/:uuid`| Delete domain             |
| Domains         | `POST /api/v1/manage/domains/:uuid/verify`| Trigger DNS verification |
| Messages        | `POST /api/v1/send/message`| Send structured email message |
| Messages        | `POST /api/v1/send/raw`    | Send raw email             |
| Messages        | `POST /api/v1/messages/message` | Query message details    |
| Messages        | `POST /api/v1/messages/deliveries` | Query delivery details |


## Support

- [GitHub Discussions](https://github.com/postalserver/postal/discussions)
- [Discord Community](https://discord.postalserver.io)
- [Documentation](https://docs.postalserver.io)
