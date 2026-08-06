# VPS Architecture — server1.tsvdev.com

Last updated: 2026-07-24

Canonical reference for agents deploying services on this VPS — especially **dockerized game servers**.

> **Source of truth:** this file lives in the `tsvdev-infra` git repo (`/home/rob/tsvdev-infra/VPS-ARCHITECTURE.md`). Host-level proxy, firewall, SSH, Docker daemon, and bootstrap scripts are in that repo.

> **Quick start for game servers:** skip to [Deploying a Dockerized Game Server](#deploying-a-dockerized-game-server).

---

## Current State (2026-07-24)

| Item | Status |
|-------|--------|
| Running Docker containers | `tradeshots-game-server` |
| Live production HTTP sites | none (nginx present; no managed vhosts) |
| Disk free | ~90 GB of 118 GB |
| RAM available | ~4–5 GB of 5.8 GB |
| Kernel | `5.10.0-44-amd64` |
| Infra repo | `/home/rob/tsvdev-infra` → `https://github.com/RobHaus/tsvdev-infra` |

Retired and removed from this host (2026-07-24): **apk-portal**, **wartime**, **bbiw** / **bbiw_dev** / **bbiw.com.au**.

---

## Identity & Access

| Field | Value |
|-------|--------|
| Hostname | `server1.tsvdev.com` |
| Public IP | `162.0.236.23` |
| Provider | Namecheap KVM VPS |
| DNS | Cloudflare (domain `tsvdev.com`) |
| Primary user | `rob` (uid 1000, groups: `rob`, `sudo`, `docker`) |
| SSH port | **46789** (not 22) |
| SSH auth | Key-only (`PasswordAuthentication no`) |
| Root login | Enabled (`PermitRootLogin yes`) |
| Timezone | UTC |

### SSH connection

```bash
ssh -p 46789 rob@162.0.236.23
# or
ssh -p 46789 root@162.0.236.23
```

SSH policy fragment is managed in `tsvdev-infra` as `ssh/sshd_config.d/99-tsvdev.conf`.

---

## Hardware

| Resource | Value |
|----------|-------|
| CPU | 4 vCPU (x86_64) |
| RAM | 5.8 GiB |
| Swap | 4 GiB (`/swapfile`, in `/etc/fstab`) |
| Disk | 118 GB on `/dev/vda2` |
| NIC | `eth0` → `162.0.236.23/24` |

**Sizing guidance for game servers:** assume ~1–2 GB RAM for the OS/nginx/Docker overhead. A container using more than ~3.5 GB RAM will cause pressure on this host. Monitor with `free -h` and `docker stats`.

---

## Software Stack

| Component | Version | Notes |
|-----------|---------|-------|
| OS | Debian 11 (bullseye) | oldoldstable; plan upgrade later |
| Docker CE | 29.5.3 | apt repo: `download.docker.com/linux/debian bullseye` |
| Docker Compose | v5.1.4 (plugin) | `docker compose` (not `docker-compose`) |
| containerd | 2.2.4 | |
| nginx | 1.18.0 | Host reverse proxy + TLS (not containerized) |
| certbot | 1.12.0 | Auto-renew via `certbot.timer` |
| Python | 3.9.2 | System Python |

---

## Architecture Diagram

```
                         ┌─────────────────────────────────────┐
                         │         Internet / Players          │
                         └──────────────┬──────────────────────┘
                                        │
              ┌─────────────────────────┼─────────────────────────┐
              │                         │                         │
              ▼                         ▼                         ▼
     Cloudflare (optional)        Direct to IP              SSH :46789
     HTTP/S only, orange cloud     Game traffic MUST          Key auth
              │                   use this path (or grey-cloud DNS)
              ▼                         │
     nginx :80 / :443                   │
     TLS termination                    │
     reverse proxy                      │
              │                         │
              ▼                         ▼
     127.0.0.1:<app-port>      Docker published ports
     (web apps, admin UIs)      (game server TCP/UDP)
              │                         │
              └────────────┬────────────┘
                           ▼
                  Docker bridge (172.17.0.0/16)
                           │
                           ▼
                  Game server / app container(s)
```

### Two traffic paths — understand this before deploying

| Traffic type | Path | Tool |
|--------------|------|------|
| HTTP/HTTPS (web UI, REST API, status page) | Cloudflare → nginx → `127.0.0.1:PORT` | nginx reverse proxy |
| Game protocol (UDP/TCP, e.g. Minecraft, Valheim, Source) | Internet → UFW → Docker `ports:` mapping | **Direct exposure, no nginx** |

**Cloudflare orange-cloud (proxied) only supports HTTP/HTTPS.** Game clients cannot connect through the Cloudflare proxy. For game subdomains, set the DNS record to **DNS only (grey cloud)** so it resolves directly to `162.0.236.23`.

### Why nginx stays on the host

Managed by `tsvdev-infra`. Host nginx + certbot is intentional: thin HTTP proxy, reliable ACME renewals (`certbot.timer`), no Docker/`iptables` fights on :80/:443. There is **no** shared Docker “proxy” network — web apps publish to `127.0.0.1` only.

---

## Firewall (UFW)

Default policy: **deny incoming**, allow outgoing.

Baseline rules (from `tsvdev-infra/ufw/rules.sh`):

| Rule | Port | Purpose |
|------|------|---------|
| 80/tcp | HTTP | nginx (certbot challenges + redirects) |
| 443/tcp | HTTPS | nginx |
| 46789/tcp | SSH | Admin access |
| 7777/tcp | Game | TradeShots |

**Every additional game port must be explicitly opened.** Example:

```bash
sudo ufw allow 7777/udp comment 'MyGame server'
sudo ufw allow 7777/tcp comment 'MyGame server query'
sudo ufw status numbered
```

Verify listening after deploy:

```bash
ss -tlnup | grep -E '7777|PORT'
```

---

## Port Registry

Document new ports here when deploying. Update this table in git (`tsvdev-infra`).

| Port | Protocol | Service | Status |
|------|----------|---------|--------|
| 80 | TCP | nginx HTTP | in use |
| 443 | TCP | nginx HTTPS | in use |
| 46789 | TCP | SSH | in use |
| 7777 | TCP | TradeShots game server (Docker) | in use |
| 8572 | TCP | DiaryIQ app, production (Docker, `127.0.0.1` only, behind nginx) | in use |
| 8573 | TCP | DiaryIQ app, staging (Docker, `127.0.0.1` only, behind nginx) | in use |
| 8574 | TCP | DiaryIQ app, dev (Docker, `127.0.0.1` only, not proxied) | in use |
| 55432 | TCP | DiaryIQ Postgres, dev (Docker, `127.0.0.1` only) | in use |
| 55433 | TCP | DiaryIQ Postgres, production (Docker, `127.0.0.1` only, operator tooling) | in use |
| 55434 | TCP | DiaryIQ Postgres, staging (Docker, `127.0.0.1` only, operator tooling) | in use |

Pick unused ports above 1024 for new services.

---

## Directory Layout

```
/home/rob/
├── tsvdev-infra/             # THIS REPO — host platform (nginx, ufw, ssh, docker daemon, docs)
│   ├── VPS-ARCHITECTURE.md   # this file
│   ├── nginx/
│   ├── docker/
│   ├── ufw/
│   ├── ssh/
│   ├── certbot/
│   └── scripts/
├── VPS-ARCHITECTURE.md       # short pointer → tsvdev-infra
├── HOST-ENVIRONMENT.md       # short pointer → tsvdev-infra
├── tradeshots/               # TradeShots game-server deploy
├── source/repos/             # application source clones
├── <project-name>/           # one folder per deployed project
│   ├── docker-compose.yml
│   ├── Dockerfile            # if custom image
│   ├── .env                  # secrets (do not commit)
│   ├── data/                 # persistent bind-mount data
│   └── README.md             # project-specific notes
└── .docker/                  # Docker client config for rob user
```

**Convention:** all new projects live under `/home/rob/<project-name>/`, owned by `rob:rob`. App source clones live under `/home/rob/source/repos/`. Host platform changes go through `tsvdev-infra`.

---

## Docker Configuration

### Daemon settings (`/etc/docker/daemon.json`)

Managed copy: `tsvdev-infra/docker/daemon.json`. Apply with `sudo ./scripts/apply-docker.sh`.

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

Logs rotate at 10 MB × 3 files per container.

### Who can run Docker

- User `rob` is in the `docker` group — runs containers without sudo
- Root also has full access

### Standard compose pattern

```yaml
services:
  game-server:
    build: .                          # or image: vendor/game:latest
    container_name: mygame-server
    restart: unless-stopped
    ports:
      - "7777:7777/udp"               # game port — must match UFW rule
      - "7777:7777/tcp"               # if query port needed
    volumes:
      - ./data:/game/saves            # persist saves/config
    environment:
      - SERVER_NAME=My Game Server
    env_file:
      - .env
```

Web admin / HTTP only on loopback:

```yaml
ports:
  - "127.0.0.1:8080:8080"
```

### Lifecycle commands

```bash
cd /home/rob/<project-name>

docker compose up -d --build     # first deploy / rebuild
docker compose ps                # status
docker compose logs -f           # tail logs
docker compose down              # stop (keeps volumes)
docker compose down -v           # stop + delete named volumes (destructive)
docker stats --no-stream         # resource usage
```

### Cleanup

```bash
docker system prune -f           # remove unused images/networks
docker system df                 # disk usage breakdown
```

---

## Deploying a Dockerized Game Server

Step-by-step checklist for an agent building a new game server here.

### 1. Create project directory

```bash
mkdir -p /home/rob/mygame/{data,config}
cd /home/rob/mygame
chown -R rob:rob /home/rob/mygame
```

### 2. Write `docker-compose.yml`

- Map **all** ports the game needs (check upstream docs for UDP vs TCP)
- Bind-mount `./data` for saves/world files
- Set `restart: unless-stopped`
- Pin image tags in production (avoid `:latest` drift)

### 3. Open firewall ports

```bash
sudo ufw allow <PORT>/<udp|tcp> comment '<game-name>'
sudo ufw status
```

Repeat for every port the game uses (game, query, RCON, etc.).

### 4. DNS (if players connect by hostname)

In Cloudflare for `tsvdev.com` (or another domain):

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| A | `mygame` | `162.0.236.23` | **DNS only (grey cloud)** |

Players connect to `mygame.tsvdev.com:<port>` or `162.0.236.23:<port>`.

### 5. Build and start

```bash
cd /home/rob/mygame
docker compose up -d --build
docker compose ps
docker compose logs -f
```

### 6. Verify

```bash
docker ps
ss -ulnp | grep <PORT>
ss -tlnp | grep <PORT>
```

### 7. (Optional) Web admin panel via nginx

1. Publish the web component on localhost only (e.g. `127.0.0.1:8080`)
2. Add a site under `tsvdev-infra/nginx/sites-available/` and apply:

```bash
cd /home/rob/tsvdev-infra
# edit nginx/sites-available/mygame.tsvdev.com.conf
sudo ./scripts/apply-nginx.sh
sudo certbot --nginx -d mygame.tsvdev.com
```

3. Update the [Port Registry](#port-registry) and commit in `tsvdev-infra`.

### 8. Document the deployment

Update the Port Registry in this file and add a `README.md` in the project folder with ports, env vars, and backup notes.

---

## nginx (Web Traffic Only)

Configs are managed in **`tsvdev-infra/nginx/`** and applied with `sudo ./scripts/apply-nginx.sh`.

Every `.conf` in `nginx/snippets/` is installed to `/etc/nginx/snippets/tsvdev-<name>.conf`. That directory is shared with the distribution and with certbot, hence the prefix.

| Snippet | Purpose |
|---------|---------|
| `tsvdev-proxy-params.conf` | Shared proxy headers. Sets `X-Forwarded-For` to one observed address rather than appending to what the client sent, so an upstream reading it is not reading client input. |
| `tsvdev-cloudflare-real-ip.conf` | Lets Cloudflare peers, and only Cloudflare peers, declare the visitor address via `CF-Connecting-IP`. Include it in any server block for a proxied name, otherwise logs and upstreams see a Cloudflare address shared by every visitor. |

### Before applying

```bash
./scripts/validate-nginx.sh      # container-based, no root, no effect on the host
sudo ./scripts/apply-nginx.sh
```

`validate-nginx.sh` parses every site config against stand-in certificates and then asserts the client address rules against a live nginx with an echo upstream. Cloudflare adds ranges occasionally, so refresh the trusted set and commit the diff when it changes:

```bash
./scripts/update-cloudflare-ips.sh
```

### Active vhosts

| Config file | Domain | Upstream | Status |
|-------------|--------|----------|--------|
| `diaryiq.com.conf` | diaryiq.com (www → apex) | `127.0.0.1:8572` | active (project: `/home/rob/diaryiq/`) |
| `staging.diaryiq.com.conf` | staging.diaryiq.com | `127.0.0.1:8573` | active, basic auth + noindex (project: `/home/rob/diaryiq-staging/`) |
| `smartbooks.tsvdev.com.conf` | smartbooks.tsvdev.com | `127.0.0.1:8572` (`/v1/` only) | legacy redirect, retire when no extension points at it |

### Common nginx commands

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo tail -f /var/log/nginx/error.log
```

nginx binary: `/usr/sbin/nginx` (may not be in non-root `$PATH`).

---

## TLS / certbot

Renewal: automatic via `certbot.timer`. Deploy hook (reload nginx) is installed from `tsvdev-infra/certbot/renewal-hooks/deploy/reload-nginx.sh`.

```bash
sudo certbot renew --dry-run
sudo certbot renew && sudo systemctl reload nginx
```

New cert for a web service:

```bash
sudo certbot --nginx -d mygame.tsvdev.com
```

After retiring a hostname, delete its cert lineage:

```bash
sudo certbot delete --cert-name mygame.tsvdev.com
```

---

## Networking Reference

| Interface | Address | Purpose |
|-----------|---------|---------|
| eth0 | 162.0.236.23/24 | Public |
| docker0 | 172.17.0.1/16 | Docker bridge (default) |
| lo | 127.0.0.1 | Localhost — nginx upstreams bind here |

---

## Security Notes

- UFW default-deny; only explicitly opened ports are reachable
- SSH: port 46789, key-only authentication
- Root SSH login is enabled — consider disabling once `rob` key access is confirmed
- Do not commit `.env` files with secrets
- Cloudflare hides origin IP for proxied HTTP hosts; game ports expose the origin IP directly
- Keep Docker images pinned and updated for security patches

---

## Operational Runbook

### Apply / rebuild platform configs

```bash
cd /home/rob/tsvdev-infra
sudo ./scripts/apply.sh
```

Fresh metal:

```bash
sudo ./scripts/bootstrap-from-metal.sh
sudo ./scripts/apply.sh
```

### Check health

```bash
uptime && free -h && df -h /
docker ps -a
systemctl is-active docker nginx
sudo ufw status
```

### After kernel updates

```bash
test -f /var/run/reboot-required && cat /var/run/reboot-required
sudo reboot
```

Containers with `restart: unless-stopped` come back automatically after reboot.

### Backing up game data

```bash
cd /home/rob/mygame && docker compose stop
tar -czf ~/mygame-backup-$(date +%F).tar.gz data/ config/
docker compose start
```

### Disk cleanup

```bash
docker system prune -a -f
du -sh /home/rob/* /var/lib/docker
```

---

## Removed / Legacy (do not recreate unless asked)

| Project | Notes |
|---------|-------|
| apk-portal | Removed 2026-07-24 (containers, nginx, project dir) |
| wartime | Removed 2026-07-24 |
| bbiw / bbiw_dev / bbiw.com.au | Removed 2026-07-24 (nginx + certs via cleanup script) |
| myBalance | WordPress + MySQL — moved to another VPS (June 2026) |
| flask-upload-service | Part of myBalance; removed |

If leftover nginx/certs remain on a host:

```bash
sudo /home/rob/tsvdev-infra/scripts/cleanup-legacy-services.sh
```

---

## Agent Checklist Summary

When deploying a dockerized game server on this VPS:

- [ ] Create project under `/home/rob/<name>/`
- [ ] Write `docker-compose.yml` with correct UDP/TCP port mappings
- [ ] Persist data via bind mount (`./data`) or named volume
- [ ] Open all required ports in UFW (`sudo ufw allow …`)
- [ ] Set Cloudflare DNS to **grey cloud** for game hostname
- [ ] `docker compose up -d --build`
- [ ] Verify with `docker ps`, `ss -ulnp`, external connection test
- [ ] (Optional) Add nginx vhost in `tsvdev-infra` + certbot for HTTP admin UI only
- [ ] Update Port Registry in this file (commit in `tsvdev-infra`)
- [ ] Add project `README.md`
