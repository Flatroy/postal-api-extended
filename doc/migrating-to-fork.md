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
| Database | Existing MariaDB/MySQL | Same — fork only adds tables |
| Web UI | Same | Same |
| Management API | Not available | `POST /api/v1/manage/domains`, `/routes`, `/http_endpoints`, etc. |
| Ports | Same | Same |

The fork only **adds** controllers and routes — it does not modify existing
models, migrations, or the web UI. Your existing data and config are untouched.

## Step 1 — Verify the GHCR image is published

The GitHub Actions workflow builds and pushes automatically on every push to
`routes-api`. The image is tagged as:

- `ghcr.io/flatroy/postal-api-extended:latest` — always the most recent `routes-api` build
- `ghcr.io/flatroy/postal-api-extended:routes-api` — branch name tag
- `ghcr.io/flatroy/postal-api-extended:sha-<commit>` — pinned to a specific commit

Check on your server:

```bash
docker pull ghcr.io/flatroy/postal-api-extended:routes-api
```

If it fails with "not found", the package visibility might be private.
Go to: https://github.com/Flatroy/postal-api-extended/pkgs/container/postal-api-extended
→ Package settings → Danger Zone → Change visibility to Public.

Alternatively, build the image locally on the server:

```bash
git clone -b routes-api https://github.com/Flatroy/postal-api-extended.git /opt/postal/fork
cd /opt/postal/fork
docker build -t ghcr.io/flatroy/postal-api-extended:routes-api .
```

## Step 2 — Back up your current config

```bash
cp -r /opt/postal/config /opt/postal/config.backup.$(date +%Y%m%d)
```

## Step 3 — Stop Postal

```bash
postal stop
```

Verify all containers are stopped:

```bash
docker ps | grep postal
# Should show nothing
```

## Step 4 — Update the image reference

Find where the Postal image is configured:

```bash
# Check the postal CLI wrapper
cat /opt/postal/install/bin/postal | grep -i image

# Or check environment
grep -r POSTAL_IMAGE /opt/postal/ /etc/environment
```

### Option A — Set the POSTAL_IMAGE environment variable (recommended)

```bash
# Set it in /etc/environment so it persists across reboots
sed -i '/POSTAL_IMAGE/d' /etc/environment
echo 'POSTAL_IMAGE=ghcr.io/flatroy/postal-api-extended:routes-api' >> /etc/environment
source /etc/environment
```

### Option B — Edit the postal CLI script

```bash
nano /opt/postal/install/bin/postal

# Find the line that sets the image (something like):
#   IMAGE="${POSTAL_IMAGE:-ghcr.io/postalserver/postal:3.3.7}"
# Change the default to:
#   IMAGE="${POSTAL_IMAGE:-ghcr.io/flatroy/postal-api-extended:routes-api}"
```

### Option C — Edit the docker-compose template

If you used `postal bootstrap` to generate your config, the compose file is at
`/opt/postal/install/docker-compose.yml`. Replace the image reference:

```yaml
# Before
services:
  web:
    image: ghcr.io/postalserver/postal:3.3.7

# After
services:
  web:
    image: ghcr.io/flatroy/postal-api-extended:routes-api
```

Do this for **all three services**: `web`, `smtp`, and `worker`.

## Step 5 — Pull the new image and start Postal

```bash
docker pull ghcr.io/flatroy/postal-api-extended:routes-api
postal start
```

Verify all components are running:

```bash
postal status
# Should show: web, smtp, worker all running
```

## Step 6 — Run database migrations

The fork adds a `management_api_keys` table. Run:

```bash
postal upgrade
```

This is safe — it only adds tables, never drops or alters existing ones.

## Step 7 — Create a management API key

```bash
# Find the web container name
docker ps | grep postal | grep web

# Open Rails console (replace postal-web-1 with your container name)
docker exec -it postal-web-1 postal console
```

In the console:

