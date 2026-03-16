ARG LITELLM_VERSION=litellm_stable_release_branch-v1.73.0-stable
FROM ghcr.io/berriai/litellm:${LITELLM_VERSION}

# Copy your specific config to the expected location
# We use /app/config.yaml as it is the standard path LiteLLM looks for
COPY config/default-config-us-east-1.yaml /app/config.yaml

# Set the working directory
WORKDIR /app

# Override CMD to point to your new config file.
# Note: We do NOT redefine ENTRYPOINT because the base image already has it.
# We just provide the arguments:
CMD ["--config", "/app/config.yaml", "--port", "4000"]