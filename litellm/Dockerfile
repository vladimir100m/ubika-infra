FROM docker.litellm.ai/berriai/litellm:main-latest

# Copy configuration file
COPY litellm_config.yaml /app/config.yaml

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]