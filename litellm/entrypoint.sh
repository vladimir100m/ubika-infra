#!/bin/sh
# Entrypoint script to build DATABASE_URL from components and configure secrets

if [ -n "$DB_USERNAME" ] && [ -n "$DB_PASSWORD" ] && [ -n "$DB_ENDPOINT" ]; then
  # URL encode the password to handle special characters
  ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$DB_PASSWORD', safe=''))")
  export DATABASE_URL="postgresql://${DB_USERNAME}:${ENCODED_PASSWORD}@${DB_ENDPOINT}:${DB_PORT:-5432}/${DB_NAME:-litellm}"
  echo "✅ Database URL configured successfully: postgresql://${DB_USERNAME}:***@${DB_ENDPOINT}:${DB_PORT:-5432}/${DB_NAME:-litellm}"
  
  # Wait for RDS to be ready with TCP connectivity check
  echo "⏳ Waiting for database TCP connectivity..."
  MAX_RETRIES=30
  RETRY_COUNT=0
  DB_HOST="${DB_ENDPOINT}"
  DB_PORT_NUM="${DB_PORT:-5432}"
  
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if timeout 3 sh -c "echo > /dev/tcp/${DB_HOST}/${DB_PORT_NUM}" 2>/dev/null; then
      echo "✅ Database TCP port is reachable!"
      sleep 2
      break
    else
      RETRY_COUNT=$((RETRY_COUNT + 1))
      if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "⏳ Database not reachable yet (attempt $RETRY_COUNT/$MAX_RETRIES), retrying in 3 seconds..."
        sleep 3
      fi
    fi
  done
  
  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "⚠️  Database TCP connection failed after ${MAX_RETRIES} attempts"
    echo "🔍 Checking network connectivity..."
    echo "   DB Host: ${DB_HOST}"
    echo "   DB Port: ${DB_PORT_NUM}"
    echo "❌ Continuing anyway - LiteLLM Prisma will handle retries"
  fi
else
  echo "⚠️  Database credentials not provided - running without database"
fi

# LITELLM_MASTER_KEY is passed as an environment variable from ECS task secrets
# No need to construct it here - it comes from AWS Secrets Manager

# Execute litellm proxy with all arguments
exec python3 -m litellm.proxy.proxy_cli "$@"
