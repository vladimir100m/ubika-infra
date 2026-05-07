# Rendered by Terraform with LiteLLM private IP; synced to S3 for Nginx EC2 user-data.
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    location /health {
        access_log off;
        return 200 'ok\n';
        add_header Content-Type text/plain;
    }

    # LiteLLM admin UI sometimes requests this literal Next placeholder; map to real paths on the proxy.
    location /litellm-asset-prefix/ {
        rewrite ^/litellm-asset-prefix/(.*)$ /$1 break;
        proxy_pass http://${litellm_private_ip}:4000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
    }

    location / {
        proxy_pass http://${litellm_private_ip}:4000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
    }
}
