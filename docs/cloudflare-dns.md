# Cloudflare DNS checklist (not automated)
#
# Zone: tsvdev.com
# Origin: 162.0.236.23
#
# Rules of thumb:
# - HTTP/HTTPS sites that need real client certs or non-CF features: DNS only (grey cloud)
# - Normal public websites OK with orange cloud (proxied)
# - Game hostnames / direct UDP-TCP game ports: ALWAYS DNS only (grey cloud)
# - SSH is never via Cloudflare; connect to IP:46789
#
# After retiring a service, delete or grey-cloud-disable its DNS record and
# remove the matching nginx site + certbot lineage on the host.
