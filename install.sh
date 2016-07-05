#! /bin/bash


if [ ! -d "/app" ]; then
  mkdir /app
  chmod 777 /app
  virtualenv /app/ve
fi

source /app/ve/bin/activate
pip install -r requirements.txt

cat > /etc/nginx/site-enabled/wvchallenge.conf <<NGINX_CONF
worker_processes 1;

user nobody nogroup;
pid /tmp/nginx.pid;
error_log /tmp/nginx.error.log;

events {
  worker_connections 1024;
  accept_mutex off;
}

http {
  include mime.types;
  access_log /tmp/nginx.access.log combined;
  sendfile on;

  server {
    listen 80 deferred default_server;
    server_name _;
    keepalive_timeout 5;

    location / {
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header Host $http_host;
      proxy_redirect off;
      proxy_pass http://127.0.0.1:8000;
    }
  }
}
NGINX_CONF

cat > /etc/supervisord.d/wvchallenges.ini <<SUPERVISORD_CONF
[program:gunicorn]
command=/app/ve/bin/gunicorn app:app
directory=/app
user=nobody
autostart=true
autorestart=true
redirect_stderr=true
SUPERVISORD_CONF
