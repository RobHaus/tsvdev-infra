# Active:
#   diaryiq.com.conf         → DiaryIQ production, apex + www redirect (127.0.0.1:8572), project /home/rob/diaryiq
#   staging.diaryiq.com.conf → DiaryIQ staging, basic auth + noindex (127.0.0.1:8573), project /home/rob/diaryiq-staging
#
# Apply:
#   sudo ./scripts/apply-nginx.sh
#
# Certificates. Production was issued with the nginx plugin, which rewrites the
# vhost in place. Staging uses the webroot plugin instead so the config in this
# repo stays authoritative:
#   sudo certbot --nginx -d diaryiq.com -d www.diaryiq.com
#   sudo certbot certonly --webroot -w /var/www/html -d staging.diaryiq.com
#
# Staging basic auth credentials live in /etc/nginx/.htpasswd-staging:
#   sudo htpasswd -c /etc/nginx/.htpasswd-staging <username>
