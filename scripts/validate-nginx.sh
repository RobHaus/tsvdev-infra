#!/usr/bin/env bash
#
# Check nginx configuration without touching the running host.
#
# Two parts:
#
#   1. Syntax. Every site config and snippet is installed into a throwaway
#      container, with stand-ins for the certificates and password files that
#      only exist on the host, and nginx -t is run against the result.
#
#   2. Behaviour. Header handling is the part that is easy to get subtly wrong
#      and impossible to see in a syntax check, so a container serves the real
#      snippets in front of an upstream that echoes what it received, and the
#      client address rules are asserted against it.
#
# Run before sudo ./scripts/apply-nginx.sh. Needs docker, no root.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NGINX_IMAGE="nginx:1.27-alpine"
NODE_IMAGE="node:24-alpine"
WORK="$(mktemp -d)"
NET="nginx-validate-$$"

pass() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
log()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
FAILURES=0

cleanup() {
  docker rm -f "$NET-echo" "$NET-proxy" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. Syntax
# ---------------------------------------------------------------------------

log "Checking site configuration syntax"

mkdir -p "$WORK/etc/nginx/sites-enabled" "$WORK/etc/nginx/snippets" \
         "$WORK/etc/letsencrypt" "$WORK/var/www/html"

for snippet in "$ROOT"/nginx/snippets/*.conf; do
  cp "$snippet" "$WORK/etc/nginx/snippets/tsvdev-$(basename "$snippet")"
done
cp "$ROOT"/nginx/sites-available/*.conf "$WORK/etc/nginx/sites-enabled/"

# One self-signed key pair stands in for every certbot certificate referenced by
# a site config. nginx only needs a loadable pair to validate.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -keyout "$WORK/etc/letsencrypt/key.pem" -out "$WORK/etc/letsencrypt/cert.pem" \
  -subj "/CN=validate" >/dev/null 2>&1

grep -rho 'letsencrypt/live/[^/]*' "$ROOT/nginx/sites-available" | cut -d/ -f3 | sort -u |
while read -r name; do
  mkdir -p "$WORK/etc/letsencrypt/live/$name"
  cp "$WORK/etc/letsencrypt/cert.pem" "$WORK/etc/letsencrypt/live/$name/fullchain.pem"
  cp "$WORK/etc/letsencrypt/key.pem" "$WORK/etc/letsencrypt/live/$name/privkey.pem"
done

printf 'ssl_session_cache shared:le_nginx_SSL:10m;\nssl_protocols TLSv1.2 TLSv1.3;\n' \
  > "$WORK/etc/letsencrypt/options-ssl-nginx.conf"
# 2048 bit, because a modern OpenSSL refuses anything smaller and nginx -t would
# fail on the parameters rather than on the files under test. Generating them
# takes long enough to be worth keeping between runs.
DH_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/tsvdev-infra/ssl-dhparams.pem"
if [[ ! -s "$DH_CACHE" ]]; then
  echo "     generating Diffie-Hellman parameters, this happens once"
  mkdir -p "$(dirname "$DH_CACHE")"
  openssl dhparam -out "$DH_CACHE" 2048 >/dev/null 2>&1
fi
cp "$DH_CACHE" "$WORK/etc/letsencrypt/ssl-dhparams.pem"
# shellcheck disable=SC2016  # a literal crypt string, nothing to expand
printf 'validate:$apr1$abcdefgh$0123456789abcdefghijk0\n' > "$WORK/etc/nginx/.htpasswd-staging"

# server_names_hash_bucket_size matches the host. The image default is smaller
# than the longest name in use here, which would fail for a reason that has
# nothing to do with these files.
cat > "$WORK/etc/nginx/nginx.conf" <<'EOF'
events { worker_connections 1024; }
http {
    include /etc/nginx/mime.types;
    server_names_hash_bucket_size 64;
    access_log off;
    include /etc/nginx/sites-enabled/*.conf;
}
EOF

# Mounted file by file rather than over /etc/nginx, which would hide mime.types
# and the rest of the image's own configuration.
if docker run --rm \
     -v "$WORK/etc/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
     -v "$WORK/etc/nginx/sites-enabled:/etc/nginx/sites-enabled:ro" \
     -v "$WORK/etc/nginx/snippets:/etc/nginx/snippets:ro" \
     -v "$WORK/etc/nginx/.htpasswd-staging:/etc/nginx/.htpasswd-staging:ro" \
     -v "$WORK/etc/letsencrypt:/etc/letsencrypt:ro" \
     -v "$WORK/var/www/html:/var/www/html:ro" \
     "$NGINX_IMAGE" nginx -t 2>&1 | sed 's/^/     /'; then
  pass "all site configs parse"
else
  fail "nginx -t rejected the configuration"
fi

# ---------------------------------------------------------------------------
# 2. Client address behaviour
# ---------------------------------------------------------------------------

log "Checking client address handling"

cat > "$WORK/echo.mjs" <<'EOF'
import { createServer } from "node:http";
createServer((req, res) => {
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify(req.headers));
}).listen(8080, "0.0.0.0");
EOF

# Two server blocks, differing only in which peers may declare a client address.
# 8080 stands in for production, where the peer is Cloudflare. 8081 uses the
# real published ranges, so a request from this test network is an untrusted
# peer, which is what a direct connection to the origin looks like.
cat > "$WORK/behaviour.conf" <<'EOF'
events { worker_connections 64; }
http {
    access_log off;
    resolver 127.0.0.11 ipv6=off;

    server {
        listen 8080;
        set_real_ip_from 10.0.0.0/8;
        set_real_ip_from 172.16.0.0/12;
        set_real_ip_from 192.168.0.0/16;
        real_ip_header CF-Connecting-IP;

        location / {
            include /etc/nginx/snippets/tsvdev-proxy-params.conf;
            proxy_pass http://echo:8080;
        }
    }

    server {
        listen 8081;
        include /etc/nginx/snippets/tsvdev-cloudflare-real-ip.conf;

        location / {
            include /etc/nginx/snippets/tsvdev-proxy-params.conf;
            proxy_pass http://echo:8080;
        }
    }
}
EOF

docker network create "$NET" >/dev/null
docker run -d --name "$NET-echo" --network "$NET" --network-alias echo \
  -v "$WORK/echo.mjs:/echo.mjs:ro" "$NODE_IMAGE" node /echo.mjs >/dev/null
docker run -d --name "$NET-proxy" --network "$NET" \
  -v "$WORK/behaviour.conf:/etc/nginx/nginx.conf:ro" \
  -v "$WORK/etc/nginx/snippets:/etc/nginx/snippets:ro" \
  -p 127.0.0.1:18080:8080 -p 127.0.0.1:18081:8081 \
  "$NGINX_IMAGE" >/dev/null

for _ in $(seq 30); do
  curl -fsS --max-time 2 http://127.0.0.1:18080/ >/dev/null 2>&1 && break
  sleep 1
done

# A request carrying both a forged X-Forwarded-For and a CF-Connecting-IP. The
# first is what an attacker controls; the second is what Cloudflare sets.
probe() {
  curl -fsS --max-time 5 \
    -H "X-Forwarded-For: 198.51.100.7, 203.0.113.200" \
    -H "CF-Connecting-IP: 203.0.113.9" \
    "http://127.0.0.1:$1/"
}

header() { python3 -c "import json,sys; print(json.load(sys.stdin).get('$2',''))" <<<"$1"; }

TRUSTED="$(probe 18080 || true)"
if [[ -z "$TRUSTED" ]]; then
  fail "trusted-peer probe got no response"
else
  xff="$(header "$TRUSTED" x-forwarded-for)"
  real="$(header "$TRUSTED" x-real-ip)"
  if [[ "$xff" == "203.0.113.9" ]]; then
    pass "trusted peer: X-Forwarded-For replaced with the declared client"
  else
    fail "trusted peer: X-Forwarded-For is '$xff', expected 203.0.113.9"
  fi
  if [[ "$real" == "203.0.113.9" ]]; then
    pass "trusted peer: X-Real-IP is the declared client"
  else
    fail "trusted peer: X-Real-IP is '$real', expected 203.0.113.9"
  fi
fi

UNTRUSTED="$(probe 18081 || true)"
if [[ -z "$UNTRUSTED" ]]; then
  fail "untrusted-peer probe got no response"
else
  xff="$(header "$UNTRUSTED" x-forwarded-for)"
  case "$xff" in
    *198.51.100.7*) fail "untrusted peer: forged X-Forwarded-For survived as '$xff'" ;;
    *203.0.113.9*)  fail "untrusted peer: CF-Connecting-IP was honoured as '$xff'" ;;
    "")             fail "untrusted peer: X-Forwarded-For was not set at all" ;;
    *)              pass "untrusted peer: X-Forwarded-For is the socket address ($xff)" ;;
  esac
fi

echo
if (( FAILURES )); then
  printf '\033[31m%d check(s) failed\033[0m\n' "$FAILURES"
  exit 1
fi
printf '\033[32mnginx configuration validated\033[0m\n'
