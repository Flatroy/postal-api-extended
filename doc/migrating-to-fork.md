# Migrating from upstream Postal to the postal-api-extended fork

This guide walks you through swapping a production Postal installation from the
upstream `ghcr.io/postalserver/postal` image to the fork at
`ghcr.io/flatroy/postal-api-extended`. The fork adds the management API
(domains, routes, http_endpoints, credentials, organizations, servers, users)
needed for self-service custom domains in HideMail.

The fork is kept in sync with upstream — it currently tracks **v3.3.7**.

## Prerequisites

- SSH access to your production Postal server
- Docker + Docker Compose installed
- Your existing Postal config at `/opt/postal/config/` (postal.yml, signing.key, Caddyfile)
- The `postal` CLI wrapper from `postalserver/install` at `/opt/postal/install/`

## What changes

| | Upstream | Fork |
|---|---|---|
| Image | `ghcr.io/postalserver/postal:3.3.7` | `ghcr.io/flatroy/postal-api-extended:routes-api` |
| Config | `/opt/postal/config/postal.yml` | Same — no changes needed |
| Database | Existing MariaDB/MySQL | Same — no schema changes in the fork |
| Web UI | Same | Same |
| Management API | Not available | `POST /api/v1/manage/domains`, `/routes`, `/http_endpoints`, etc. |
| Ports | Same | Same |

The fork only **adds** controllers and routes — it does not modify existing
models, migrations, or the web UI. Your existing data and config are untouched.

## Step 1 — Pull the fork image

```bash
docker pull ghcr.io/flatroy/postal-api-extended:routes-api
```

If the image isn't published yet (check GitHub Actions), you can build it
locally on the server:

```bash
git clone -b routes-api https://github.com/Flatroy/postal-api-extended.git /opt/postal/fork
cd /opt/postal/fork
docker build -t ghcr.io/flatroy/postal-api-extended:routes-api .
```

## Step 2 — Update the image reference

The `postal` CLI wrapper at `/opt/postal/install/bin/postal` reads the image
from an environment variable or defaults to the upstream image. You need to
point it at the fork.

### Option A — Set the POSTAL_IMAGE environment variable (recommended)

Edit `/opt/postal/install/bin/postal` and find the line that sets the image
(or set it in your shell environment):

```bash
export POSTAL_IMAGE=ghcr.io/flatroy/postal-api-extended:routes-api
```

Or add it to `/etc/environment` or your `.bashrc` so it persists:

```bash
echo 'POSTAL_IMAGE=ghcr.io/flatroy/postal-api-extended:routes-api' | sudo tee -a /etc/environment
```

Then log out and back in, or `source /etc/environment`.

### Option B — Edit the docker-compose template

If you used `postal bootstrap` to generate your config, the compose file is at
`/opt/postal/install/docker-compose.yml` (or similar). Replace the image
reference:

```yaml
# Before
services:
  web:
    image: ghcr.io/postalserver/postal:3.3.7
    # ...

# After
services:
  web:
    image: ghcr.io/flatroy/postal-api-extended:routes-api
    # ...
```

Do this for **all three services**: `web`, `smtp`, and `worker`.

## Step 3 — Stop Postal

```bash
postal stop
```

This stops all three containers (web, smtp, worker).

## Step 4 — Start Postal with the fork image

```bash
postal start
```

Verify all components are running:

```bash
postal status
```

You should see `web`, `smtp`, and `worker` all running.

## Step 5 — Run database migrations

The fork may include new migrations (for the management API keys table). Run:

```bash
postal upgrade
```

This is safe to run — it only adds tables, never drops or alters existing ones.

## Step 6 — Create a management API key

The management API requires a separate admin-bound key. Create one from the
Rails console:

```bash
docker exec -it postal-web-1 postal console
```

```ruby
user = User.find_by(email: "your-admin@example.com")
user.update!(admin: true) unless user.admin?
key = ManagementAPIKey.create!(name: "hidemail-management", user: user)
puts "Management API Key: #{key.key}"
# => Copy this key — it's shown only once
```

## Step 7 — Verify the management API

```bash
curl -s -H "X-Management-API-Key: YOUR_KEY" \
  https://postal.yourdomain.com/api/v1/manage/domains | jq .
```

You should see:

```json
{
  "status": "success",
  "data": { "domains": [], "total": 0, "pagination": { ... } }
}
```

## Step 8 — Configure HideMail

In your HideMail `.env`, set:

```env
POSTAL_MANAGEMENT_URL=https://postal.yourdomain.com
POSTAL_MANAGEMENT_KEY=YOUR_MANAGEMENT_API_KEY
POSTAL_SERVER_ID=YOUR_SERVER_ID
POSTAL_WEB_ENDPOINT_UUID=YOUR_HTTP_ENDPOINT_UUID
POSTAL_INBOUND_MX_HOST=mx.postal.yourdomain.com
```

To find your server ID and HTTP endpoint UUID:

```bash
# Server ID
curl -s -H "X-Management-API-Key: YOUR_KEY" \
  https://postal.yourdomain.com/api/v1/manage/servers | jq '.data.servers[].id'

# HTTP endpoint UUID (look for the "postal - web" endpoint)
curl -s -H "X-Management-API-Key: YOUR_KEY" \
  https://postal.yourdomain.com/api/v1/manage/http_endpoints | jq '.data.http_endpoints[] | {name, uuid}'
```

## Rollback

If something goes wrong, revert to the upstream image:

```bash
postal stop
export POSTAL_IMAGE=ghcr.io/postalserver/postal:3.3.7
postal start
```

Your data is untouched — the fork only adds tables and routes.

## Notes

- The fork's management API endpoints are under `/api/v1/manage/*` and require
  the `X-Management-API-Key` header (separate from the regular Postal API key).
- The management API key is stored as a digest — the raw key is only shown once
  at creation time.
- The fork tracks upstream releases. To update, pull the latest from upstream
  and rebuild. See `CONTRIBUTING.md` for the merge process.
