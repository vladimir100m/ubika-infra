# Get the docker compose file
curl -O https://raw.githubusercontent.com/BerriAI/litellm/main/docker-compose.yml

# Add the master key - set your own value
# Example: LITELLM_MASTER_KEY="your-random-key"
echo 'LITELLM_MASTER_KEY="<LITELLM_MASTER_KEY>"' > .env

# Add the litellm salt key - you cannot change this after adding a model
# It is used to encrypt / decrypt your LLM API Key credentials
# We recommend - https://1password.com/password-generator/ 
# password generator to get a random hash for litellm salt key
# Example: LITELLM_SALT_KEY="your-random-salt"
echo 'LITELLM_SALT_KEY="<LITELLM_SALT_KEY>"' >> .env

# Start
docker compose up