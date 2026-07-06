![GitHub Header](https://github.com/postalserver/.github/assets/4765/7a63c35d-2f47-412f-a6b3-aebc92a55310)

> **Maintained fork.** This is HideMail's fork of `csiocc/postal-api-extended`, which tracks upstream `postalserver/postal`. Adds the management API plus routes/HTTP-endpoints management on Postal 3.3.5. Remotes: `origin`=csiocc, `upstream`=postalserver.

**Postal** is a complete and fully featured mail server for use by websites & web servers. Think Sendgrid, Mailgun or Postmark but open source and ready for you to run on your own servers. 

* [Documentation](https://docs.postalserver.io)
* [Installation Instructions](https://docs.postalserver.io/getting-started)
* [FAQs](https://docs.postalserver.io/welcome/faqs) & [Features](https://docs.postalserver.io/welcome/feature-list)
* [Discussions](https://github.com/postalserver/postal/discussions) - ask for help or request a feature
* [Join us on Discord](https://discord.postalserver.io)

## GitHub Container Image

This fork publishes a runnable Docker image to GitHub Container Registry on every push to `main`
and via manual workflow dispatch.

- Image name: `ghcr.io/<github-owner>/<github-repository>`
- Tags: `latest` and `sha-<commit-sha>`
- Build target: `full`

Example:

```bash
docker pull ghcr.io/<owner>/<repo>:latest
```

If the package is private:

```bash
echo "<github_pat_with_read:packages>" | docker login ghcr.io -u <github-username> --password-stdin
docker pull ghcr.io/<owner>/<repo>:latest
```

Runtime notes:

- The image expects a Postal config at `POSTAL_CONFIG_FILE_PATH` and a signing key at `POSTAL_SIGNING_KEY_PATH`.
- The repo's root [`docker-compose.yml`](./docker-compose.yml) is a test helper, not a production deployment manifest.
