# tsvdev-infra

Host infrastructure for **server1.tsvdev.com** (`162.0.236.23`).

This repo is the source of truth for rebuilding the VPS *platform* from metal: nginx reverse proxy, certbot, Docker daemon settings, UFW, SSH hardening, and operational docs. Application stacks (game servers, web apps) live in their own repos under `/home/rob/<project>/` and plug into what this defines.

## What lives here

| Path | Purpose |
|------|---------|
| `VPS-ARCHITECTURE.md` | Canonical host reference (ports, deploy rules, runbooks) |
| `nginx/` | Site configs + shared snippets (applied to `/etc/nginx`) |
| `docker/daemon.json` | Docker log rotation / daemon options |
| `ufw/rules.sh` | Baseline firewall (80, 443, SSH) |
| `ssh/sshd_config.d/` | SSH port + auth policy fragment |
| `certbot/` | Renew hooks (reload nginx after renew) |
| `scripts/bootstrap-from-metal.sh` | Fresh Debian → packages + first apply |
| `scripts/apply.sh` | Idempotent apply of all managed configs |
| `scripts/cleanup-legacy-services.sh` | One-shot removal of retired vhosts/certs/UFW rules |

## Design choices

- **nginx + certbot stay on the host** (not Docker). Game traffic bypasses nginx; the proxy is TLS + a few HTTP/WS upstreams. Host packages keep ACME renewals simple.
- **No shared Docker proxy network.** Web apps bind `127.0.0.1:<port>`; nginx proxies to localhost.
- **Apps own their compose files.** This repo does not ship application containers.

## Quick start (existing host)

```bash
cd /home/rob/tsvdev-infra
sudo ./scripts/apply.sh
```

## From metal (new Debian 11+ box)

1. Create user `rob`, SSH key auth, clone this repo to `/home/rob/tsvdev-infra`
2. Run:

```bash
sudo ./scripts/bootstrap-from-metal.sh
sudo ./scripts/apply.sh
```

3. Point Cloudflare DNS (grey cloud for origin-facing hosts) and issue certs when you add nginx sites:

```bash
sudo certbot --nginx -d example.tsvdev.com
```

## Adding a web vhost

1. Drop a config in `nginx/sites-available/<name>.conf` (HTTP-only is fine; certbot adds SSL)
2. `sudo ./scripts/apply-nginx.sh`
3. `sudo certbot --nginx -d <hostname>`
4. Update the Port Registry in `VPS-ARCHITECTURE.md`

## Legacy cleanup

If apk-portal / wartime / bbiw nginx sites or certs are still on the host:

```bash
sudo ./scripts/cleanup-legacy-services.sh
```
