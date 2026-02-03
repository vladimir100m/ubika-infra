#!/bin/sh
# Entrypoint script to build DATABASE_URL from components and configure secrets

if [ -n "$DB_USERNAME" ] && [ -n "$DB_PASSWORD" ] && [ -n "$DB_ENDPOINT" ]; then
  # URL encode the password to handle special characters
  ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$DB_PASSWORD', safe=''))")
  export DATABASE_URL="postgresql://${DB_USERNAME}:${ENCODED_PASSWORD}@${DB_ENDPOINT}:${DB_PORT:-5432}/${DB_NAME:-litellm}"
  echo "Database URL configured successfully"
else
  echo "Database credentials not provided - running without database"
fi

# LITELLM_MASTER_KEY is passed as an environment variable from ECS task secrets
# No need to construct it here - it comes from AWS Secrets Manager

# Execute litellm proxy with all arguments
exec python3 -m litellm.proxy.proxy_cli "$@"