```ruby
# Find your admin user
u = User.where(admin: true).first
# Or by email:
# u = User.find_by(email_address: "your-admin@example.com")

# Create the management API key
key = ManagementAPIKey.create!(name: "hidemail-management", user: u)

# Copy this key — it's shown ONLY once
puts "KEY: #{key.key}"
```

Type `exit` to leave the console.

## Step 8 — Find your server ID and HTTP endpoint UUID

```bash
MGMT_KEY="your-key-from-step-7"

# Server ID
curl -s -H "X-Management-API-Key: $MGMT_KEY" \
  https://postal.yourdomain.com/api/v1/manage/servers | jq '.data.servers[] | {id, name}'

# HTTP endpoint UUID (look for the "postal - web" endpoint)
curl -s -H "X-Management-API-Key: $MGMT_KEY" \
  https://postal.yourdomain.com/api/v1/manage/http_endpoints | jq '.data.http_endpoints[] | {name, uuid, url}'
```

If no HTTP endpoint exists yet, create one in the Postal web UI:
1. Log into your Postal web UI
2. Go to your server → HTTP Endpoints
3. Create one named "postal - web" pointing to your HideMail webhook URL
   (e.g. https://hidemail.app/postal/webhook)
4. Copy the UUID

## Step 9 — Verify the management API works

```bash
curl -s -H "X-Management-API-Key: $MGMT_KEY" \
  https://postal.yourdomain.com/api/v1/manage/domains | jq .

# Should return:
# {
#   "status": "success",
#   "data": { "domains": [...], "total": N, "pagination": {...} }
# }
```

## Step 10 — Configure HideMail

In your HideMail `.env`:

```env
POSTAL_MANAGEMENT_URL=https://postal.yourdomain.com
POSTAL_MANAGEMENT_KEY=your-key-from-step-7
POSTAL_SERVER_ID=your-server-id-from-step-8
POSTAL_WEB_ENDPOINT_UUID=your-endpoint-uuid-from-step-8
POSTAL_INBOUND_MX_HOST=mx.postal.yourdomain.com
```

Then clear config cache:

```bash
php artisan config:clear
```

## Step 11 — Test the full flow

1. Log into HideMail
2. Go to the custom domains page
3. Add a test domain
4. Verify it appears in Postal
5. Click "Verify MX" (after adding the MX record)
6. Delete the test domain — verify it's removed from Postal too

## Rollback

```bash
postal stop
export POSTAL_IMAGE=ghcr.io/postalserver/postal:3.3.7
postal start
```

Your data is untouched — the fork only adds tables and routes.

## GHCR — How automatic builds work

The workflow at `.github/workflows/ghcr-image.yml` triggers on every push to
`main` or `routes-api`. It builds the Docker image (target: `full`, with assets
precompiled) and pushes to `ghcr.io/flatroy/postal-api-extended` with tags:

- `:latest` — **only applied to `routes-api` builds**, so production can safely
  pull `:latest` without risk of getting a `main` build that lacks the
  management API
- `:routes-api` — the branch name tag
- `:sha-<commit>` — pinned to a specific commit

For production, **pin to `:sha-<commit>`** or use `:routes-api` rather than
`:latest` to avoid unexpected updates.

To update production after a new push:

```bash
postal stop
docker pull ghcr.io/flatroy/postal-api-extended:routes-api
postal start
postal upgrade  # run migrations if any
```

To check build status:
https://github.com/Flatroy/postal-api-extended/actions/workflows/ghcr-image.yml

To manage the package (visibility, delete old tags):
https://github.com/Flatroy/postal-api-extended/pkgs/container/postal-api-extended

## Notes

- The fork's management API endpoints are under `/api/v1/manage/*` and require
  the `X-Management-API-Key` header (separate from the regular Postal API key).
- The management API key is stored as a digest — the raw key is only shown once
  at creation time.
- The fork tracks upstream releases. To update, pull the latest from upstream
  and rebuild. See `CONTRIBUTING.md` for the merge process.
