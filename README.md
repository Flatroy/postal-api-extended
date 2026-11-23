![GitHub Header](https://github.com/postalserver/.github/assets/4765/7a63c35d-2f47-412f-a6b3-aebc92a55310)

> **Maintained fork of [postalserver/postal](https://github.com/postalserver/postal).**
> Synced with upstream **[v3.5.0](https://github.com/postalserver/postal/releases/tag/3.5.0)** (released 2026-11-20).
> Active branch: [`routes-api`](https://github.com/Flatroy/postal-api-extended/tree/routes-api). Used in production by [HideMail](https://hidemail.app).

## What this fork adds

Everything from upstream Postal 3.5.0, plus:

- **Management API** under `/api/v1/manage/*`. CRUD for [users](doc/api/users.md), [organizations](doc/api/organizations.md), [servers](doc/api/servers.md), [credentials](doc/api/credentials.md), [domains](doc/api/domains.md) (including DNS verification), [routes](doc/api/routes.md) and [HTTP endpoints](doc/api/http_endpoints.md). Index endpoints are paginated. See the [API overview](doc/api/README.md).
- **Management API keys.** A separate key type (`X-Management-API-Key`), bound to an admin user and created on the user edit screen. Keys are stored as digests and shown only once. Server API keys still work only for the send and message endpoints, and they cannot call the management API.
- **Staged DKIM rotation over the API.** `PATCH /api/v1/manage/domains/:uuid` with `rotate_dkim_key=true` works like upstream's web UI: if the current DKIM record is verified, the new key waits under a new selector until its DNS record is verified, so signing never breaks. `cancel_pending_dkim_key=true` discards a pending key. See [domains.md](doc/api/domains.md).
- **Docker image on GHCR**, built by [`ghcr-image.yml`](.github/workflows/ghcr-image.yml).
- **One extra table**, `management_api_keys`. The fork does not change upstream tables, so `postal upgrade` is the only migration step.

The legacy send API (`/api/v1/send/*`, `/api/v1/messages/*`) is unchanged.

To move an existing upstream install to this fork, read [doc/migrating-to-fork.md](doc/migrating-to-fork.md).

### Syncing with upstream

Upstream releases are merged into `routes-api`. Each merge must pass the full rspec suite before it is pushed. After you deploy a new image, run `postal upgrade` to apply new migrations.

| Fork commit | Upstream release |
| --- | --- |
| `7072520` (2026-11-23) | 3.5.0 |
| `da5227f` (2026-07-07) | 3.3.7 |

---

**Postal** is a complete and fully featured mail server for use by websites & web servers. Think Sendgrid, Mailgun or Postmark but open source and ready for you to run on your own servers. 

* [Documentation](https://docs.postalserver.io)
* [Installation Instructions](https://docs.postalserver.io/getting-started)
* [FAQs](https://docs.postalserver.io/welcome/faqs) & [Features](https://docs.postalserver.io/welcome/feature-list)
* [Discussions](https://github.com/postalserver/postal/discussions) - ask for help or request a feature
* [Join us on Discord](https://discord.postalserver.io)

## GitHub Container Image

Every push to `routes-api` or `main`, and every manual workflow run, publishes an image to GitHub Container Registry:

- `ghcr.io/flatroy/postal-api-extended:latest`: `routes-api` only. Use this tag in production.
- `ghcr.io/flatroy/postal-api-extended:<branch>`: the latest build of that branch.
- `ghcr.io/flatroy/postal-api-extended:sha-<commit-sha>`: one exact build, for pinning and rollbacks.
- Build target: `full`.

```bash
docker pull ghcr.io/flatroy/postal-api-extended:latest
```

The package is public, so no login is needed to pull.

Runtime notes:

- The image expects a Postal config at `POSTAL_CONFIG_FILE_PATH` and a signing key at `POSTAL_SIGNING_KEY_PATH`.
- The repo's root [`docker-compose.yml`](./docker-compose.yml) is a test helper, not a production deployment manifest.
