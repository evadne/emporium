web: env ROLE=WEB ./infra/foreman-app/start.sh
ngrok: ngrok http $(($PORT - 100)) --subdomain $NGROK_SUBDOMAIN --region eu -log stdout
