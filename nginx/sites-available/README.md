# Placeholder — no production HTTP sites are managed yet.
# Add vhosts as nginx/sites-available/<name>.conf then run:
#   sudo ./scripts/apply-nginx.sh
#   sudo certbot --nginx -d <hostname>
#
# Example (HTTP only; certbot will add listen 443 / certificates):
#
# server {
#     listen 80;
#     listen [::]:80;
#     server_name app.tsvdev.com;
#
#     location /.well-known/acme-challenge/ {
#         root /var/www/html;
#     }
#
#     location / {
#         include /etc/nginx/snippets/tsvdev-proxy-params.conf;
#         proxy_pass http://127.0.0.1:8080;
#     }
# }
