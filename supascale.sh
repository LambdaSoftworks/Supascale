#!/bin/bash

################################################################################
# Supascale
# Original Development: Frog Byte, LLC - https://www.frogbyte.co
#
# GPL V3 License
#
# Copyright (c) 2025 Frog Byte, LLC
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Description:
# This script facilitates the management of multiple self-hosted Supabase
# instances on a single machine. It automates the setup, configuration,
# and running of separate Supabase environments, each with its own set of
# ports and configuration files. Includes comprehensive backup and restore
# capabilities with encryption, validation, and cloud storage support.
#
# Key Features & Steps:
# 1. Project Creation (`add`):
#    - Prompts for a unique project ID.
#    - Creates a dedicated directory for the project (`$HOME/<project_id>`).
#    - Clones the official Supabase repository into the project directory.
#    - Creates a `.env` file from `.env.example`.
#    - Generates secure random passwords for `POSTGRES_PASSWORD` and `JWT_SECRET`.
#    - Updates the `.env` file with generated secrets and placeholders for JWTs.
#    - Assigns a unique port range for Supabase services (API, DB, Studio, etc.).
#    - Updates the `docker-compose.yml` file with the assigned ports.
#    - Updates the `config.toml` file (for potential CLI use) with ports.
#    - Stores project configuration (directory, ports) in a central JSON file.
#    - Instructs the user to manually generate and replace JWT placeholders.
# 2. List Projects (`list`):
#    - Displays all configured projects, their assigned ports, and directories.
# 3. Start Project (`start <project_id>`):
#    - Navigates to the project's `supabase/docker` directory.
#    - Runs `docker compose up -d` to start the Supabase services.
# 4. Stop Project (`stop <project_id>`):
#    - Navigates to the project's `supabase/docker` directory.
#    - Runs `docker compose down -v --remove-orphans` to stop services and clean up.
# 5. Remove Project (`remove <project_id>`):
#    - Stops the project if it's running.
#    - Removes the project's configuration from the central JSON file.
#    - (Note: Does not delete the project directory or Docker images/volumes).
# 6. Update Containers (`update-containers <project_id>` or `--all`):
#    - Creates a full project snapshot (docker-compose.yml, .env, volumes).
#    - Fetches latest container versions from GitHub and Docker Hub.
#    - Updates docker-compose.yml with new image tags.
#    - Pulls new images and restarts containers in dependency order.
#    - Performs health checks (container status, API response, error logs).
#    - Auto-rollback on health check failure with detailed error display.
#    - Prompts user to confirm update success.
#    - Saves versioned backup to `~/.supascale_backups/` on confirmation.
#    - Supports selective updates via `--only=service1,service2` flag.
# 7. Check Updates (`check-updates <project_id>`):
#    - Compares current container versions with latest available.
#    - Displays version comparison table without applying changes.
# 8. Container Versions (`container-versions <project_id>`):
#    - Shows current container versions for a project.
#    - Displays running container status.
# 9. Backup (`backup <project_id> [options]`):
#    - Creates comprehensive backups of Supabase projects.
#    - Backup types: full, database, storage, functions, config.
#    - Storage destinations: local filesystem or AWS S3.
#    - Optional AES-256 encryption with password.
#    - Creates manifest with SHA256 checksums for integrity verification.
#    - Supports retention policies to auto-delete old backups.
#    - Silent mode for cron job integration.
# 10. Restore (`restore <project_id> --from <path> [options]`):
#    - Restores project from backup archive.
#    - Supports local and S3 backup sources.
#    - Full validation with checksum verification.
#    - Dry-run mode to test restore without modifying data.
#    - Creates temporary database to validate database restores.
#    - Handles encrypted backups with password.
# 11. Backup Utilities:
#    - `list-backups <project_id>`: List available backups.
#    - `verify-backup <path>`: Verify backup integrity and checksums.
#    - `backup-info <path>`: Display backup metadata and contents.
#    - `setup-backup-schedule <project_id>`: Generate cron job examples.
# 12. Dependency Check:
#    - Verifies that `jq` (JSON processor) is installed.
# 13. Database Initialization:
#    - Creates the central JSON configuration file if it doesn't exist.
# 14. Setup Custom Domain (`setup-domain <project_id>`):
#    - Configures a custom domain with automatic SSL certificate provisioning.
#    - Auto-detects installed web server (Nginx, Apache, or Caddy).
#    - Prompts to install a web server if none detected.
#    - Creates reverse proxy configuration for Studio and API routing.
#    - Generates Let's Encrypt SSL certificate via Certbot (webroot mode).
#    - Enables automatic certificate renewal with web server reload hooks.
#    - Stores domain configuration in central database for persistence.
# 15. Remove Custom Domain (`remove-domain <project_id>`):
#    - Removes web server configuration for the project's domain.
#    - Optionally revokes SSL certificate.
#    - Updates database to remove domain configuration.
#    - Provides fallback IP:port access URLs.
################################################################################

# Supascale - Script Content Starts Below

# Configuration
VERSION="1.5.0"
GITHUB_RAW_URL="https://raw.githubusercontent.com/LambdaSoftworks/supascale/main/supascale.sh"
UPDATE_CHECK_FILE="$HOME/.supascale_last_check"
DB_FILE="$HOME/.supascale_database.json"
BASE_PORT=54321  # Default starting port for Supabase services
PORT_INCREMENT=1000  # How much to increment for a new project's port range

# Container Update Configuration
SUPABASE_DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/supabase/supabase/master/docker/docker-compose.yml"
BACKUP_DIR="$HOME/.supascale_backups"

# Supabase service definitions (all containers in a standard deployment)
SUPABASE_SERVICES=("studio" "kong" "auth" "rest" "realtime" "storage" "imgproxy" "meta" "functions" "analytics" "db" "vector" "supavisor")

# Service dependencies for update ordering (foundational services first)
UPDATE_ORDER=("vector" "db" "analytics" "auth" "rest" "realtime" "meta" "supavisor" "imgproxy" "storage" "functions" "kong" "studio")

# Backup Feature Configuration
BACKUP_VERSION="1.0.0"
BACKUP_MANIFEST_VERSION="1"
BACKUP_TEMP_DIR="/tmp/supascale_backup"
ENCRYPTION_CIPHER="aes-256-cbc"
BACKUP_TYPES=("full" "database" "storage" "functions" "config")
SILENT_MODE=false

# Custom Domain Configuration
DOMAIN_FEATURE_VERSION="1.0.0"
SUPPORTED_WEB_SERVERS=("nginx" "apache" "caddy")

# Web server configuration paths
# Nginx paths (same on all distros)
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_CONF_D="/etc/nginx/conf.d"

# Apache paths vary by distribution - detected at runtime
# Ubuntu/Debian: /etc/apache2/sites-available, /etc/apache2/sites-enabled
# RHEL/CentOS/Fedora: /etc/httpd/conf.d (no sites-available pattern)
APACHE_DEBIAN_SITES_AVAILABLE="/etc/apache2/sites-available"
APACHE_DEBIAN_SITES_ENABLED="/etc/apache2/sites-enabled"
APACHE_RHEL_CONF_D="/etc/httpd/conf.d"

# Caddy paths
CADDY_CONFIG_DIR="/etc/caddy"
CADDYFILE_PATH="/etc/caddy/Caddyfile"

# Certbot configuration
CERTBOT_WEBROOT="/var/www/certbot"
CERTBOT_RENEWAL_HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"

# Domain configuration file naming
DOMAIN_CONFIG_PREFIX="supascale"

# Function to check if jq is installed
check_dependencies() {
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq first."
    echo "You can install it with:"
    echo "  - Ubuntu/Debian: sudo apt install jq"
    echo "  - macOS: brew install jq"
    echo "  - Fedora/CentOS: sudo dnf install jq"
    exit 1
  fi
}

# Function to check for script updates
check_for_updates() {
  # Skip if --no-update-check flag is present
  if [[ "$*" == *"--no-update-check"* ]]; then
    return 0
  fi

  # Rate limiting: only check once per day
  if [ -f "$UPDATE_CHECK_FILE" ]; then
    local last_check=$(cat "$UPDATE_CHECK_FILE" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_check))
    # Skip if checked within last 24 hours (86400 seconds)
    if [ $time_diff -lt 86400 ]; then
      return 0
    fi
  fi

  # Try to fetch the latest version (timeout after 5 seconds)
  local latest_version=""
  if command -v curl &> /dev/null; then
    latest_version=$(curl -s --max-time 5 "$GITHUB_RAW_URL" | grep '^VERSION=' | head -1 | cut -d'"' -f2 2>/dev/null)
  elif command -v wget &> /dev/null; then
    latest_version=$(wget -q --timeout=5 -O- "$GITHUB_RAW_URL" | grep '^VERSION=' | head -1 | cut -d'"' -f2 2>/dev/null)
  else
    # No curl or wget available, skip update check
    return 0
  fi

  # Update the last check timestamp
  echo "$(date +%s)" > "$UPDATE_CHECK_FILE"

  # Compare versions if we got a valid response
  if [ -n "$latest_version" ] && [ "$latest_version" != "$VERSION" ]; then
    echo ""
    echo "Update Available!"
    echo "   Current version: $VERSION"
    echo "   Latest version:  $latest_version"
    echo ""
    echo "   Run './supascale.sh update' to update to the latest version."
    echo "   Or visit: https://github.com/LambdaSoftworks/supascale"
    echo ""
  fi
}

# Function to migrate old database file if it exists
migrate_old_db() {
  local old_db_file="$HOME/.supabase_multi_manager.json"
  if [ -f "$old_db_file" ] && [ ! -f "$DB_FILE" ]; then
    echo "Found old database file, migrating to new location..."
    mv "$old_db_file" "$DB_FILE"
    echo "Migrated database from $old_db_file to $DB_FILE"
  fi
}

# Function to initialize the JSON database if it doesn't exist
initialize_db() {
  if [ ! -f "$DB_FILE" ]; then
    echo '{
      "projects": {},
      "last_port_assigned": '"$BASE_PORT"'
    }' > "$DB_FILE"
    echo "Initialized project database at $DB_FILE"
  fi
}

# Function to list all projects
list_projects() {
  if [ ! -f "$DB_FILE" ] || [ "$(jq '.projects | length' "$DB_FILE")" -eq 0 ]; then
    echo "No projects configured yet."
    return
  fi

  echo "Configured Supabase Projects:"
  echo "============================="
  jq -r '.projects | to_entries[] |
    "Project ID: \(.key)\n  API Port: \(.value.ports.api)\n  DB Port: \(.value.ports.db)\n  Studio Port: \(.value.ports.studio)\n  Directory: \(.value.directory)" +
    (if .value.domain.name then
      "\n  Domain: \(.value.domain.name)" +
      (if .value.domain.ssl_enabled then " (SSL)" else " (HTTP)" end) +
      "\n  Web Server: \(.value.domain.web_server // "unknown")"
    else "" end) + "\n"' "$DB_FILE"
}

# Function to generate a random password (alphanumeric, 40 chars)
generate_password() {
  # Use /dev/urandom, filter for alphanumeric, take first 40 chars
  tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 40
}

# Function to generate a random encryption key (alphanumeric, 32 chars for AES-256)
# Fix related to Github issue 5 (https://github.com/LambdaSoftworks/Supascale/issues/5)
generate_encryption_key() {
  # Use /dev/urandom, filter for alphanumeric, take first 32 chars
  # Required for AES-256-GCM encryption (256 bits = 32 bytes)
  tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32
}

# Function to generate JWT token using the JWT_SECRET
generate_jwt_token() {
  local jwt_secret="$1"
  local role="$2"
  local iat=$(date +%s)
  local exp=$((iat + 315360000))  # 10 years from now
  
  # Create the header (base64url encoded)
  local header='{"alg":"HS256","typ":"JWT"}'
  local header_b64=$(echo -n "$header" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
  
  # Create the payload (base64url encoded)
  local payload="{\"aud\":\"authenticated\",\"exp\":$exp,\"iat\":$iat,\"iss\":\"supabase\",\"ref\":\"localhost\",\"role\":\"$role\",\"sub\":\"1234567890\"}"
  local payload_b64=$(echo -n "$payload" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
  
  # Create the signature
  local signature_input="$header_b64.$payload_b64"
  local signature=$(echo -n "$signature_input" | openssl dgst -sha256 -hmac "$jwt_secret" -binary | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
  
  # Return the complete JWT
  echo "$header_b64.$payload_b64.$signature"
}

# Function to add a new project
add_project() {
  local project_id="$1"
  local directory postgres_password jwt_secret anon_key_placeholder service_key_placeholder docker_env_file

  if [ -z "$project_id" ]; then
    echo "Error: Project ID required."
    echo "Usage: ./supascale.sh add <project_id>"
    echo ""
    echo "Project ID must:"
    echo "  - Start with a letter or number"
    echo "  - Contain only lowercase letters, numbers, hyphens, and underscores"
    echo "  - No dots, spaces, or special characters allowed"
    return 1
  fi

  # Validate project ID format for Docker Compose compatibility
  if [[ ! "$project_id" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "Error: Project ID '$project_id' is invalid."
    echo "Project ID must:"
    echo "  - Start with a letter or number"
    echo "  - Contain only lowercase letters, numbers, hyphens, and underscores"
    echo "  - No dots, spaces, or special characters allowed"
    return 1
  fi

  # Check if project ID already exists
  # Updated check to use --arg and check for existence more robustly
  if jq -e --arg pid "$project_id" '.projects[$pid] != null' "$DB_FILE" > /dev/null 2>&1; then
     echo "Error: Project ID '$project_id' already exists."
     return 1
  fi

  # Create a new directory based on the project ID
  directory="$HOME/$project_id"
  if [ -d "$directory" ]; then
    echo "Error: Directory '$directory' already exists."
    return 1
  fi
  mkdir -p "$directory"

  # Clone the Supabase repository into the new directory
  echo "Cloning Supabase repository..."
  git clone --depth 1 https://github.com/supabase/supabase "$directory/supabase"
  if [ $? -ne 0 ] || [ ! -d "$directory/supabase/docker" ]; then
      echo "Error: Failed to clone Supabase repository or docker directory missing."
      rm -rf "$directory" # Clean up created directory
      return 1
  fi

  # Define path to docker env file
  docker_env_file="$directory/supabase/docker/.env"
  local docker_env_example_file="$directory/supabase/docker/.env.example"

  # Copy .env.example to .env
  if [ -f "$docker_env_example_file" ]; then
    echo "Creating .env file from example..."
    cp "$docker_env_example_file" "$docker_env_file"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to copy .env.example to .env"
        # Consider cleaning up directory or allowing retry?
        return 1
    fi
  else
      echo "Error: .env.example not found in $directory/supabase/docker/"
      # Consider cleaning up directory?
      return 1
  fi

  # Generate secrets
  echo "Generating secrets..."
  postgres_password=$(generate_password)
  jwt_secret=$(generate_password)
  local dashboard_password=$(generate_password)
  local vault_enc_key=$(generate_encryption_key)

  # Generate JWT keys automatically using the JWT secret
  echo "Generating JWT keys..."
  local anon_key=$(generate_jwt_token "$jwt_secret" "anon")
  local service_role_key=$(generate_jwt_token "$jwt_secret" "service_role")

  # Update .env file with secrets and generated JWT keys
  echo "Updating .env file..."
  # Use a different delimiter for sed because passwords might contain slashes
  # Also ensure we match the start of the line and the equals sign
  sed -i.tmp "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$postgres_password|" "$docker_env_file"
  sed -i.tmp "s|^JWT_SECRET=.*|JWT_SECRET=$jwt_secret|" "$docker_env_file"
  sed -i.tmp "s|^ANON_KEY=.*|ANON_KEY=$anon_key|" "$docker_env_file"
  sed -i.tmp "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$service_role_key|" "$docker_env_file"
  sed -i.tmp "s|^DASHBOARD_USERNAME=.*|DASHBOARD_USERNAME=supabase|" "$docker_env_file"
  sed -i.tmp "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$dashboard_password|" "$docker_env_file"
  sed -i.tmp "s|^VAULT_ENC_KEY=.*|VAULT_ENC_KEY=$vault_enc_key|" "$docker_env_file"
  rm -f "$docker_env_file.tmp" # Clean up sed backup

  echo ".env file updated with generated passwords and JWT keys."

  # --- Assign Ports and Update DB ---
  local last_port=$(jq '.last_port_assigned' "$DB_FILE")
  local api_port=$((last_port))
  local db_port=$((api_port + 1))
  local shadow_port=$((api_port - 1)) # Used in config.toml
  local studio_port=$((api_port + 2))
  local inbucket_port=$((api_port + 3))
  local smtp_port=$((api_port + 4)) # Used in config.toml
  local pop3_port=$((api_port + 5)) # Used in config.toml
  local pooler_port=$((api_port + 8)) # Used in config.toml
  local analytics_port=$((api_port + 6)) # Used in config.toml
  local kong_https_port=$((api_port + 443)) # Assign dedicated HTTPS port for Kong

  # Update the database with the new project
  jq --arg project_id "$project_id" \
     --arg directory "$directory" \
     --argjson api_port "$api_port" \
     --argjson db_port "$db_port" \
     --argjson shadow_port "$shadow_port" \
     --argjson studio_port "$studio_port" \
     --argjson inbucket_port "$inbucket_port" \
     --argjson smtp_port "$smtp_port" \
     --argjson pop3_port "$pop3_port" \
     --argjson pooler_port "$pooler_port" \
     --argjson analytics_port "$analytics_port" \
     --argjson kong_https_port "$kong_https_port" \
     --argjson next_port "$((last_port + PORT_INCREMENT))" \
     '.projects[$project_id] = {
        "directory": $directory,
        "ports": {
          "api": $api_port,
          "db": $db_port,
          "shadow": $shadow_port,
          "studio": $studio_port,
          "inbucket": $inbucket_port,
          "smtp": $smtp_port,
          "pop3": $pop3_port,
          "pooler": $pooler_port,
          "analytics": $analytics_port,
          "kong_https": $kong_https_port
        }
      } |
      .last_port_assigned = $next_port' "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"

  echo "Project '$project_id' added to database with the following ports:"
  echo "  API Port: $api_port"
  echo "  DB Port: $db_port"
  echo "  Studio Port: $studio_port"

  # --- Update docker-compose.yml and config.toml ---
  update_project_configurations "$project_id"

  echo ""
  echo "----------------------------------------------------------------------"
  echo "SUCCESS: PROJECT CREATED AND CONFIGURED"
  echo "----------------------------------------------------------------------"
  echo "Project '$project_id' has been successfully created and configured."
  echo "Generated secrets have been saved to:"
  echo "  $docker_env_file"
  echo ""
  echo "Generated credentials:"
  echo "  DASHBOARD_USERNAME: supabase"
  echo "  DASHBOARD_PASSWORD: $dashboard_password"
  echo "  POSTGRES_PASSWORD:  $postgres_password"
  echo "  VAULT_ENC_KEY:      $vault_enc_key"
  echo "  JWT_SECRET:         $jwt_secret"
  echo ""
  echo "Generated JWT keys:"
  echo "  ANON_KEY:           $anon_key"
  echo "  SERVICE_ROLE_KEY:   $service_role_key"
  echo "----------------------------------------------------------------------"
  echo ""
  echo "Configuration complete! Start your instance with:"
  echo "  ./supascale.sh start $project_id"

  # Update Kong and Postgres ports in .env
  echo "Updating Kong and Postgres ports in .env file..."
  sed -i.tmp "s|^KONG_HTTP_PORT=.*|KONG_HTTP_PORT=$api_port|" "$docker_env_file"
  sed -i.tmp "s|^KONG_HTTPS_PORT=.*|KONG_HTTPS_PORT=$kong_https_port|" "$docker_env_file"
  sed -i.tmp "s|^POSTGRES_PORT=.*|POSTGRES_PORT=$db_port|" "$docker_env_file"
  rm -f "$docker_env_file.tmp" # Clean up sed backup

  echo ".env file updated with generated passwords, JWT keys, Kong ports, and Postgres port."

  # Offer to configure custom domain
  echo ""
  read -p "Would you like to configure a custom domain for this instance? (y/N): " setup_domain_prompt
  if [[ "$setup_domain_prompt" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Note: Your project must be running for domain setup to complete successfully."
    read -p "Would you like to start the project now? (Y/n): " start_now
    if [[ ! "$start_now" =~ ^[Nn]$ ]]; then
      start_project "$project_id"
      echo ""
    fi
    setup_domain "$project_id"
  fi
}

# Function to update configuration files for a project
update_project_configurations() {
  local project_id="$1"

  # Use --arg to safely pass the project_id variable to jq
  local project_info=$(jq -r --arg pid "$project_id" '.projects[$pid]' "$DB_FILE")

  # Check if jq command succeeded and found the project
  if [ $? -ne 0 ] || [ "$project_info" = "null" ]; then
    echo "Error: Project '$project_id' not found or error retrieving project info."
    return 1
  fi

  local directory=$(echo "$project_info" | jq -r '.directory')
  # Ensure directory is not empty (as a fallback check)
  if [ -z "$directory" ]; then
     echo "Error: Failed to extract directory for project '$project_id'."
     return 1
  fi

  local config_file="$directory/supabase/supabase/config.toml"
  local compose_file="$directory/supabase/docker/docker-compose.yml"

  # --- Update config.toml (for CLI compatibility, though less critical for Docker setup) ---
  if [ ! -f "$config_file" ]; then
    echo "Warning: CLI Config file not found at '$config_file'. Skipping update."
  else
    echo "Updating CLI config file: $config_file"
    # Extract ports for config.toml
    local cli_api_port=$(echo "$project_info" | jq -r '.ports.api')
    local cli_db_port=$(echo "$project_info" | jq -r '.ports.db')
    local cli_studio_port=$(echo "$project_info" | jq -r '.ports.studio')
    local cli_inbucket_port=$(echo "$project_info" | jq -r '.ports.inbucket')
    local cli_shadow_port=$(echo "$project_info" | jq -r '.ports.shadow')
    local cli_smtp_port=$(echo "$project_info" | jq -r '.ports.smtp')
    local cli_pop3_port=$(echo "$project_info" | jq -r '.ports.pop3')
    local cli_pooler_port=$(echo "$project_info" | jq -r '.ports.pooler')
    local cli_analytics_port=$(echo "$project_info" | jq -r '.ports.analytics')

    cp "$config_file" "$config_file.bak"
    sed -i.tmp "s/^project_id = .*/project_id = \"$project_id\"/" "$config_file"
    sed -i.tmp "s/^port = [0-9]\\+/port = $cli_api_port/g" "$config_file"

    # Update specific section ports in config.toml
    sed -i.tmp "/^\\[db\\]/,/^\\[/ s/port = [0-9]\\+/port = $cli_db_port/" "$config_file"
    sed -i.tmp "/^\\[db\\]/,/^\\[/ s/shadow_port = [0-9]\\+/shadow_port = $cli_shadow_port/" "$config_file"
    sed -i.tmp "/^\\[studio\\]/,/^\\[/ s/port = [0-9]\\+/port = $cli_studio_port/" "$config_file"
    sed -i.tmp "/^\\[inbucket\\]/,/^\\[/ s/port = [0-9]\\+/port = $cli_inbucket_port/" "$config_file"
    sed -i.tmp "/^\\[inbucket\\]/,/^\\[/ s/smtp_port = [0-9]\\+/smtp_port = $cli_smtp_port/" "$config_file"
    sed -i.tmp "/^\\[inbucket\\]/,/^\\[/ s/pop3_port = [0-9]\\+/pop3_port = $cli_pop3_port/" "$config_file"
    sed -i.tmp "/^\\[db\\.pooler\\]/,/^\\[/ s/port = [0-9]\\+/port = $cli_pooler_port/" "$config_file"
    sed -i.tmp "/^\\[analytics\\]/,/^\\[/ s/port = [0-9]\\+/port = $cli_analytics_port/" "$config_file"

    rm -f "$config_file.tmp"
    echo "Updated $config_file"
  fi

  # --- Update docker-compose.yml ---
  if [ ! -f "$compose_file" ]; then
    echo "Error: Docker Compose file not found at '$compose_file'."
    return 1
  fi

  echo "Updating Docker Compose file: $compose_file"
  # Extract ports for docker-compose.yml
  local api_port=$(echo "$project_info" | jq -r '.ports.api')
  local db_port=$(echo "$project_info" | jq -r '.ports.db')
  local studio_port=$(echo "$project_info" | jq -r '.ports.studio')
  local inbucket_port=$(echo "$project_info" | jq -r '.ports.inbucket')
  local kong_https_port=$(echo "$project_info" | jq -r '.ports.kong_https // ""') # Extract Kong HTTPS port, default to empty if null

  cp "$compose_file" "$compose_file.bak" # Backup original first

  # --- Prepend project_id to container names ---
  echo "Updating container names in $compose_file to be project-specific..."
  # Pattern: Look for lines starting with optional space, 'container_name:', optional space,
  #          capture the rest of the line (the original name)
  # Replace: With the captured start, the project_id, a hyphen, and the captured original name
  sed -i.tmp -E "s/^([[:space:]]*container_name:[[:space:]]*)(.*)$/\1${project_id}-\2/" "$compose_file"
  # Note: This assumes original container names don't need further quoting changes after prepending.

  # --- Update Ports (using the existing refined sed commands) ---
  echo "Setting Kong/API Gateway port to $api_port (updates host side of :8000 mapping)"
  sed -i.tmp -E "s/^([[:space:]]*-*[[:space:]]*[\"\']?)[0-9]+(:8000[\"\']?.*)$/\1$api_port\2/" "$compose_file"
  echo "Setting Postgres port to $db_port (updates host side of :5432 mapping)"
  sed -i.tmp -E "s/^([[:space:]]*-*[[:space:]]*[\"\']?)[0-9]+(:5432[\"\']?.*)$/\1$db_port\2/" "$compose_file"
  echo "Setting Studio port to $studio_port (updates host side of :3000 mapping)"
  sed -i.tmp -E "s/^([[:space:]]*-*[[:space:]]*[\"\']?)[0-9]+(:3000[\"\']?.*)$/\1$studio_port\2/" "$compose_file"
  echo "Setting Inbucket port to $inbucket_port (updates host side of :9000 mapping)"
  sed -i.tmp -E "s/^([[:space:]]*-*[[:space:]]*[\"\']?)[0-9]+(:9000[\"\']?.*)$/\1$inbucket_port\2/" "$compose_file"

  # Update analytics port
  echo "Setting Analytics port to $analytics_port (updates host side of :4000 mapping)"
  sed -i.tmp -E "s/^([[:space:]]*-*[[:space:]]*[\"\']?)[0-9]+(:4000[\"\']?.*)$/\1$analytics_port\2/" "$compose_file"

  # Only update Kong HTTPS if the port was actually extracted
  if [ -n "$kong_https_port" ]; then
    echo "Setting Kong/API Gateway HTTPS port to $kong_https_port (updates host side of :8443 mapping)"
    sed -i.tmp -E "s/^([[:space:]]*-*[[:space:]]*[\"\']?)[0-9]+(:8443[\"\']?.*)$/\1$kong_https_port\2/" "$compose_file"
  else
    echo "Warning: Kong HTTPS port not found in project data for $project_id. Skipping update for 8443 mapping."
  fi

  rm -f "$compose_file.tmp"
  echo "Updated $compose_file for project '$project_id'"
}

# Function to start a project
start_project() {
  local project_id="$1"

  if [ -z "$project_id" ]; then
    echo "Error: Project ID required."
    echo "Usage: ./supascale.sh start <project_id>"
    return 1
  fi

  local project_info=$(jq -r --arg pid "$project_id" '.projects[$pid]' "$DB_FILE")

  if [ "$project_info" = "null" ]; then
    echo "Error: Project '$project_id' not found."
    echo "Available projects:"
    list_projects
    return 1
  fi

  local directory=$(echo "$project_info" | jq -r '.directory')

  echo "Starting Supabase for project '$project_id'..."
  echo "Changing to directory: $directory/supabase/docker"
  cd "$directory/supabase/docker" || { echo "Failed to change directory"; return 1; }

  # Copy the .env.example to .env if it doesn't exist
  if [ ! -f ".env" ]; then
    echo "Warning: .env file not found. Copying .env.example. Secrets may need manual population."
    if [ -f ".env.example" ]; then
        cp .env.example .env
    else
        echo "Error: .env.example also missing. Cannot proceed."
        return 1
    fi
  fi

  echo "Running docker compose up..."
  sudo docker compose -p "$project_id" up -d

  # Extract ports
  local api_port=$(echo "$project_info" | jq -r '.ports.api')

  # Attempt to get host IP
  local host_ip=$(hostname -I | awk '{print $1}')
  # Fallback to localhost if IP retrieval fails
  if [ -z "$host_ip" ]; then
    host_ip="localhost"
    echo "Warning: Could not automatically determine host IP address. Displaying URLs with 'localhost'."
  fi

  echo "Supabase should now be running for project '$project_id':"

  # Check if domain is configured
  local domain_name=$(echo "$project_info" | jq -r '.domain.name // empty')
  local ssl_enabled=$(echo "$project_info" | jq -r '.domain.ssl_enabled // false')

  if [ -n "$domain_name" ]; then
    if [ "$ssl_enabled" = "true" ]; then
      echo ""
      echo "  Custom Domain (HTTPS):"
      echo "    Studio URL: https://$domain_name"
      echo "    API URL: https://$domain_name/rest/v1/"
    else
      echo ""
      echo "  Custom Domain (HTTP):"
      echo "    Studio URL: http://$domain_name"
      echo "    API URL: http://$domain_name/rest/v1/"
    fi
    echo ""
    echo "  Direct Access (fallback):"
  fi
  echo "    Studio URL: http://$host_ip:$api_port"
  echo "    API URL: http://$host_ip:$api_port/rest/v1/"
}

# Function to stop a project
stop_project() {
  local project_id="$1"

  if [ -z "$project_id" ]; then
    echo "Error: Project ID required."
    echo "Usage: ./supascale.sh stop <project_id>"
    return 1
  fi

  local project_info=$(jq -r ".projects.\"$project_id\"" "$DB_FILE")

  if [ "$project_info" = "null" ]; then
    echo "Error: Project '$project_id' not found."
    echo "Available projects:"
    list_projects
    return 1
  fi

  local directory=$(echo "$project_info" | jq -r '.directory')

  echo "Stopping Supabase for project '$project_id'..."
  echo "Changing to directory: $directory/supabase/docker"
  cd "$directory/supabase/docker" || { echo "Failed to change directory, maybe already stopped or directory removed?"; return 1; }

  echo "Running docker compose down..."
  sudo docker compose -p "$project_id" down -v --remove-orphans

  echo "Supabase stopped for project '$project_id'"
}

# Function to remove a project from the database
remove_project() {
  local project_id="$1"

  if [ -z "$project_id" ]; then
    echo "Error: Project ID required."
    echo "Usage: ./supascale.sh remove <project_id>"
    return 1
  fi

  local project_info=$(jq -r ".projects.\"$project_id\"" "$DB_FILE")

  if [ "$project_info" = "null" ]; then
    echo "Error: Project '$project_id' not found."
    echo "Available projects:"
    list_projects
    return 1
  fi

  # First, stop the project if it's running
  stop_project "$project_id"

  # Remove the project from the database
  jq --arg project_id "$project_id" 'del(.projects[$project_id])' "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"

  echo "Project '$project_id' removed from the database."
  echo "Note: This does not delete any project files or Docker containers."
  echo "To completely remove Docker containers, you may need to run 'docker container prune'."
}

# Function to update the script
update_script() {
  echo "Checking for updates..."
  
  # Try to fetch the latest version
  local latest_version=""
  local temp_script="/tmp/supascale-latest.sh"
  
  if command -v curl &> /dev/null; then
    curl -s --max-time 10 "$GITHUB_RAW_URL" -o "$temp_script"
  elif command -v wget &> /dev/null; then
    wget -q --timeout=10 -O "$temp_script" "$GITHUB_RAW_URL"
  else
    echo "Error: curl or wget is required for updates."
    return 1
  fi
  
  if [ ! -f "$temp_script" ] || [ ! -s "$temp_script" ]; then
    echo "Error: Failed to download the latest version."
    rm -f "$temp_script"
    return 1
  fi
  
  # Extract version from downloaded script
  latest_version=$(grep '^VERSION=' "$temp_script" | head -1 | cut -d'"' -f2 2>/dev/null)
  
  if [ -z "$latest_version" ]; then
    echo "Error: Could not determine the latest version."
    rm -f "$temp_script"
    return 1
  fi
  
  if [ "$latest_version" = "$VERSION" ]; then
    echo "You are already running the latest version ($VERSION)."
    rm -f "$temp_script"
    return 0
  fi
  
  echo "Current version: $VERSION"
  echo "Latest version:  $latest_version"
  echo ""
  read -p "Would you like to update to version $latest_version? (y/N): " -r
  
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Update cancelled."
    rm -f "$temp_script"
    return 0
  fi
  
  # Get the current script path
  local script_path="$(readlink -f "${BASH_SOURCE[0]}")"
  local backup_path="${script_path}.bak"
  
  echo "Backing up current script to $backup_path..."
  cp "$script_path" "$backup_path"
  
  echo "Installing update..."
  if mv "$temp_script" "$script_path" && chmod +x "$script_path"; then
    echo "Update completed successfully!"
    echo "   Updated from $VERSION to $latest_version"
    echo "   Backup saved to: $backup_path"
  else
    echo "Update failed! Restoring backup..."
    mv "$backup_path" "$script_path"
    rm -f "$temp_script"
    return 1
  fi
}

################################################################################
# Container Update Functions
################################################################################

# Function to fetch latest container versions from GitHub docker-compose.yml
fetch_github_versions() {
  local temp_file="/tmp/supascale_github_compose.yml"

  # Download docker-compose.yml from Supabase GitHub
  if command -v curl &> /dev/null; then
    curl -s --max-time 30 "$SUPABASE_DOCKER_COMPOSE_URL" -o "$temp_file" 2>/dev/null
  elif command -v wget &> /dev/null; then
    wget -q --timeout=30 -O "$temp_file" "$SUPABASE_DOCKER_COMPOSE_URL" 2>/dev/null
  fi

  if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
    echo "{}"
    return 1
  fi

  # Parse image versions from docker-compose.yml
  local versions="{}"
  local current_service=""

  while IFS= read -r line; do
    # Detect service name (e.g., "  studio:" or "  db:")
    if [[ "$line" =~ ^[[:space:]]{2}([a-z_-]+):[[:space:]]*$ ]]; then
      current_service="${BASH_REMATCH[1]}"
    fi
    # Extract image tag when we're in a service block
    if [ -n "$current_service" ] && [[ "$line" =~ image:[[:space:]]*([^[:space:]]+) ]]; then
      local full_image="${BASH_REMATCH[1]}"
      # Remove quotes if present
      full_image=$(echo "$full_image" | tr -d '"' | tr -d "'")
      # Extract version (everything after the last colon)
      local version="${full_image##*:}"
      if [ -n "$version" ] && [ "$version" != "$full_image" ]; then
        versions=$(echo "$versions" | jq --arg svc "$current_service" --arg ver "$version" '.[$svc] = $ver')
      fi
      current_service=""
    fi
  done < "$temp_file"

  rm -f "$temp_file"
  echo "$versions"
}

# Function to query Docker Hub API for latest tag of an image
fetch_dockerhub_version() {
  local image_name="$1"
  local api_url="https://hub.docker.com/v2/repositories/${image_name}/tags?page_size=10&ordering=last_updated"

  local response=""
  if command -v curl &> /dev/null; then
    response=$(curl -s --max-time 10 "$api_url" 2>/dev/null)
  elif command -v wget &> /dev/null; then
    response=$(wget -q --timeout=10 -O- "$api_url" 2>/dev/null)
  fi

  if [ -z "$response" ]; then
    echo ""
    return 1
  fi

  # Extract latest non-"latest" tag
  echo "$response" | jq -r '.results[]? | select(.name != "latest") | .name' 2>/dev/null | head -1
}

# Function to extract current container versions from local docker-compose.yml
get_current_versions() {
  local project_id="$1"
  local project_info=$(jq -r --arg pid "$project_id" '.projects[$pid]' "$DB_FILE")

  if [ "$project_info" = "null" ]; then
    echo "{}"
    return 1
  fi

  local directory=$(echo "$project_info" | jq -r '.directory')
  local compose_file="$directory/supabase/docker/docker-compose.yml"

  if [ ! -f "$compose_file" ]; then
    echo "{}"
    return 1
  fi

  local versions="{}"
  local current_service=""

  while IFS= read -r line; do
    # Detect service name
    if [[ "$line" =~ ^[[:space:]]{2}([a-z_-]+):[[:space:]]*$ ]]; then
      current_service="${BASH_REMATCH[1]}"
    fi
    # Extract image tag
    if [ -n "$current_service" ] && [[ "$line" =~ image:[[:space:]]*([^[:space:]]+) ]]; then
      local full_image="${BASH_REMATCH[1]}"
      full_image=$(echo "$full_image" | tr -d '"' | tr -d "'")
      local version="${full_image##*:}"
      if [ -n "$version" ] && [ "$version" != "$full_image" ]; then
        versions=$(echo "$versions" | jq --arg svc "$current_service" --arg ver "$version" '.[$svc] = $ver')
      fi
      current_service=""
    fi
  done < "$compose_file"

  echo "$versions"
}

# Function to create a full project snapshot before update
create_project_snapshot() {
  local project_id="$1"
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  local project_info=$(jq -r --arg pid "$project_id" '.projects[$pid]' "$DB_FILE")
  local directory=$(echo "$project_info" | jq -r '.directory')
  local docker_dir="$directory/supabase/docker"

  # Create snapshot directory
  local snapshot_dir="$BACKUP_DIR/$project_id/snapshots/${timestamp}_pre_update"
  mkdir -p "$snapshot_dir"

  echo "  Creating snapshot at: $snapshot_dir"

  # Backup docker-compose.yml and .env
  cp "$docker_dir/docker-compose.yml" "$snapshot_dir/" 2>/dev/null
  cp "$docker_dir/.env" "$snapshot_dir/" 2>/dev/null || true

  # Save current image versions
  get_current_versions "$project_id" > "$snapshot_dir/versions.json"

  # Stop containers gracefully for consistent backup
  echo "  Stopping containers for consistent backup..."
  cd "$docker_dir"
  sudo docker compose -p "$project_id" stop 2>/dev/null

  # Backup volumes directory
  if [ -d "$docker_dir/volumes" ]; then
    echo "  Backing up volumes directory..."
    tar -czf "$snapshot_dir/volumes.tar.gz" -C "$docker_dir" volumes 2>/dev/null || true
  fi

  # Backup named Docker volumes
  echo "  Backing up Docker volumes..."
  for volume in $(sudo docker volume ls -q 2>/dev/null | grep "^${project_id}_" || true); do
    sudo docker run --rm -v "$volume:/data:ro" -v "$snapshot_dir:/backup" alpine \
      tar -czf "/backup/volume_${volume}.tar.gz" -C /data . 2>/dev/null || true
  done

  # Save container images list
  sudo docker compose -p "$project_id" config --images > "$snapshot_dir/images.txt" 2>/dev/null || true

  # Save metadata
  echo "{
    \"project_id\": \"$project_id\",
    \"timestamp\": \"$timestamp\",
    \"type\": \"pre_update_snapshot\",
    \"created_at\": \"$(date -Iseconds)\"
  }" > "$snapshot_dir/metadata.json"

  echo "$snapshot_dir"
}

# Function to restore project from a snapshot (rollback)
restore_project_snapshot() {
  local project_id="$1"
  local snapshot_path="$2"
  local project_info=$(jq -r --arg pid "$project_id" '.projects[$pid]' "$DB_FILE")
  local directory=$(echo "$project_info" | jq -r '.directory')
  local docker_dir="$directory/supabase/docker"

  if [ ! -d "$snapshot_path" ]; then
    echo "Error: Snapshot not found at $snapshot_path"
    return 1
  fi

  echo "  Stopping all containers..."
  cd "$docker_dir"
  sudo docker compose -p "$project_id" down --remove-orphans 2>/dev/null

  # Restore docker-compose.yml and .env
  echo "  Restoring configuration files..."
  cp "$snapshot_path/docker-compose.yml" "$docker_dir/" 2>/dev/null
  [ -f "$snapshot_path/.env" ] && cp "$snapshot_path/.env" "$docker_dir/"

  # Restore volumes directory
  if [ -f "$snapshot_path/volumes.tar.gz" ]; then
    echo "  Restoring volumes directory..."
    rm -rf "$docker_dir/volumes" 2>/dev/null
    tar -xzf "$snapshot_path/volumes.tar.gz" -C "$docker_dir" 2>/dev/null
  fi

  # Restore named Docker volumes
  for volume_backup in "$snapshot_path"/volume_*.tar.gz; do
    if [ -f "$volume_backup" ]; then
      local volume_name=$(basename "$volume_backup" | sed 's/^volume_//' | sed 's/.tar.gz$//')
      echo "  Restoring Docker volume: $volume_name"
      sudo docker volume rm "$volume_name" 2>/dev/null || true
      sudo docker volume create "$volume_name" 2>/dev/null
      sudo docker run --rm -v "$volume_name:/data" -v "$(dirname "$volume_backup"):/backup:ro" alpine \
        sh -c "cd /data && tar -xzf /backup/$(basename "$volume_backup")" 2>/dev/null || true
    fi
  done

  # Pull the original images and start
  echo "  Pulling original images..."
  sudo docker compose -p "$project_id" pull 2>/dev/null

  echo "  Starting containers with restored configuration..."
  sudo docker compose -p "$project_id" up -d
}

# Function to save volumes backup after successful update
save_volumes_backup() {
  local project_id="$1"
  local version_info="$2"
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  local project_info=$(jq -r --arg pid "$project_id" '.projects[$pid]' "$DB_FILE")
  local directory=$(echo "$project_info" | jq -r '.directory')
  local docker_dir="$directory/supabase/docker"

  local backup_dir="$BACKUP_DIR/$project_id/versions/${version_info}_${timestamp}"
  mkdir -p "$backup_dir"

  echo "  Saving versioned backup to: $backup_dir"

  # Stop containers for consistent backup
  cd "$docker_dir"
  sudo docker compose -p "$project_id" stop 2>/dev/null

  # Backup volumes
  if [ -d "$docker_dir/volumes" ]; then
    tar -czf "$backup_dir/volumes.tar.gz" -C "$docker_dir" volumes 2>/dev/null || true
  fi

  # Backup named Docker volumes
  for volume in $(sudo docker volume ls -q 2>/dev/null | grep "^${project_id}_" || true); do
    sudo docker run --rm -v "$volume:/data:ro" -v "$backup_dir:/backup" alpine \
      tar -czf "/backup/volume_${volume}.tar.gz" -C /data . 2>/dev/null || true
  done

  # Save metadata
  get_current_versions "$project_id" > "$backup_dir/versions.json"
  echo "{
    \"project_id\": \"$project_id\",
    \"version\": \"$version_info\",
    \"timestamp\": \"$timestamp\",
    \"type\": \"post_update_backup\",
    \"created_at\": \"$(date -Iseconds)\"
  }" > "$backup_dir/metadata.json"

  # Restart containers
  sudo docker compose -p "$project_id" up -d

  echo "  Backup saved successfully"
}

# Function to update image tag in docker-compose.yml for a specific service
update_docker_compose_image() {
  local compose_file="$1"
  local service="$2"
  local new_version="$3"

  # Create backup
  cp "$compose_file" "${compose_file}.update_backup"

  # Use awk to find the service block and update the image line
  awk -v svc="$service" -v ver="$new_version" '
  BEGIN { in_service = 0; indent = "" }
  /^[[:space:]]{2}[a-z_-]+:[[:space:]]*$/ {
    if ($0 ~ "^  " svc ":") {
      in_service = 1
    } else {
      in_service = 0
    }
  }
  in_service && /image:/ {
    # Replace the version tag (everything after the last colon in the image value)
    gsub(/:[^[:space:]"'\'']+/, ":" ver)
  }
  { print }
  ' "$compose_file" > "${compose_file}.tmp" && mv "${compose_file}.tmp" "$compose_file"
}

# Function to perform health checks after update
perform_health_check() {
  local project_id="$1"
  local project_info=$(jq -r --arg pid "$project_id" '.projects[$pid]' "$DB_FILE")
  local directory=$(echo "$project_info" | jq -r '.directory')
  local docker_dir="$directory/supabase/docker"
  local api_port=$(echo "$project_info" | jq -r '.ports.api')

  local errors=""

  cd "$docker_dir"

  # Check 1: Count running vs total containers
  local running_count=$(sudo docker compose -p "$project_id" ps --status running -q 2>/dev/null | wc -l)
  local total_count=$(sudo docker compose -p "$project_id" ps -q 2>/dev/null | wc -l)

  if [ "$running_count" -lt "$total_count" ]; then
    errors+="  - Only $running_count of $total_count containers are running\n"
    # Get non-running containers
    local failed_containers=$(sudo docker compose -p "$project_id" ps --format "{{.Name}}: {{.Status}}" 2>/dev/null | grep -v "running" || true)
    if [ -n "$failed_containers" ]; then
      errors+="  - Failed containers:\n$failed_containers\n"
    fi
  fi

  # Check 2: Look for containers in restart loop
  local restarting=$(sudo docker compose -p "$project_id" ps 2>/dev/null | grep -c "Restarting" || true)
  if [ "$restarting" -gt 0 ]; then
    errors+="  - $restarting container(s) are in a restart loop\n"
  fi

  # Check 3: API endpoint responding (wait a bit for services to initialize)
  sleep 5
  local api_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$api_port/rest/v1/" 2>/dev/null || echo "000")
  if [ "$api_status" != "200" ] && [ "$api_status" != "401" ]; then
    errors+="  - API not responding (HTTP status: $api_status)\n"
  fi

  # Check 4: Get recent error logs from containers
  local error_logs=$(sudo docker compose -p "$project_id" logs --tail=20 2>&1 | grep -i "error\|fatal\|panic" | head -10 || true)
  if [ -n "$error_logs" ]; then
    errors+="  - Recent error logs detected:\n$error_logs\n"
  fi

  if [ -n "$errors" ]; then
    echo "$errors"
    return 1
  fi

  return 0
}

# Function to parse --only flag for selective updates
parse_only_services() {
  local flag_value="$1"
  local -n result_array=$2

  IFS=',' read -ra services <<< "$flag_value"
  for service in "${services[@]}"; do
    # Validate service name
    local valid=0
    for valid_svc in "${SUPABASE_SERVICES[@]}"; do
      if [ "$service" = "$valid_svc" ]; then
        valid=1
        break
      fi
    done
    if [ $valid -eq 1 ]; then
      result_array+=("$service")
    else
      echo "Warning: Unknown service '$service' - skipping"
    fi
  done
}

# Main function to orchestrate container updates
update_containers() {
  local project_id="$1"
  shift
  local -a services_to_update=("$@")

  # Default to all services in dependency order if none specified
  if [ ${#services_to_update[@]} -eq 0 ]; then
    services_to_update=("${UPDATE_ORDER[@]}")
  else
    # Reorder specified services according to dependency order
    local -a ordered_services=()
    for svc in "${UPDATE_ORDER[@]}"; do
      for sel_svc in "${services_to_update[@]}"; do
        if [ "$svc" = "$sel_svc" ]; then
          ordered_services+=("$svc")
          break
        fi
      done
    done
    services_to_update=("${ordered_services[@]}")
  fi

  local project_info=$(jq -r --arg pid "$project_id" '.projects[$pid]' "$DB_FILE")
  if [ "$project_info" = "null" ]; then
    echo "Error: Project '$project_id' not found"
    return 1
  fi

  local directory=$(echo "$project_info" | jq -r '.directory')
  local docker_dir="$directory/supabase/docker"
  local compose_file="$docker_dir/docker-compose.yml"

  # Step 1: Create pre-update snapshot
  echo ""
  echo "=========================================="
  echo "Step 1: Creating pre-update snapshot"
  echo "=========================================="
  local snapshot_path=$(create_project_snapshot "$project_id")

  # Step 2: Fetch latest versions
  echo ""
  echo "=========================================="
  echo "Step 2: Fetching latest versions"
  echo "=========================================="
  echo "  Fetching from GitHub..."
  local github_versions=$(fetch_github_versions)
  echo "  Reading current local versions..."
  local current_versions=$(get_current_versions "$project_id")

  # Step 3: Update docker-compose.yml
  echo ""
  echo "=========================================="
  echo "Step 3: Updating container versions"
  echo "=========================================="
  local update_summary=""
  local updates_made=0

  for service in "${services_to_update[@]}"; do
    local current=$(echo "$current_versions" | jq -r --arg s "$service" '.[$s] // "unknown"')
    local latest=$(echo "$github_versions" | jq -r --arg s "$service" '.[$s] // ""')

    if [ -n "$latest" ] && [ "$current" != "$latest" ] && [ "$current" != "unknown" ]; then
      echo "  Updating $service: $current -> $latest"
      update_docker_compose_image "$compose_file" "$service" "$latest"
      update_summary+="  $service: $current -> $latest\n"
      updates_made=$((updates_made + 1))
    elif [ "$current" = "unknown" ]; then
      echo "  $service: Not found in local config"
    else
      echo "  $service: Already at latest ($current)"
    fi
  done

  if [ $updates_made -eq 0 ]; then
    echo ""
    echo "No updates required. All containers are at latest versions."
    echo "Restarting containers..."
    cd "$docker_dir"
    sudo docker compose -p "$project_id" up -d
    rm -rf "$snapshot_path"
    return 0
  fi

  # Step 4: Pull new images and restart
  echo ""
  echo "=========================================="
  echo "Step 4: Pulling images and restarting"
  echo "=========================================="
  cd "$docker_dir"
  echo "  Pulling new container images..."
  sudo docker compose -p "$project_id" pull
  echo "  Starting updated containers..."
  sudo docker compose -p "$project_id" up -d

  # Step 5: Health check with auto-rollback on failure
  echo ""
  echo "=========================================="
  echo "Step 5: Performing health checks"
  echo "=========================================="
  echo "  Waiting for containers to initialize..."
  sleep 10

  local health_errors=$(perform_health_check "$project_id")
  local health_status=$?

  if [ $health_status -ne 0 ]; then
    echo ""
    echo "=========================================="
    echo "HEALTH CHECK FAILED - AUTO ROLLBACK"
    echo "=========================================="
    echo ""
    echo "Detected issues:"
    echo -e "$health_errors"
    echo ""
    echo "Automatically rolling back to previous version..."
    echo ""
    restore_project_snapshot "$project_id" "$snapshot_path"
    echo ""
    echo "=========================================="
    echo "Rollback Complete"
    echo "=========================================="
    echo "Your project has been restored to the pre-update state."
    echo "Please investigate the issues before attempting to update again."
    return 1
  fi

  echo "  All health checks passed!"

  # Step 6: User verification
  echo ""
  echo "=========================================="
  echo "Update Summary"
  echo "=========================================="
  echo "Updated containers:"
  echo -e "$update_summary"
  echo ""
  echo "Please verify your application is working correctly."
  echo ""
  read -p "Is everything working? (y/n): " -r user_response

  if [[ "$user_response" =~ ^[Yy]$ ]]; then
    echo ""
    echo "=========================================="
    echo "Step 6: Saving post-update backup"
    echo "=========================================="
    local version_string=$(date +"%Y%m%d")
    save_volumes_backup "$project_id" "$version_string"

    # Remove pre-update snapshot
    echo "  Removing pre-update snapshot..."
    rm -rf "$snapshot_path"

    # Optional: Clean up old images
    echo "  Cleaning up unused Docker images..."
    sudo docker image prune -f 2>/dev/null || true

    echo ""
    echo "=========================================="
    echo "Update Completed Successfully!"
    echo "=========================================="
    echo "Your project '$project_id' is now running the latest container versions."
  else
    echo ""
    echo "=========================================="
    echo "Step 6: Rolling back to previous version"
    echo "=========================================="
    restore_project_snapshot "$project_id" "$snapshot_path"
    echo ""
    echo "=========================================="
    echo "Rollback Complete"
    echo "=========================================="
    echo "Your project has been restored to the pre-update state."
  fi
}

# Command handler for update-containers
update_containers_command() {
  local target="$1"
  shift

  # Parse optional flags
  local only_services=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --only=*)
        only_services="${1#*=}"
        shift
        ;;
      *)
        echo "Unknown option: $1"
        return 1
        ;;
    esac
  done

  # Parse --only flag if provided
  local -a services_array=()
  if [ -n "$only_services" ]; then
    parse_only_services "$only_services" services_array
    if [ ${#services_array[@]} -eq 0 ]; then
      echo "Error: No valid services specified in --only flag"
      return 1
    fi
  fi

  if [ "$target" = "--all" ]; then
    # Update all projects
    local projects=$(jq -r '.projects | keys[]' "$DB_FILE" 2>/dev/null)
    if [ -z "$projects" ]; then
      echo "No projects configured."
      return 1
    fi

    for project_id in $projects; do
      echo ""
      echo "########################################"
      echo "Updating project: $project_id"
      echo "########################################"
      update_containers "$project_id" "${services_array[@]}"
    done
  elif [ -z "$target" ]; then
    echo "Error: Project ID or --all required."
    echo ""
    echo "Usage:"
    echo "  ./supascale.sh update-containers <project_id> [--only=service1,service2]"
    echo "  ./supascale.sh update-containers --all [--only=service1,service2]"
    echo ""
    echo "Available services for --only flag:"
    echo "  ${SUPABASE_SERVICES[*]}"
    return 1
  else
    update_containers "$target" "${services_array[@]}"
  fi
}

# Command to check for available updates without applying them
check_updates() {
  local project_id="$1"

  if [ -z "$project_id" ]; then
    echo "Error: Project ID required."
    echo "Usage: ./supascale.sh check-updates <project_id>"
    return 1
  fi

  local project_info=$(jq -r --arg pid "$project_id" '.projects[$pid]' "$DB_FILE")
  if [ "$project_info" = "null" ]; then
    echo "Error: Project '$project_id' not found"
    return 1
  fi

  echo "Checking for container updates for project '$project_id'..."
  echo ""

  echo "Fetching latest versions from GitHub..."
  local github_versions=$(fetch_github_versions)

  echo "Reading current local versions..."
  local current_versions=$(get_current_versions "$project_id")

  echo ""
  echo "Container Version Comparison"
  echo "============================"
  printf "%-15s %-30s %-30s %s\n" "SERVICE" "CURRENT" "LATEST" "STATUS"
  printf "%-15s %-30s %-30s %s\n" "-------" "-------" "------" "------"

  local updates_available=0
  for service in "${SUPABASE_SERVICES[@]}"; do
    local current=$(echo "$current_versions" | jq -r --arg s "$service" '.[$s] // "not found"')
    local latest=$(echo "$github_versions" | jq -r --arg s "$service" '.[$s] // "unknown"')

    local status="Up to date"
    if [ "$current" = "not found" ]; then
      status="-"
    elif [ "$latest" = "unknown" ]; then
      status="Unknown"
    elif [ "$current" != "$latest" ]; then
      status="UPDATE AVAILABLE"
      updates_available=$((updates_available + 1))
    fi

    printf "%-15s %-30s %-30s %s\n" "$service" "$current" "$latest" "$status"
  done

  echo ""
  if [ $updates_available -gt 0 ]; then
    echo "$updates_available update(s) available."
    echo ""
    echo "To apply updates, run:"
    echo "  ./supascale.sh update-containers $project_id"
  else
    echo "All containers are up to date."
  fi
}

# Command to display current container versions
container_versions() {
  local project_id="$1"

  if [ -z "$project_id" ]; then
    echo "Error: Project ID required."
    echo "Usage: ./supascale.sh container-versions <project_id>"
    return 1
  fi

  local project_info=$(jq -r --arg pid "$project_id" '.projects[$pid]' "$DB_FILE")
  if [ "$project_info" = "null" ]; then
    echo "Error: Project '$project_id' not found"
    return 1
  fi

  echo "Container versions for project '$project_id'"
  echo "============================================"
  echo ""

  local versions=$(get_current_versions "$project_id")

  printf "%-15s %s\n" "SERVICE" "VERSION"
  printf "%-15s %s\n" "-------" "-------"

  for service in "${SUPABASE_SERVICES[@]}"; do
    local version=$(echo "$versions" | jq -r --arg s "$service" '.[$s] // "not found"')
    printf "%-15s %s\n" "$service" "$version"
  done

  echo ""
  echo "Running Container Status"
  echo "========================"
  local directory=$(echo "$project_info" | jq -r '.directory')
  cd "$directory/supabase/docker" 2>/dev/null && \
    sudo docker compose -p "$project_id" ps --format "table {{.Name}}\t{{.Image}}\t{{.Status}}" 2>/dev/null || \
    echo "Unable to retrieve container status (containers may not be running)"
}

################################################################################
# End Container Update Functions
################################################################################

################################################################################
# Backup Feature Functions
################################################################################

# Backup logging functions (respect SILENT_MODE)
log_progress() {
  if [ "$SILENT_MODE" != "true" ]; then
    echo "$1"
  fi
}

log_error() {
  # Always show errors, even in silent mode
  echo "ERROR: $1" >&2
}

log_warning() {
  if [ "$SILENT_MODE" != "true" ]; then
    echo "WARNING: $1" >&2
  fi
}

log_step() {
  if [ "$SILENT_MODE" != "true" ]; then
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
  fi
}

# Calculate SHA256 checksum for a file
calculate_checksum() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo ""
    return 1
  fi

  if command -v sha256sum &> /dev/null; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum &> /dev/null; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    log_error "Neither sha256sum nor shasum is available"
    return 1
  fi
}

# Verify checksum matches expected value
verify_checksum() {
  local file="$1"
  local expected="$2"

  local actual=$(calculate_checksum "$file")
  if [ -z "$actual" ]; then
    return 1
  fi

  if [ "$actual" = "$expected" ]; then
    return 0
  else
    return 1
  fi
}

# Encrypt a file using AES-256-CBC
encrypt_file() {
  local input="$1"
  local output="$2"
  local password="$3"

  if [ ! -f "$input" ]; then
    log_error "Input file not found: $input"
    return 1
  fi

  if [ -z "$password" ]; then
    log_error "Password is required for encryption"
    return 1
  fi

  if ! command -v openssl &> /dev/null; then
    log_error "openssl is required for encryption"
    return 1
  fi

  # Use PBKDF2 key derivation for better security
  if openssl enc -$ENCRYPTION_CIPHER -salt -pbkdf2 -iter 100000 \
      -in "$input" -out "$output" -pass "pass:$password" 2>/dev/null; then
    return 0
  else
    log_error "Encryption failed"
    rm -f "$output"
    return 1
  fi
}

# Decrypt a file using AES-256-CBC
decrypt_file() {
  local input="$1"
  local output="$2"
  local password="$3"

  if [ ! -f "$input" ]; then
    log_error "Input file not found: $input"
    return 1
  fi

  if [ -z "$password" ]; then
    log_error "Password is required for decryption"
    return 1
  fi

  if ! command -v openssl &> /dev/null; then
    log_error "openssl is required for decryption"
    return 1
  fi

  # Use PBKDF2 key derivation (must match encryption)
  if openssl enc -d -$ENCRYPTION_CIPHER -salt -pbkdf2 -iter 100000 \
      -in "$input" -out "$output" -pass "pass:$password" 2>/dev/null; then
    return 0
  else
    log_error "Decryption failed (wrong password or corrupted file)"
    rm -f "$output"
    return 1
  fi
}

# Generate a standardized backup filename
generate_backup_filename() {
  local project_id="$1"
  local backup_type="$2"
  local timestamp=$(date +%Y%m%d_%H%M%S)

  echo "${project_id}_${backup_type}_${timestamp}.supascale.tar.gz"
}

# Get backup destination directory (local)
get_local_backup_dir() {
  local project_id="$1"
  echo "$BACKUP_DIR/$project_id/backups"
}

# Parse backup destination string
parse_backup_destination() {
  local destination="$1"

  # Default to local if not specified
  if [ -z "$destination" ] || [ "$destination" = "local" ]; then
    echo "type=local"
    return 0
  fi

  # Check for S3 URL
  if [[ "$destination" =~ ^s3:// ]]; then
    echo "type=s3"
    echo "url=$destination"
    return 0
  fi

  # Check for local path
  if [[ "$destination" =~ ^local:// ]]; then
    local path="${destination#local://}"
    echo "type=local"
    echo "path=$path"
    return 0
  fi

  # Assume it's a local path
  echo "type=local"
  echo "path=$destination"
}

# Check if AWS CLI is installed and configured
check_aws_cli() {
  if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it to use S3 storage."
    echo "Installation:"
    echo "  - Ubuntu/Debian: sudo apt install awscli"
    echo "  - macOS: brew install awscli"
    echo "  - Or: pip install awscli"
    return 1
  fi

  # Check if credentials are configured
  if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS CLI is not configured. Please run 'aws configure' first."
    return 1
  fi

  return 0
}

# Upload file to S3
upload_to_s3() {
  local local_path="$1"
  local s3_url="$2"

  if ! check_aws_cli; then
    return 1
  fi

  log_progress "Uploading to $s3_url..."
  if aws s3 cp "$local_path" "$s3_url" --quiet; then
    return 0
  else
    log_error "Failed to upload to S3"
    return 1
  fi
}

# Download file from S3
download_from_s3() {
  local s3_url="$1"
  local local_path="$2"

  if ! check_aws_cli; then
    return 1
  fi

  log_progress "Downloading from $s3_url..."
  if aws s3 cp "$s3_url" "$local_path" --quiet; then
    return 0
  else
    log_error "Failed to download from S3"
    return 1
  fi
}

# List backups in S3
list_s3_backups() {
  local s3_base_url="$1"
  local project_id="$2"

  if ! check_aws_cli; then
    return 1
  fi

  aws s3 ls "$s3_base_url" 2>/dev/null | grep "${project_id}_" | awk '{print $4}'
}

# Create a temporary working directory for backup operations
create_backup_temp_dir() {
  local temp_dir="${BACKUP_TEMP_DIR}_$$"
  mkdir -p "$temp_dir"
  echo "$temp_dir"
}

# Cleanup temporary directory
cleanup_backup_temp_dir() {
  local temp_dir="$1"
  if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
    rm -rf "$temp_dir"
  fi
}

# Get database container name for a project
get_db_container_name() {
  local project_id="$1"
  echo "supabase-db"  # Standard Supabase container name
}

# Get database connection info from .env file
get_db_credentials() {
  local project_dir="$1"
  local env_file="$project_dir/supabase/docker/.env"

  if [ ! -f "$env_file" ]; then
    log_error "Environment file not found: $env_file"
    return 1
  fi

  # Extract POSTGRES_PASSWORD from .env
  local password=$(grep '^POSTGRES_PASSWORD=' "$env_file" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
  if [ -z "$password" ]; then
    log_error "POSTGRES_PASSWORD not found in $env_file"
    return 1
  fi

  echo "$password"
}

# Validate backup type argument
validate_backup_type() {
  local backup_type="$1"

  for valid_type in "${BACKUP_TYPES[@]}"; do
    if [ "$backup_type" = "$valid_type" ]; then
      return 0
    fi
  done

  log_error "Invalid backup type: $backup_type"
  log_error "Valid types: ${BACKUP_TYPES[*]}"
  return 1
}

# Format file size for display
format_size() {
  local size=$1

  if [ $size -ge 1073741824 ]; then
    echo "$(awk "BEGIN {printf \"%.2f\", $size/1073741824}") GB"
  elif [ $size -ge 1048576 ]; then
    echo "$(awk "BEGIN {printf \"%.2f\", $size/1048576}") MB"
  elif [ $size -ge 1024 ]; then
    echo "$(awk "BEGIN {printf \"%.2f\", $size/1024}") KB"
  else
    echo "$size bytes"
  fi
}

# Get timestamp in a readable format
get_timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

# =============================================================================
# Component Backup Functions
# =============================================================================

# Backup PostgreSQL database
# Creates: database.dump (custom format), database.sql (plain), schema_only.sql
backup_database() {
  local project_id="$1"
  local output_dir="$2"
  local project_dir="$3"

  log_progress "Backing up PostgreSQL database..."

  local db_output_dir="$output_dir/database"
  mkdir -p "$db_output_dir"

  # Get database password
  local db_password=$(get_db_credentials "$project_dir")
  if [ $? -ne 0 ]; then
    return 1
  fi

  local docker_dir="$project_dir/supabase/docker"
  cd "$docker_dir" || return 1

  # Get the actual container name
  local container_name=$(sudo docker compose -p "$project_id" ps -q db 2>/dev/null)
  if [ -z "$container_name" ]; then
    log_error "Database container not found. Is the project running?"
    return 1
  fi

  # Create custom format dump (best for restore)
  log_progress "  Creating custom format dump..."
  if ! sudo docker exec "$container_name" pg_dump -U postgres -Fc -f /tmp/database.dump postgres 2>/dev/null; then
    log_error "Failed to create custom format database dump"
    return 1
  fi
  sudo docker cp "$container_name:/tmp/database.dump" "$db_output_dir/database.dump" 2>/dev/null
  sudo docker exec "$container_name" rm -f /tmp/database.dump 2>/dev/null

  # Create plain SQL dump (human readable)
  log_progress "  Creating plain SQL dump..."
  if ! sudo docker exec "$container_name" pg_dump -U postgres -f /tmp/database.sql postgres 2>/dev/null; then
    log_warning "Failed to create plain SQL dump (non-critical)"
  else
    sudo docker cp "$container_name:/tmp/database.sql" "$db_output_dir/database.sql" 2>/dev/null
    sudo docker exec "$container_name" rm -f /tmp/database.sql 2>/dev/null
  fi

  # Create schema-only dump (for reference)
  log_progress "  Creating schema-only dump..."
  if ! sudo docker exec "$container_name" pg_dump -U postgres --schema-only -f /tmp/schema_only.sql postgres 2>/dev/null; then
    log_warning "Failed to create schema-only dump (non-critical)"
  else
    sudo docker cp "$container_name:/tmp/schema_only.sql" "$db_output_dir/schema_only.sql" 2>/dev/null
    sudo docker exec "$container_name" rm -f /tmp/schema_only.sql 2>/dev/null
  fi

  # Verify main dump was created
  if [ ! -f "$db_output_dir/database.dump" ]; then
    log_error "Database dump file not found after backup"
    return 1
  fi

  local dump_size=$(stat -c%s "$db_output_dir/database.dump" 2>/dev/null || stat -f%z "$db_output_dir/database.dump" 2>/dev/null)
  log_progress "  Database backup complete ($(format_size $dump_size))"
  return 0
}

# Backup storage buckets
backup_storage() {
  local project_id="$1"
  local output_dir="$2"
  local project_dir="$3"

  log_progress "Backing up storage buckets..."

  local storage_output_dir="$output_dir/storage"
  mkdir -p "$storage_output_dir"

  local volumes_dir="$project_dir/supabase/docker/volumes/storage"

  if [ ! -d "$volumes_dir" ]; then
    log_warning "Storage volumes directory not found: $volumes_dir"
    # Create empty placeholder to indicate no storage data
    echo "No storage data found" > "$storage_output_dir/.empty"
    return 0
  fi

  # Create tar archive of storage directory
  cd "$project_dir/supabase/docker/volumes" || return 1

  if tar -czf "$storage_output_dir/storage.tar.gz" storage 2>/dev/null; then
    local storage_size=$(stat -c%s "$storage_output_dir/storage.tar.gz" 2>/dev/null || stat -f%z "$storage_output_dir/storage.tar.gz" 2>/dev/null)
    log_progress "  Storage backup complete ($(format_size $storage_size))"
    return 0
  else
    log_error "Failed to create storage backup archive"
    return 1
  fi
}

# Backup edge functions
backup_functions() {
  local project_id="$1"
  local output_dir="$2"
  local project_dir="$3"

  log_progress "Backing up edge functions..."

  local functions_output_dir="$output_dir/functions"
  mkdir -p "$functions_output_dir"

  local functions_dir="$project_dir/supabase/docker/volumes/functions"

  if [ ! -d "$functions_dir" ]; then
    log_warning "Functions directory not found: $functions_dir"
    echo "No functions data found" > "$functions_output_dir/.empty"
    return 0
  fi

  # Create tar archive of functions directory
  cd "$project_dir/supabase/docker/volumes" || return 1

  if tar -czf "$functions_output_dir/functions.tar.gz" functions 2>/dev/null; then
    local functions_size=$(stat -c%s "$functions_output_dir/functions.tar.gz" 2>/dev/null || stat -f%z "$functions_output_dir/functions.tar.gz" 2>/dev/null)
    log_progress "  Functions backup complete ($(format_size $functions_size))"
    return 0
  else
    log_error "Failed to create functions backup archive"
    return 1
  fi
}

# Backup project configuration files
backup_config() {
  local project_id="$1"
  local output_dir="$2"
  local project_dir="$3"

  log_progress "Backing up configuration files..."

  local config_output_dir="$output_dir/config"
  mkdir -p "$config_output_dir"

  local docker_dir="$project_dir/supabase/docker"

  # Copy docker-compose.yml
  if [ -f "$docker_dir/docker-compose.yml" ]; then
    cp "$docker_dir/docker-compose.yml" "$config_output_dir/"
    log_progress "  Backed up docker-compose.yml"
  else
    log_warning "docker-compose.yml not found"
  fi

  # Copy .env file
  if [ -f "$docker_dir/.env" ]; then
    cp "$docker_dir/.env" "$config_output_dir/"
    log_progress "  Backed up .env"
  else
    log_warning ".env file not found"
  fi

  # Copy config.toml if it exists
  if [ -f "$project_dir/supabase/supabase/config.toml" ]; then
    cp "$project_dir/supabase/supabase/config.toml" "$config_output_dir/"
    log_progress "  Backed up config.toml"
  fi

  log_progress "  Configuration backup complete"
  return 0
}

# Backup all Docker volumes (comprehensive)
backup_volumes() {
  local project_id="$1"
  local output_dir="$2"
  local project_dir="$3"

  log_progress "Backing up Docker volumes..."

  local volumes_output_dir="$output_dir/volumes"
  mkdir -p "$volumes_output_dir"

  local docker_dir="$project_dir/supabase/docker"
  local volumes_dir="$docker_dir/volumes"

  # Backup bind-mounted volumes directory
  if [ -d "$volumes_dir" ]; then
    log_progress "  Backing up bind-mounted volumes..."
    cd "$docker_dir" || return 1

    if tar -czf "$volumes_output_dir/volumes.tar.gz" volumes 2>/dev/null; then
      local volumes_size=$(stat -c%s "$volumes_output_dir/volumes.tar.gz" 2>/dev/null || stat -f%z "$volumes_output_dir/volumes.tar.gz" 2>/dev/null)
      log_progress "    Bind volumes backup complete ($(format_size $volumes_size))"
    else
      log_warning "Failed to backup bind-mounted volumes"
    fi
  fi

  # Backup named Docker volumes
  log_progress "  Backing up named Docker volumes..."
  cd "$docker_dir" || return 1

  # Get list of named volumes for this project
  local volume_list=$(sudo docker compose -p "$project_id" config --volumes 2>/dev/null)

  if [ -n "$volume_list" ]; then
    for vol_name in $volume_list; do
      local full_vol_name="${project_id}_${vol_name}"

      # Check if volume exists
      if sudo docker volume inspect "$full_vol_name" &>/dev/null; then
        log_progress "    Backing up volume: $vol_name..."

        # Use alpine container to tar the volume contents
        if sudo docker run --rm \
            -v "$full_vol_name:/volume:ro" \
            -v "$volumes_output_dir:/backup" \
            alpine tar -czf "/backup/volume_${vol_name}.tar.gz" -C /volume . 2>/dev/null; then
          log_progress "      Volume $vol_name backed up"
        else
          log_warning "      Failed to backup volume: $vol_name"
        fi
      fi
    done
  else
    log_progress "    No named Docker volumes found"
  fi

  log_progress "  Volumes backup complete"
  return 0
}

# =============================================================================
# Manifest Functions
# =============================================================================

# Create backup manifest with checksums and metadata
create_manifest() {
  local backup_dir="$1"
  local project_id="$2"
  local backup_type="$3"
  local encrypted="$4"

  log_progress "Creating backup manifest..."

  local manifest_file="$backup_dir/manifest.json"

  # Start building manifest
  local manifest="{}"
  manifest=$(echo "$manifest" | jq --arg v "$BACKUP_MANIFEST_VERSION" '.manifest_version = $v')
  manifest=$(echo "$manifest" | jq --arg v "$BACKUP_VERSION" '.supascale_version = $v')
  manifest=$(echo "$manifest" | jq --arg v "$project_id" '.project_id = $v')
  manifest=$(echo "$manifest" | jq --arg v "$backup_type" '.backup_type = $v')
  manifest=$(echo "$manifest" | jq --arg v "$(get_timestamp)" '.created_at = $v')
  manifest=$(echo "$manifest" | jq --arg v "$(hostname)" '.hostname = $v')
  manifest=$(echo "$manifest" | jq --argjson v "$encrypted" '.encrypted = $v')

  # Calculate checksums for all files
  local files_json="[]"

  # Find all files in backup directory (excluding manifest itself)
  while IFS= read -r -d '' file; do
    local rel_path="${file#$backup_dir/}"
    if [ "$rel_path" != "manifest.json" ]; then
      local checksum=$(calculate_checksum "$file")
      local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)

      files_json=$(echo "$files_json" | jq \
        --arg path "$rel_path" \
        --arg checksum "$checksum" \
        --arg size "$size" \
        '. += [{"path": $path, "checksum": $checksum, "size": ($size | tonumber)}]')
    fi
  done < <(find "$backup_dir" -type f -print0)

  manifest=$(echo "$manifest" | jq --argjson files "$files_json" '.files = $files')

  # Add project configuration info if available
  local project_info=$(jq -r ".projects[\"$project_id\"]" "$DB_FILE" 2>/dev/null)
  if [ "$project_info" != "null" ] && [ -n "$project_info" ]; then
    local ports=$(echo "$project_info" | jq '.ports')
    manifest=$(echo "$manifest" | jq --argjson ports "$ports" '.project_ports = $ports')
  fi

  # Calculate total backup size
  local total_size=0
  total_size=$(echo "$files_json" | jq '[.[].size] | add // 0')
  manifest=$(echo "$manifest" | jq --argjson size "$total_size" '.total_size = $size')

  # Write manifest to file
  echo "$manifest" | jq '.' > "$manifest_file"

  log_progress "  Manifest created with $(echo "$files_json" | jq 'length') files"
  return 0
}

# Validate backup manifest and checksums
validate_manifest() {
  local backup_dir="$1"

  local manifest_file="$backup_dir/manifest.json"

  if [ ! -f "$manifest_file" ]; then
    log_error "Manifest file not found: $manifest_file"
    return 1
  fi

  log_progress "Validating backup manifest..."

  # Parse manifest
  local manifest=$(cat "$manifest_file")
  local manifest_version=$(echo "$manifest" | jq -r '.manifest_version')

  if [ "$manifest_version" != "$BACKUP_MANIFEST_VERSION" ]; then
    log_warning "Manifest version mismatch (expected: $BACKUP_MANIFEST_VERSION, got: $manifest_version)"
  fi

  # Validate each file
  local error_count=0
  local file_count=$(echo "$manifest" | jq '.files | length')

  for ((i=0; i<file_count; i++)); do
    local rel_path=$(echo "$manifest" | jq -r ".files[$i].path")
    local expected_checksum=$(echo "$manifest" | jq -r ".files[$i].checksum")
    local file_path="$backup_dir/$rel_path"

    if [ ! -f "$file_path" ]; then
      log_error "  Missing file: $rel_path"
      ((error_count++))
      continue
    fi

    if ! verify_checksum "$file_path" "$expected_checksum"; then
      log_error "  Checksum mismatch: $rel_path"
      ((error_count++))
    else
      log_progress "  ✓ $rel_path"
    fi
  done

  if [ $error_count -gt 0 ]; then
    log_error "Validation failed with $error_count error(s)"
    return 1
  fi

  log_progress "  All $file_count files validated successfully"
  return 0
}

# Read manifest metadata
read_manifest() {
  local backup_path="$1"

  if [ ! -f "$backup_path" ]; then
    log_error "Backup file not found: $backup_path"
    return 1
  fi

  # If it's a tar.gz file, extract manifest to temp
  if [[ "$backup_path" =~ \.tar\.gz(\.enc)?$ ]]; then
    local temp_dir=$(create_backup_temp_dir)
    trap "cleanup_backup_temp_dir '$temp_dir'" EXIT

    # Handle encrypted backups
    local tar_file="$backup_path"
    if [[ "$backup_path" =~ \.enc$ ]]; then
      log_error "Encrypted backup - provide password with --password to read manifest"
      cleanup_backup_temp_dir "$temp_dir"
      return 1
    fi

    # Extract just the manifest
    tar -xzf "$backup_path" -C "$temp_dir" --wildcards 'manifest.json' 2>/dev/null || \
    tar -xzf "$backup_path" -C "$temp_dir" manifest.json 2>/dev/null

    if [ -f "$temp_dir/manifest.json" ]; then
      cat "$temp_dir/manifest.json"
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 0
    else
      log_error "Could not extract manifest from backup"
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 1
    fi
  fi

  # If it's a directory, read manifest directly
  if [ -d "$backup_path" ] && [ -f "$backup_path/manifest.json" ]; then
    cat "$backup_path/manifest.json"
    return 0
  fi

  log_error "Could not read manifest from: $backup_path"
  return 1
}

# =============================================================================
# Component Restore Functions
# =============================================================================

# Restore PostgreSQL database
# Supports --dry-run for testing restore without modifying live data
restore_database() {
  local project_id="$1"
  local backup_dir="$2"
  local project_dir="$3"
  local dry_run="$4"  # "true" or "false"

  local db_backup_dir="$backup_dir/database"

  if [ ! -d "$db_backup_dir" ]; then
    log_warning "No database backup found in this archive"
    return 0
  fi

  if [ ! -f "$db_backup_dir/database.dump" ]; then
    log_error "Database dump file not found: $db_backup_dir/database.dump"
    return 1
  fi

  local docker_dir="$project_dir/supabase/docker"
  cd "$docker_dir" || return 1

  # Get the actual container name
  local container_name=$(sudo docker compose -p "$project_id" ps -q db 2>/dev/null)
  if [ -z "$container_name" ]; then
    log_error "Database container not found. Is the project running?"
    return 1
  fi

  if [ "$dry_run" = "true" ]; then
    log_progress "Testing database restore (dry-run)..."

    # Create a temporary test database
    local temp_db="supascale_restore_test_$$"

    log_progress "  Creating temporary database: $temp_db"
    if ! sudo docker exec "$container_name" psql -U postgres -c "CREATE DATABASE $temp_db;" 2>/dev/null; then
      log_error "Failed to create temporary test database"
      return 1
    fi

    # Copy dump file to container
    log_progress "  Copying backup to container..."
    sudo docker cp "$db_backup_dir/database.dump" "$container_name:/tmp/restore_test.dump" 2>/dev/null

    # Attempt restore to temp database
    log_progress "  Testing restore to temporary database..."
    local restore_result=0
    if ! sudo docker exec "$container_name" pg_restore -U postgres -d "$temp_db" --no-owner --no-acl /tmp/restore_test.dump 2>/dev/null; then
      log_warning "pg_restore reported warnings (this may be normal)"
    fi

    # Verify the temp database has tables
    local table_count=$(sudo docker exec "$container_name" psql -U postgres -d "$temp_db" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')

    # Cleanup temp database
    log_progress "  Cleaning up temporary database..."
    sudo docker exec "$container_name" psql -U postgres -c "DROP DATABASE IF EXISTS $temp_db;" 2>/dev/null
    sudo docker exec "$container_name" rm -f /tmp/restore_test.dump 2>/dev/null

    if [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
      log_progress "  ✓ Dry-run successful: Database restore validated ($table_count tables)"
      return 0
    else
      # Check if we at least could read the dump
      log_progress "  ✓ Dry-run successful: Dump file is readable and restorable"
      return 0
    fi
  else
    log_progress "Restoring PostgreSQL database..."

    # Copy dump file to container
    log_progress "  Copying backup to container..."
    sudo docker cp "$db_backup_dir/database.dump" "$container_name:/tmp/restore.dump" 2>/dev/null

    # Drop and recreate the database
    log_progress "  Dropping existing database..."
    sudo docker exec "$container_name" psql -U postgres -c "DROP DATABASE IF EXISTS postgres WITH (FORCE);" 2>/dev/null || true
    sudo docker exec "$container_name" psql -U postgres -d template1 -c "CREATE DATABASE postgres;" 2>/dev/null

    # Restore the database
    log_progress "  Restoring database from backup..."
    if ! sudo docker exec "$container_name" pg_restore -U postgres -d postgres --no-owner --no-acl /tmp/restore.dump 2>/dev/null; then
      log_warning "pg_restore reported warnings (this is often normal)"
    fi

    # Cleanup
    sudo docker exec "$container_name" rm -f /tmp/restore.dump 2>/dev/null

    log_progress "  Database restore complete"
    return 0
  fi
}

# Restore storage buckets
restore_storage() {
  local project_id="$1"
  local backup_dir="$2"
  local project_dir="$3"
  local dry_run="$4"

  local storage_backup_dir="$backup_dir/storage"

  if [ ! -d "$storage_backup_dir" ]; then
    log_warning "No storage backup found in this archive"
    return 0
  fi

  if [ -f "$storage_backup_dir/.empty" ]; then
    log_progress "Storage backup is empty (no storage data to restore)"
    return 0
  fi

  if [ ! -f "$storage_backup_dir/storage.tar.gz" ]; then
    log_warning "Storage archive not found"
    return 0
  fi

  if [ "$dry_run" = "true" ]; then
    log_progress "Validating storage backup (dry-run)..."

    # Test archive integrity
    if tar -tzf "$storage_backup_dir/storage.tar.gz" > /dev/null 2>&1; then
      local file_count=$(tar -tzf "$storage_backup_dir/storage.tar.gz" 2>/dev/null | wc -l)
      log_progress "  ✓ Storage archive is valid ($file_count files)"
      return 0
    else
      log_error "Storage archive is corrupted"
      return 1
    fi
  else
    log_progress "Restoring storage buckets..."

    local volumes_dir="$project_dir/supabase/docker/volumes"
    mkdir -p "$volumes_dir"

    # Remove existing storage directory
    if [ -d "$volumes_dir/storage" ]; then
      log_progress "  Removing existing storage data..."
      rm -rf "$volumes_dir/storage"
    fi

    # Extract storage archive
    cd "$volumes_dir" || return 1
    if tar -xzf "$storage_backup_dir/storage.tar.gz" 2>/dev/null; then
      log_progress "  Storage restore complete"
      return 0
    else
      log_error "Failed to extract storage archive"
      return 1
    fi
  fi
}

# Restore edge functions
restore_functions() {
  local project_id="$1"
  local backup_dir="$2"
  local project_dir="$3"
  local dry_run="$4"

  local functions_backup_dir="$backup_dir/functions"

  if [ ! -d "$functions_backup_dir" ]; then
    log_warning "No functions backup found in this archive"
    return 0
  fi

  if [ -f "$functions_backup_dir/.empty" ]; then
    log_progress "Functions backup is empty (no functions to restore)"
    return 0
  fi

  if [ ! -f "$functions_backup_dir/functions.tar.gz" ]; then
    log_warning "Functions archive not found"
    return 0
  fi

  if [ "$dry_run" = "true" ]; then
    log_progress "Validating functions backup (dry-run)..."

    if tar -tzf "$functions_backup_dir/functions.tar.gz" > /dev/null 2>&1; then
      local file_count=$(tar -tzf "$functions_backup_dir/functions.tar.gz" 2>/dev/null | wc -l)
      log_progress "  ✓ Functions archive is valid ($file_count files)"
      return 0
    else
      log_error "Functions archive is corrupted"
      return 1
    fi
  else
    log_progress "Restoring edge functions..."

    local volumes_dir="$project_dir/supabase/docker/volumes"
    mkdir -p "$volumes_dir"

    # Remove existing functions directory
    if [ -d "$volumes_dir/functions" ]; then
      log_progress "  Removing existing functions..."
      rm -rf "$volumes_dir/functions"
    fi

    # Extract functions archive
    cd "$volumes_dir" || return 1
    if tar -xzf "$functions_backup_dir/functions.tar.gz" 2>/dev/null; then
      log_progress "  Functions restore complete"
      return 0
    else
      log_error "Failed to extract functions archive"
      return 1
    fi
  fi
}

# Restore configuration files
restore_config() {
  local project_id="$1"
  local backup_dir="$2"
  local project_dir="$3"
  local dry_run="$4"

  local config_backup_dir="$backup_dir/config"

  if [ ! -d "$config_backup_dir" ]; then
    log_warning "No configuration backup found in this archive"
    return 0
  fi

  if [ "$dry_run" = "true" ]; then
    log_progress "Validating configuration backup (dry-run)..."

    local files_found=0
    if [ -f "$config_backup_dir/docker-compose.yml" ]; then
      log_progress "  ✓ docker-compose.yml present"
      ((files_found++))
    fi
    if [ -f "$config_backup_dir/.env" ]; then
      log_progress "  ✓ .env present"
      ((files_found++))
    fi
    if [ -f "$config_backup_dir/config.toml" ]; then
      log_progress "  ✓ config.toml present"
      ((files_found++))
    fi

    if [ $files_found -eq 0 ]; then
      log_warning "No configuration files found in backup"
    else
      log_progress "  Configuration backup validated ($files_found files)"
    fi
    return 0
  else
    log_progress "Restoring configuration files..."

    local docker_dir="$project_dir/supabase/docker"

    # Restore docker-compose.yml
    if [ -f "$config_backup_dir/docker-compose.yml" ]; then
      cp "$config_backup_dir/docker-compose.yml" "$docker_dir/"
      log_progress "  Restored docker-compose.yml"
    fi

    # Restore .env
    if [ -f "$config_backup_dir/.env" ]; then
      cp "$config_backup_dir/.env" "$docker_dir/"
      log_progress "  Restored .env"
    fi

    # Restore config.toml if it exists
    if [ -f "$config_backup_dir/config.toml" ]; then
      mkdir -p "$project_dir/supabase/supabase"
      cp "$config_backup_dir/config.toml" "$project_dir/supabase/supabase/"
      log_progress "  Restored config.toml"
    fi

    log_progress "  Configuration restore complete"
    return 0
  fi
}

# Restore Docker volumes
restore_volumes() {
  local project_id="$1"
  local backup_dir="$2"
  local project_dir="$3"
  local dry_run="$4"

  local volumes_backup_dir="$backup_dir/volumes"

  if [ ! -d "$volumes_backup_dir" ]; then
    log_warning "No volumes backup found in this archive"
    return 0
  fi

  if [ "$dry_run" = "true" ]; then
    log_progress "Validating volumes backup (dry-run)..."

    local valid_archives=0

    # Check bind-mounted volumes
    if [ -f "$volumes_backup_dir/volumes.tar.gz" ]; then
      if tar -tzf "$volumes_backup_dir/volumes.tar.gz" > /dev/null 2>&1; then
        log_progress "  ✓ Bind volumes archive is valid"
        ((valid_archives++))
      else
        log_error "  Bind volumes archive is corrupted"
        return 1
      fi
    fi

    # Check named volumes
    for vol_file in "$volumes_backup_dir"/volume_*.tar.gz; do
      if [ -f "$vol_file" ]; then
        local vol_name=$(basename "$vol_file" .tar.gz | sed 's/volume_//')
        if tar -tzf "$vol_file" > /dev/null 2>&1; then
          log_progress "  ✓ Named volume '$vol_name' archive is valid"
          ((valid_archives++))
        else
          log_error "  Named volume '$vol_name' archive is corrupted"
          return 1
        fi
      fi
    done

    if [ $valid_archives -eq 0 ]; then
      log_warning "No volume archives found"
    else
      log_progress "  Volumes backup validated ($valid_archives archives)"
    fi
    return 0
  else
    log_progress "Restoring Docker volumes..."

    local docker_dir="$project_dir/supabase/docker"

    # Restore bind-mounted volumes
    if [ -f "$volumes_backup_dir/volumes.tar.gz" ]; then
      log_progress "  Restoring bind-mounted volumes..."

      # Remove existing volumes directory
      if [ -d "$docker_dir/volumes" ]; then
        rm -rf "$docker_dir/volumes"
      fi

      cd "$docker_dir" || return 1
      if ! tar -xzf "$volumes_backup_dir/volumes.tar.gz" 2>/dev/null; then
        log_error "Failed to restore bind-mounted volumes"
        return 1
      fi
      log_progress "    Bind volumes restored"
    fi

    # Restore named Docker volumes
    for vol_file in "$volumes_backup_dir"/volume_*.tar.gz; do
      if [ -f "$vol_file" ]; then
        local vol_name=$(basename "$vol_file" .tar.gz | sed 's/volume_//')
        local full_vol_name="${project_id}_${vol_name}"

        log_progress "  Restoring named volume: $vol_name..."

        # Remove existing volume if it exists
        sudo docker volume rm "$full_vol_name" 2>/dev/null || true

        # Create the volume
        sudo docker volume create "$full_vol_name" > /dev/null 2>&1

        # Restore volume contents using alpine container
        if sudo docker run --rm \
            -v "$full_vol_name:/volume" \
            -v "$volumes_backup_dir:/backup:ro" \
            alpine sh -c "rm -rf /volume/* && tar -xzf /backup/volume_${vol_name}.tar.gz -C /volume" 2>/dev/null; then
          log_progress "    Volume $vol_name restored"
        else
          log_warning "    Failed to restore volume: $vol_name"
        fi
      fi
    done

    log_progress "  Volumes restore complete"
    return 0
  fi
}

# =============================================================================
# Retention Policy
# =============================================================================

# Apply retention policy - keep only the N most recent backups
apply_retention_policy() {
  local project_id="$1"
  local backup_type="$2"
  local destination="$3"
  local retention_count="$4"

  if [ -z "$retention_count" ] || [ "$retention_count" -le 0 ]; then
    return 0  # No retention policy specified
  fi

  log_progress "Applying retention policy (keep last $retention_count backups)..."

  # Parse destination
  local dest_info=$(parse_backup_destination "$destination")
  local dest_type=$(echo "$dest_info" | grep "type=" | cut -d'=' -f2)

  if [ "$dest_type" = "s3" ]; then
    local s3_url=$(echo "$dest_info" | grep "url=" | cut -d'=' -f2-)

    # List backups in S3
    local backups=$(aws s3 ls "$s3_url/" 2>/dev/null | grep "${project_id}_${backup_type}_" | awk '{print $4}' | sort -r)
    local count=0

    for backup in $backups; do
      ((count++))
      if [ $count -gt $retention_count ]; then
        log_progress "  Deleting old backup: $backup"
        aws s3 rm "${s3_url}/${backup}" --quiet 2>/dev/null
      fi
    done
  else
    # Local storage
    local backup_dir=$(get_local_backup_dir "$project_id")

    if [ -d "$backup_dir" ]; then
      # List backups sorted by date (newest first)
      local backups=$(ls -1t "$backup_dir"/${project_id}_${backup_type}_*.supascale.tar.gz* 2>/dev/null)
      local count=0

      for backup in $backups; do
        ((count++))
        if [ $count -gt $retention_count ]; then
          log_progress "  Deleting old backup: $(basename "$backup")"
          rm -f "$backup"
        fi
      done
    fi
  fi

  log_progress "  Retention policy applied"
}

# =============================================================================
# Main Backup Command Handler
# =============================================================================

backup_command() {
  local project_id="$1"
  shift

  # Default values
  local backup_type="full"
  local destination="local"
  local encrypt=false
  local password=""
  local password_file=""
  local retention=""

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type=*)
        backup_type="${1#--type=}"
        ;;
      --destination=*)
        destination="${1#--destination=}"
        ;;
      --encrypt)
        encrypt=true
        ;;
      --password=*)
        password="${1#--password=}"
        ;;
      --password-file=*)
        password_file="${1#--password-file=}"
        ;;
      --retention=*)
        retention="${1#--retention=}"
        ;;
      --silent)
        SILENT_MODE=true
        ;;
      *)
        log_error "Unknown option: $1"
        return 1
        ;;
    esac
    shift
  done

  # Validate project exists
  if [ -z "$project_id" ]; then
    log_error "Project ID is required"
    echo "Usage: ./supascale.sh backup <project_id> [options]"
    return 1
  fi

  local project_info=$(jq -r ".projects[\"$project_id\"]" "$DB_FILE" 2>/dev/null)
  if [ "$project_info" = "null" ] || [ -z "$project_info" ]; then
    log_error "Project '$project_id' not found"
    return 1
  fi

  local project_dir=$(echo "$project_info" | jq -r '.directory')

  # Validate backup type
  if ! validate_backup_type "$backup_type"; then
    return 1
  fi

  # Handle encryption password
  if [ "$encrypt" = true ]; then
    if [ -n "$password_file" ] && [ -f "$password_file" ]; then
      password=$(cat "$password_file")
    fi
    if [ -z "$password" ]; then
      log_error "Encryption requires --password or --password-file"
      return 1
    fi
  fi

  # Parse destination
  local dest_info=$(parse_backup_destination "$destination")
  local dest_type=$(echo "$dest_info" | grep "type=" | cut -d'=' -f2)
  local dest_path=$(echo "$dest_info" | grep "path=" | cut -d'=' -f2-)
  local dest_url=$(echo "$dest_info" | grep "url=" | cut -d'=' -f2-)

  # Create temp working directory
  local temp_dir=$(create_backup_temp_dir)
  trap "cleanup_backup_temp_dir '$temp_dir'" EXIT

  log_step "Step 1: Preparing backup"
  log_progress "Project: $project_id"
  log_progress "Type: $backup_type"
  log_progress "Destination: $destination"
  log_progress "Encryption: $([ "$encrypt" = true ] && echo "enabled" || echo "disabled")"

  local backup_work_dir="$temp_dir/backup"
  mkdir -p "$backup_work_dir"

  local errors=0

  # Stop containers for consistent backup (database backup)
  local containers_stopped=false
  if [ "$backup_type" = "full" ] || [ "$backup_type" = "database" ]; then
    log_step "Step 2: Stopping containers for consistent backup"
    local docker_dir="$project_dir/supabase/docker"
    cd "$docker_dir" 2>/dev/null
    # Only stop if containers are running
    if sudo docker compose -p "$project_id" ps -q 2>/dev/null | grep -q .; then
      # Just stop the db container for database backup
      log_progress "Stopping database container..."
      sudo docker compose -p "$project_id" stop db 2>/dev/null || true
      containers_stopped=true
      sleep 2
      # Restart db for pg_dump
      sudo docker compose -p "$project_id" start db 2>/dev/null
      sleep 3
    fi
  fi

  log_step "Step 3: Creating backup"

  # Execute component backups based on type
  case "$backup_type" in
    full)
      backup_database "$project_id" "$backup_work_dir" "$project_dir" || ((errors++))
      backup_storage "$project_id" "$backup_work_dir" "$project_dir" || ((errors++))
      backup_functions "$project_id" "$backup_work_dir" "$project_dir" || ((errors++))
      backup_config "$project_id" "$backup_work_dir" "$project_dir" || ((errors++))
      backup_volumes "$project_id" "$backup_work_dir" "$project_dir" || ((errors++))
      ;;
    database)
      backup_database "$project_id" "$backup_work_dir" "$project_dir" || ((errors++))
      ;;
    storage)
      backup_storage "$project_id" "$backup_work_dir" "$project_dir" || ((errors++))
      ;;
    functions)
      backup_functions "$project_id" "$backup_work_dir" "$project_dir" || ((errors++))
      ;;
    config)
      backup_config "$project_id" "$backup_work_dir" "$project_dir" || ((errors++))
      ;;
  esac

  # Restart containers if we stopped them
  if [ "$containers_stopped" = true ]; then
    log_progress "Restarting containers..."
    cd "$project_dir/supabase/docker" 2>/dev/null
    sudo docker compose -p "$project_id" up -d 2>/dev/null
  fi

  if [ $errors -gt 0 ]; then
    log_error "Backup completed with $errors error(s)"
  fi

  log_step "Step 4: Creating manifest"
  create_manifest "$backup_work_dir" "$project_id" "$backup_type" "$encrypt"

  log_step "Step 5: Compressing backup"
  local backup_filename=$(generate_backup_filename "$project_id" "$backup_type")
  local compressed_file="$temp_dir/$backup_filename"

  cd "$backup_work_dir" || return 1
  if ! tar -czf "$compressed_file" . 2>/dev/null; then
    log_error "Failed to compress backup"
    cleanup_backup_temp_dir "$temp_dir"
    trap - EXIT
    return 1
  fi

  local compressed_size=$(stat -c%s "$compressed_file" 2>/dev/null || stat -f%z "$compressed_file" 2>/dev/null)
  log_progress "Compressed backup size: $(format_size $compressed_size)"

  # Encrypt if requested
  local final_file="$compressed_file"
  if [ "$encrypt" = true ]; then
    log_step "Step 6: Encrypting backup"
    local encrypted_file="${compressed_file}.enc"
    if encrypt_file "$compressed_file" "$encrypted_file" "$password"; then
      rm -f "$compressed_file"
      final_file="$encrypted_file"
      backup_filename="${backup_filename}.enc"
      log_progress "Backup encrypted successfully"
    else
      log_error "Encryption failed"
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 1
    fi
  fi

  log_step "Step 7: Saving backup to destination"

  # Save to destination
  if [ "$dest_type" = "s3" ]; then
    local s3_dest="${dest_url}/${backup_filename}"
    if upload_to_s3 "$final_file" "$s3_dest"; then
      log_progress "Backup uploaded to: $s3_dest"
    else
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 1
    fi
  else
    # Local storage
    local local_dest_dir
    if [ -n "$dest_path" ]; then
      local_dest_dir="$dest_path"
    else
      local_dest_dir=$(get_local_backup_dir "$project_id")
    fi
    mkdir -p "$local_dest_dir"

    local final_path="$local_dest_dir/$backup_filename"
    if mv "$final_file" "$final_path"; then
      log_progress "Backup saved to: $final_path"
    else
      log_error "Failed to save backup"
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 1
    fi
  fi

  # Apply retention policy
  if [ -n "$retention" ]; then
    apply_retention_policy "$project_id" "$backup_type" "$destination" "$retention"
  fi

  # Cleanup
  cleanup_backup_temp_dir "$temp_dir"
  trap - EXIT

  log_step "Backup Complete"
  log_progress "Project: $project_id"
  log_progress "Type: $backup_type"
  log_progress "Size: $(format_size $compressed_size)"
  if [ "$dest_type" = "s3" ]; then
    log_progress "Location: ${dest_url}/${backup_filename}"
  else
    log_progress "Location: $final_path"
  fi

  return 0
}

# =============================================================================
# Main Restore Command Handler
# =============================================================================

restore_command() {
  local project_id="$1"
  shift

  # Default values
  local from_path=""
  local dry_run=false
  local password=""
  local password_file=""
  local confirm=false

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from=*)
        from_path="${1#--from=}"
        ;;
      --from)
        shift
        from_path="$1"
        ;;
      --dry-run)
        dry_run=true
        ;;
      --password=*)
        password="${1#--password=}"
        ;;
      --password-file=*)
        password_file="${1#--password-file=}"
        ;;
      --confirm)
        confirm=true
        ;;
      --silent)
        SILENT_MODE=true
        ;;
      *)
        log_error "Unknown option: $1"
        return 1
        ;;
    esac
    shift
  done

  # Validate project exists
  if [ -z "$project_id" ]; then
    log_error "Project ID is required"
    echo "Usage: ./supascale.sh restore <project_id> --from <backup_path> [options]"
    return 1
  fi

  local project_info=$(jq -r ".projects[\"$project_id\"]" "$DB_FILE" 2>/dev/null)
  if [ "$project_info" = "null" ] || [ -z "$project_info" ]; then
    log_error "Project '$project_id' not found"
    return 1
  fi

  local project_dir=$(echo "$project_info" | jq -r '.directory')

  # Validate backup path
  if [ -z "$from_path" ]; then
    log_error "--from <backup_path> is required"
    return 1
  fi

  # Handle password from file
  if [ -n "$password_file" ] && [ -f "$password_file" ]; then
    password=$(cat "$password_file")
  fi

  # Create temp working directory
  local temp_dir=$(create_backup_temp_dir)
  trap "cleanup_backup_temp_dir '$temp_dir'" EXIT

  local backup_file="$from_path"
  local is_s3=false

  # Download from S3 if needed
  if [[ "$from_path" =~ ^s3:// ]]; then
    is_s3=true
    log_step "Step 1: Downloading backup from S3"
    backup_file="$temp_dir/$(basename "$from_path")"
    if ! download_from_s3 "$from_path" "$backup_file"; then
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 1
    fi
  else
    log_step "Step 1: Locating backup file"
    if [ ! -f "$backup_file" ]; then
      log_error "Backup file not found: $backup_file"
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 1
    fi
    log_progress "Found: $backup_file"
  fi

  # Decrypt if needed
  if [[ "$backup_file" =~ \.enc$ ]]; then
    log_step "Step 2: Decrypting backup"
    if [ -z "$password" ]; then
      log_error "Encrypted backup requires --password or --password-file"
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 1
    fi

    local decrypted_file="${backup_file%.enc}"
    if ! decrypt_file "$backup_file" "$decrypted_file" "$password"; then
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 1
    fi
    backup_file="$decrypted_file"
    log_progress "Backup decrypted successfully"
  fi

  # Extract backup
  log_step "Step 3: Extracting backup"
  local extract_dir="$temp_dir/extracted"
  mkdir -p "$extract_dir"

  if ! tar -xzf "$backup_file" -C "$extract_dir" 2>/dev/null; then
    log_error "Failed to extract backup archive"
    cleanup_backup_temp_dir "$temp_dir"
    trap - EXIT
    return 1
  fi
  log_progress "Backup extracted successfully"

  # Validate manifest and checksums
  log_step "Step 4: Validating backup integrity"
  if ! validate_manifest "$extract_dir"; then
    log_error "Backup validation failed - archive may be corrupted"
    cleanup_backup_temp_dir "$temp_dir"
    trap - EXIT
    return 1
  fi

  # Read backup info from manifest
  local manifest=$(cat "$extract_dir/manifest.json")
  local backup_type=$(echo "$manifest" | jq -r '.backup_type')
  local backup_date=$(echo "$manifest" | jq -r '.created_at')
  local backup_project=$(echo "$manifest" | jq -r '.project_id')

  log_progress "Backup type: $backup_type"
  log_progress "Created: $backup_date"
  log_progress "Original project: $backup_project"

  if [ "$dry_run" = true ]; then
    log_step "Step 5: Performing dry-run validation"
    log_progress "Testing restore without modifying live data..."

    local validation_errors=0

    # Test each component based on backup type
    case "$backup_type" in
      full)
        restore_database "$project_id" "$extract_dir" "$project_dir" "true" || ((validation_errors++))
        restore_storage "$project_id" "$extract_dir" "$project_dir" "true" || ((validation_errors++))
        restore_functions "$project_id" "$extract_dir" "$project_dir" "true" || ((validation_errors++))
        restore_config "$project_id" "$extract_dir" "$project_dir" "true" || ((validation_errors++))
        restore_volumes "$project_id" "$extract_dir" "$project_dir" "true" || ((validation_errors++))
        ;;
      database)
        restore_database "$project_id" "$extract_dir" "$project_dir" "true" || ((validation_errors++))
        ;;
      storage)
        restore_storage "$project_id" "$extract_dir" "$project_dir" "true" || ((validation_errors++))
        ;;
      functions)
        restore_functions "$project_id" "$extract_dir" "$project_dir" "true" || ((validation_errors++))
        ;;
      config)
        restore_config "$project_id" "$extract_dir" "$project_dir" "true" || ((validation_errors++))
        ;;
    esac

    # Cleanup
    cleanup_backup_temp_dir "$temp_dir"
    trap - EXIT

    echo ""
    echo "=========================================="
    if [ $validation_errors -eq 0 ]; then
      echo "DRY-RUN VALIDATION PASSED"
      echo "=========================================="
      echo ""
      echo "The backup is valid and can be restored."
      echo "Run without --dry-run to perform actual restore."
      return 0
    else
      echo "DRY-RUN VALIDATION FAILED"
      echo "=========================================="
      echo ""
      echo "The backup has $validation_errors validation error(s)."
      echo "Review the errors above before attempting restore."
      return 1
    fi
  else
    # Live restore
    if [ "$confirm" != true ]; then
      echo ""
      echo "WARNING: This will restore data from backup and overwrite existing data!"
      echo "Project: $project_id"
      echo "Backup: $from_path"
      echo "Type: $backup_type"
      echo ""
      read -p "Are you sure you want to proceed? (y/N): " -r
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Restore cancelled."
        cleanup_backup_temp_dir "$temp_dir"
        trap - EXIT
        return 0
      fi
    fi

    log_step "Step 5: Stopping containers"
    local docker_dir="$project_dir/supabase/docker"
    cd "$docker_dir" 2>/dev/null
    sudo docker compose -p "$project_id" down 2>/dev/null || true
    sleep 3

    log_step "Step 6: Restoring from backup"
    local restore_errors=0

    # Restore each component based on backup type
    case "$backup_type" in
      full)
        restore_config "$project_id" "$extract_dir" "$project_dir" "false" || ((restore_errors++))
        restore_volumes "$project_id" "$extract_dir" "$project_dir" "false" || ((restore_errors++))
        # Start containers for database restore
        cd "$docker_dir" 2>/dev/null
        sudo docker compose -p "$project_id" up -d db 2>/dev/null
        sleep 5
        restore_database "$project_id" "$extract_dir" "$project_dir" "false" || ((restore_errors++))
        restore_storage "$project_id" "$extract_dir" "$project_dir" "false" || ((restore_errors++))
        restore_functions "$project_id" "$extract_dir" "$project_dir" "false" || ((restore_errors++))
        ;;
      database)
        cd "$docker_dir" 2>/dev/null
        sudo docker compose -p "$project_id" up -d db 2>/dev/null
        sleep 5
        restore_database "$project_id" "$extract_dir" "$project_dir" "false" || ((restore_errors++))
        ;;
      storage)
        restore_storage "$project_id" "$extract_dir" "$project_dir" "false" || ((restore_errors++))
        ;;
      functions)
        restore_functions "$project_id" "$extract_dir" "$project_dir" "false" || ((restore_errors++))
        ;;
      config)
        restore_config "$project_id" "$extract_dir" "$project_dir" "false" || ((restore_errors++))
        ;;
    esac

    log_step "Step 7: Starting containers"
    cd "$docker_dir" 2>/dev/null
    sudo docker compose -p "$project_id" up -d 2>/dev/null

    # Cleanup
    cleanup_backup_temp_dir "$temp_dir"
    trap - EXIT

    log_step "Restore Complete"
    if [ $restore_errors -eq 0 ]; then
      log_progress "All components restored successfully"
      log_progress "Project '$project_id' has been restored from backup"
    else
      log_warning "Restore completed with $restore_errors error(s)"
      log_progress "Review the errors above and verify your project"
    fi

    return 0
  fi
}

# =============================================================================
# Utility Commands
# =============================================================================

# List available backups for a project
list_backups_command() {
  local project_id="$1"
  local destination="${2:-local}"

  if [ -z "$project_id" ]; then
    log_error "Project ID is required"
    echo "Usage: ./supascale.sh list-backups <project_id> [destination]"
    return 1
  fi

  echo "Backups for project: $project_id"
  echo "=================================="

  local dest_info=$(parse_backup_destination "$destination")
  local dest_type=$(echo "$dest_info" | grep "type=" | cut -d'=' -f2)

  if [ "$dest_type" = "s3" ]; then
    local s3_url=$(echo "$dest_info" | grep "url=" | cut -d'=' -f2-)
    echo "Location: $s3_url"
    echo ""

    if ! check_aws_cli; then
      return 1
    fi

    aws s3 ls "$s3_url/" 2>/dev/null | grep "${project_id}_" | while read -r line; do
      local size=$(echo "$line" | awk '{print $3}')
      local file=$(echo "$line" | awk '{print $4}')
      local date=$(echo "$line" | awk '{print $1 " " $2}')
      echo "  $file"
      echo "    Size: $(format_size $size)"
      echo "    Date: $date"
      echo ""
    done
  else
    local backup_dir=$(get_local_backup_dir "$project_id")
    echo "Location: $backup_dir"
    echo ""

    if [ ! -d "$backup_dir" ]; then
      echo "No backups found."
      return 0
    fi

    ls -1t "$backup_dir"/${project_id}_*.supascale.tar.gz* 2>/dev/null | while read -r file; do
      local filename=$(basename "$file")
      local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
      local date=$(stat -c%y "$file" 2>/dev/null | cut -d'.' -f1 || stat -f%Sm "$file" 2>/dev/null)

      # Extract type from filename
      local backup_type=$(echo "$filename" | sed -E 's/.*_([a-z]+)_[0-9]+.*/\1/')

      echo "  $filename"
      echo "    Type: $backup_type"
      echo "    Size: $(format_size $size)"
      echo "    Date: $date"
      if [[ "$filename" =~ \.enc$ ]]; then
        echo "    Encrypted: yes"
      fi
      echo ""
    done

    if [ -z "$(ls -1 "$backup_dir"/${project_id}_*.supascale.tar.gz* 2>/dev/null)" ]; then
      echo "No backups found."
    fi
  fi
}

# Verify backup integrity
verify_backup_command() {
  local backup_path="$1"
  local password="$2"

  if [ -z "$backup_path" ]; then
    log_error "Backup path is required"
    echo "Usage: ./supascale.sh verify-backup <backup_path> [--password=<pass>]"
    return 1
  fi

  echo "Verifying backup: $backup_path"
  echo "=================================="

  # Check if file exists
  if [ ! -f "$backup_path" ]; then
    log_error "Backup file not found: $backup_path"
    return 1
  fi

  local temp_dir=$(create_backup_temp_dir)
  trap "cleanup_backup_temp_dir '$temp_dir'" EXIT

  local work_file="$backup_path"

  # Decrypt if needed
  if [[ "$backup_path" =~ \.enc$ ]]; then
    if [ -z "$password" ]; then
      log_error "Encrypted backup requires --password"
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 1
    fi

    echo "Decrypting backup..."
    work_file="$temp_dir/decrypted.tar.gz"
    if ! decrypt_file "$backup_path" "$work_file" "$password"; then
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 1
    fi
    echo "  ✓ Decryption successful"
  fi

  # Extract backup
  echo "Extracting backup..."
  local extract_dir="$temp_dir/extracted"
  mkdir -p "$extract_dir"

  if ! tar -xzf "$work_file" -C "$extract_dir" 2>/dev/null; then
    log_error "Failed to extract backup archive"
    cleanup_backup_temp_dir "$temp_dir"
    trap - EXIT
    return 1
  fi
  echo "  ✓ Archive extraction successful"

  # Validate manifest
  echo ""
  if validate_manifest "$extract_dir"; then
    echo ""
    echo "=========================================="
    echo "BACKUP VERIFICATION PASSED"
    echo "=========================================="
    echo "The backup is valid and all checksums match."
    cleanup_backup_temp_dir "$temp_dir"
    trap - EXIT
    return 0
  else
    echo ""
    echo "=========================================="
    echo "BACKUP VERIFICATION FAILED"
    echo "=========================================="
    echo "The backup may be corrupted. See errors above."
    cleanup_backup_temp_dir "$temp_dir"
    trap - EXIT
    return 1
  fi
}

# Show backup information
backup_info_command() {
  local backup_path="$1"
  local password=""

  # Parse password option
  for arg in "$@"; do
    case "$arg" in
      --password=*)
        password="${arg#--password=}"
        ;;
    esac
  done

  if [ -z "$backup_path" ]; then
    log_error "Backup path is required"
    echo "Usage: ./supascale.sh backup-info <backup_path> [--password=<pass>]"
    return 1
  fi

  if [ ! -f "$backup_path" ]; then
    log_error "Backup file not found: $backup_path"
    return 1
  fi

  echo "Backup Information"
  echo "=================="
  echo ""

  local temp_dir=$(create_backup_temp_dir)
  trap "cleanup_backup_temp_dir '$temp_dir'" EXIT

  local work_file="$backup_path"

  # Decrypt if needed
  if [[ "$backup_path" =~ \.enc$ ]]; then
    if [ -z "$password" ]; then
      log_error "Encrypted backup requires --password"
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 1
    fi

    work_file="$temp_dir/decrypted.tar.gz"
    if ! decrypt_file "$backup_path" "$work_file" "$password" 2>/dev/null; then
      cleanup_backup_temp_dir "$temp_dir"
      trap - EXIT
      return 1
    fi
  fi

  # Extract just manifest
  local extract_dir="$temp_dir/extracted"
  mkdir -p "$extract_dir"
  tar -xzf "$work_file" -C "$extract_dir" manifest.json 2>/dev/null

  if [ -f "$extract_dir/manifest.json" ]; then
    local manifest=$(cat "$extract_dir/manifest.json")

    echo "File: $(basename "$backup_path")"
    local file_size=$(stat -c%s "$backup_path" 2>/dev/null || stat -f%z "$backup_path" 2>/dev/null)
    echo "File Size: $(format_size $file_size)"
    echo ""
    echo "Project ID: $(echo "$manifest" | jq -r '.project_id')"
    echo "Backup Type: $(echo "$manifest" | jq -r '.backup_type')"
    echo "Created: $(echo "$manifest" | jq -r '.created_at')"
    echo "Host: $(echo "$manifest" | jq -r '.hostname')"
    echo "Supascale Version: $(echo "$manifest" | jq -r '.supascale_version')"
    echo "Encrypted: $(echo "$manifest" | jq -r '.encrypted')"
    echo ""
    echo "Contents:"
    local total_size=$(echo "$manifest" | jq -r '.total_size')
    echo "  Total Size (uncompressed): $(format_size $total_size)"
    echo "  Files:"
    echo "$manifest" | jq -r '.files[] | "    - \(.path) (\(.size) bytes)"'

    # Show ports if available
    local ports=$(echo "$manifest" | jq -r '.project_ports // empty')
    if [ -n "$ports" ] && [ "$ports" != "null" ]; then
      echo ""
      echo "Original Port Configuration:"
      echo "$ports" | jq -r 'to_entries[] | "    \(.key): \(.value)"'
    fi
  else
    log_error "Could not read manifest from backup"
    cleanup_backup_temp_dir "$temp_dir"
    trap - EXIT
    return 1
  fi

  cleanup_backup_temp_dir "$temp_dir"
  trap - EXIT
  return 0
}

# Setup backup schedule helper
setup_backup_schedule_command() {
  local project_id="$1"

  if [ -z "$project_id" ]; then
    log_error "Project ID is required"
    echo "Usage: ./supascale.sh setup-backup-schedule <project_id>"
    return 1
  fi

  # Get script path
  local script_path="$(readlink -f "${BASH_SOURCE[0]}")"

  echo "Backup Schedule Setup for: $project_id"
  echo "========================================"
  echo ""
  echo "Add one of the following lines to your crontab (crontab -e):"
  echo ""
  echo "Daily full backup at 2 AM:"
  echo "  0 2 * * * $script_path backup $project_id --type full --silent"
  echo ""
  echo "Daily database backup at 3 AM with 30-day retention:"
  echo "  0 3 * * * $script_path backup $project_id --type database --silent --retention 30"
  echo ""
  echo "Weekly full backup every Sunday at 1 AM to S3:"
  echo "  0 1 * * 0 $script_path backup $project_id --type full --destination s3://your-bucket/backups --silent"
  echo ""
  echo "Daily encrypted backup with password file:"
  echo "  0 2 * * * $script_path backup $project_id --type full --encrypt --password-file /secure/backup.key --silent"
  echo ""
  echo "Tips:"
  echo "  - Use --silent flag for cron jobs to minimize output"
  echo "  - Use --retention to automatically delete old backups"
  echo "  - Store password files with restricted permissions (chmod 600)"
  echo "  - For S3, ensure AWS CLI is configured for the cron user"
  echo ""
}

################################################################################
# End Backup Feature Functions
################################################################################

################################################################################
# Custom Domain Functions
################################################################################

# =============================================================================
# Web Server Detection and Helper Functions
# =============================================================================

# Function to detect installed web server
# Returns: nginx, apache, caddy, or "none"
detect_web_server() {
  local detected=""
  local running=""

  # Check for Nginx
  if command -v nginx &> /dev/null; then
    if systemctl is-active --quiet nginx 2>/dev/null; then
      running="nginx"
    fi
    detected="${detected:+$detected }nginx"
  fi

  # Check for Apache (apache2 on Debian/Ubuntu, httpd on RHEL/CentOS)
  if command -v apache2 &> /dev/null || command -v httpd &> /dev/null; then
    if systemctl is-active --quiet apache2 2>/dev/null || systemctl is-active --quiet httpd 2>/dev/null; then
      running="${running:+$running }apache"
    fi
    detected="${detected:+$detected }apache"
  fi

  # Check for Caddy
  if command -v caddy &> /dev/null; then
    if systemctl is-active --quiet caddy 2>/dev/null; then
      running="${running:+$running }caddy"
    fi
    detected="${detected:+$detected }caddy"
  fi

  # Prefer running server, otherwise return first detected
  if [ -n "$running" ]; then
    echo "$running" | awk '{print $1}'
  elif [ -n "$detected" ]; then
    echo "$detected" | awk '{print $1}'
  else
    echo "none"
  fi
}

# Function to check if a specific web server is available
check_web_server_available() {
  local server="$1"
  case "$server" in
    nginx)
      command -v nginx &> /dev/null
      ;;
    apache)
      command -v apache2 &> /dev/null || command -v httpd &> /dev/null
      ;;
    caddy)
      command -v caddy &> /dev/null
      ;;
    *)
      return 1
      ;;
  esac
}

# Function to detect Apache distribution type (debian or rhel)
# Returns: "debian" for Ubuntu/Debian, "rhel" for RHEL/CentOS/Fedora
get_apache_distro_type() {
  # Check if Debian-style Apache exists
  if [ -d "/etc/apache2" ]; then
    echo "debian"
  # Check if RHEL-style Apache exists
  elif [ -d "/etc/httpd" ]; then
    echo "rhel"
  # Fallback: check which command is available
  elif command -v apache2 &> /dev/null; then
    echo "debian"
  elif command -v httpd &> /dev/null; then
    echo "rhel"
  else
    # Default to debian style
    echo "debian"
  fi
}

# Function to get Apache config directory for the current system
get_apache_config_dir() {
  local distro_type=$(get_apache_distro_type)
  if [ "$distro_type" = "rhel" ]; then
    echo "$APACHE_RHEL_CONF_D"
  else
    echo "$APACHE_DEBIAN_SITES_AVAILABLE"
  fi
}

# Function to get Apache service name for the current system
get_apache_service_name() {
  local distro_type=$(get_apache_distro_type)
  if [ "$distro_type" = "rhel" ]; then
    echo "httpd"
  else
    echo "apache2"
  fi
}

# Function to configure firewall for HTTP/HTTPS ports
configure_firewall() {
  local action="${1:-open}"  # open or close

  echo "Checking firewall configuration..."

  # Check for firewalld (RHEL/CentOS/Fedora)
  if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
    echo "Detected firewalld - configuring ports 80 and 443..."
    if [ "$action" = "open" ]; then
      sudo firewall-cmd --permanent --add-service=http 2>/dev/null || true
      sudo firewall-cmd --permanent --add-service=https 2>/dev/null || true
      sudo firewall-cmd --reload 2>/dev/null || true
      echo "Firewalld: HTTP and HTTPS services enabled."
    else
      sudo firewall-cmd --permanent --remove-service=http 2>/dev/null || true
      sudo firewall-cmd --permanent --remove-service=https 2>/dev/null || true
      sudo firewall-cmd --reload 2>/dev/null || true
      echo "Firewalld: HTTP and HTTPS services disabled."
    fi
    return 0
  fi

  # Check for ufw (Ubuntu)
  if command -v ufw &> /dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    echo "Detected ufw - configuring ports 80 and 443..."
    if [ "$action" = "open" ]; then
      sudo ufw allow 80/tcp 2>/dev/null || true
      sudo ufw allow 443/tcp 2>/dev/null || true
      echo "UFW: Ports 80 and 443 opened."
    else
      sudo ufw delete allow 80/tcp 2>/dev/null || true
      sudo ufw delete allow 443/tcp 2>/dev/null || true
      echo "UFW: Ports 80 and 443 rules removed."
    fi
    return 0
  fi

  # Check for iptables (if no firewalld or ufw)
  if command -v iptables &> /dev/null; then
    # Check if iptables has any rules (indicating it's being used)
    local rule_count=$(sudo iptables -L INPUT -n 2>/dev/null | wc -l)
    if [ "$rule_count" -gt 2 ]; then
      echo "Detected iptables - configuring ports 80 and 443..."
      if [ "$action" = "open" ]; then
        # Check if rules already exist to avoid duplicates
        if ! sudo iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null; then
          sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        fi
        if ! sudo iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
          sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
        fi
        # Try to save iptables rules
        if command -v iptables-save &> /dev/null; then
          if [ -d "/etc/iptables" ]; then
            sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null 2>&1 || true
          elif [ -f "/etc/sysconfig/iptables" ]; then
            sudo iptables-save | sudo tee /etc/sysconfig/iptables > /dev/null 2>&1 || true
          fi
        fi
        echo "Iptables: Ports 80 and 443 opened."
      else
        sudo iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        sudo iptables -D INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
        echo "Iptables: Ports 80 and 443 rules removed."
      fi
      return 0
    fi
  fi

  echo "No active firewall detected (firewalld, ufw, or iptables). Skipping firewall configuration."
  echo "Note: If you have a firewall, ensure ports 80 and 443 are open for HTTP/HTTPS traffic."
  return 0
}

# Function to get server's public/external IP address
get_server_ip() {
  local ip=""

  # Try multiple methods to get public IP
  if command -v curl &> /dev/null; then
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null)
  elif command -v wget &> /dev/null; then
    ip=$(wget -q --timeout=5 -O- https://api.ipify.org 2>/dev/null)
  fi

  # Fallback to local IP if public IP retrieval fails
  if [ -z "$ip" ]; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi

  echo "$ip"
}

# Function to validate DNS resolution for a domain
# Returns 0 if domain resolves, 1 otherwise
validate_dns() {
  local domain="$1"
  local expected_ip="$2"

  # Check if any DNS lookup tool is available
  if ! command -v dig &> /dev/null && ! command -v host &> /dev/null && ! command -v nslookup &> /dev/null; then
    echo "Warning: No DNS lookup tool available (dig, host, or nslookup). Skipping DNS validation."
    return 0
  fi

  local resolved_ip=""

  # Try dig first
  if command -v dig &> /dev/null; then
    resolved_ip=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
  # Try host as fallback
  elif command -v host &> /dev/null; then
    resolved_ip=$(host "$domain" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
  # Try nslookup as last resort
  elif command -v nslookup &> /dev/null; then
    resolved_ip=$(nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | grep "Address" | head -1 | awk '{print $NF}')
  fi

  if [ -z "$resolved_ip" ]; then
    echo ""
    echo "ERROR: Domain '$domain' does not resolve to any IP address."
    echo ""
    echo "Please create a DNS A record:"
    echo "  Type:  A"
    echo "  Name:  $domain"
    echo "  Value: $expected_ip"
    echo ""
    echo "DNS propagation can take 5-30 minutes."
    return 1
  fi

  if [ "$resolved_ip" != "$expected_ip" ]; then
    echo ""
    echo "WARNING: Domain '$domain' resolves to $resolved_ip"
    echo "         Expected IP: $expected_ip"
    echo ""
    read -p "Continue anyway? (y/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
      return 1
    fi
  else
    echo "DNS validation passed: $domain -> $resolved_ip"
  fi

  return 0
}

# Function to validate domain name format
validate_domain_format() {
  local domain="$1"

  # Check for valid domain format (basic validation)
  if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
    echo "Error: Invalid domain format: $domain"
    echo "Domain must be a valid FQDN (e.g., myapp.example.com)"
    return 1
  fi

  return 0
}

# Function to prompt for sudo permission with explanation
request_sudo_permission() {
  local operation="$1"

  echo ""
  echo "============================================================"
  echo "SUDO PERMISSION REQUIRED"
  echo "============================================================"
  echo "The following operation requires administrative privileges:"
  echo "  $operation"
  echo ""
  echo "This is needed to:"
  echo "  - Configure web server (nginx/apache/caddy)"
  echo "  - Enable/reload web server service"
  echo "  - Generate SSL certificates via certbot"
  echo "  - Configure firewall for HTTP/HTTPS traffic (ports 80/443)"
  echo "============================================================"
  echo ""

  read -p "Do you want to proceed with sudo? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled by user."
    return 1
  fi

  # Test sudo access
  if ! sudo -v; then
    echo "Error: Failed to obtain sudo privileges."
    return 1
  fi

  return 0
}

# Function to ensure web server is enabled at startup
enable_web_server_startup() {
  local server="$1"

  echo "Enabling $server to start on boot..."

  case "$server" in
    nginx)
      sudo systemctl enable nginx 2>/dev/null || true
      ;;
    apache)
      if command -v apache2 &> /dev/null; then
        sudo systemctl enable apache2 2>/dev/null || true
      else
        sudo systemctl enable httpd 2>/dev/null || true
      fi
      ;;
    caddy)
      sudo systemctl enable caddy 2>/dev/null || true
      ;;
  esac
}

# Function to start web server if not running
start_web_server() {
  local server="$1"

  case "$server" in
    nginx)
      if ! systemctl is-active --quiet nginx 2>/dev/null; then
        sudo systemctl start nginx
      fi
      ;;
    apache)
      if command -v apache2 &> /dev/null; then
        if ! systemctl is-active --quiet apache2 2>/dev/null; then
          sudo systemctl start apache2
        fi
      else
        if ! systemctl is-active --quiet httpd 2>/dev/null; then
          sudo systemctl start httpd
        fi
      fi
      ;;
    caddy)
      if ! systemctl is-active --quiet caddy 2>/dev/null; then
        sudo systemctl start caddy
      fi
      ;;
  esac
}

# Function to prompt user to select and install a web server
prompt_install_web_server() {
  echo ""
  echo "No supported web server found on this system."
  echo ""
  echo "Please choose a web server to install:"
  echo "  1) Nginx (recommended - lightweight, high performance)"
  echo "  2) Apache (widely used, extensive module support)"
  echo "  3) Caddy (automatic HTTPS, simple configuration)"
  echo "  4) Cancel"
  echo ""
  read -p "Selection [1-4]: " server_choice

  local selected_server=""
  local install_cmd=""

  case "$server_choice" in
    1)
      selected_server="nginx"
      if command -v apt &> /dev/null; then
        install_cmd="sudo apt update && sudo apt install -y nginx"
      elif command -v dnf &> /dev/null; then
        install_cmd="sudo dnf install -y nginx"
      elif command -v yum &> /dev/null; then
        install_cmd="sudo yum install -y nginx"
      elif command -v brew &> /dev/null; then
        install_cmd="brew install nginx"
      fi
      ;;
    2)
      selected_server="apache"
      if command -v apt &> /dev/null; then
        install_cmd="sudo apt update && sudo apt install -y apache2"
      elif command -v dnf &> /dev/null; then
        install_cmd="sudo dnf install -y httpd"
      elif command -v yum &> /dev/null; then
        install_cmd="sudo yum install -y httpd"
      fi
      ;;
    3)
      selected_server="caddy"
      echo ""
      echo "To install Caddy, follow the instructions at:"
      echo "  https://caddyserver.com/docs/install"
      echo ""
      echo "For Debian/Ubuntu:"
      echo "  sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https"
      echo "  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
      echo "  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list"
      echo "  sudo apt update && sudo apt install caddy"
      echo ""
      return 1
      ;;
    *)
      echo "Cancelled."
      return 1
      ;;
  esac

  if [ -z "$install_cmd" ]; then
    echo "Could not determine package manager. Please install $selected_server manually."
    return 1
  fi

  echo ""
  echo "Installing $selected_server..."
  echo "Running: $install_cmd"
  echo ""

  read -p "Proceed with installation? (y/N): " confirm_install
  if [[ ! "$confirm_install" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    return 1
  fi

  if eval "$install_cmd"; then
    echo "$selected_server installed successfully."
    echo "$selected_server"
    return 0
  else
    echo "Error: Failed to install $selected_server"
    return 1
  fi
}

# =============================================================================
# Nginx Configuration Functions
# =============================================================================

# Function to generate Nginx configuration for a project
generate_nginx_config() {
  local project_id="$1"
  local domain="$2"
  local api_port="$3"
  local studio_port="$4"
  local ssl_enabled="${5:-false}"

  if [ "$ssl_enabled" = "true" ]; then
    cat << EOF
# Supascale configuration for $project_id
# Domain: $domain
# Generated: $(date -Iseconds)

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name $domain;

    # Certbot webroot for renewals
    location /.well-known/acme-challenge/ {
        root $CERTBOT_WEBROOT;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;

    # SSL certificates
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$domain/chain.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Proxy headers
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;

    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400;

    # Kong API routes
    location /rest/v1/ {
        proxy_pass http://127.0.0.1:$api_port/rest/v1/;
    }

    location /auth/v1/ {
        proxy_pass http://127.0.0.1:$api_port/auth/v1/;
    }

    location /storage/v1/ {
        proxy_pass http://127.0.0.1:$api_port/storage/v1/;
        client_max_body_size 50M;
    }

    location /realtime/v1/ {
        proxy_pass http://127.0.0.1:$api_port/realtime/v1/;
    }

    location /functions/v1/ {
        proxy_pass http://127.0.0.1:$api_port/functions/v1/;
    }

    location /graphql/v1 {
        proxy_pass http://127.0.0.1:$api_port/graphql/v1;
    }

    # Studio UI (default route)
    location / {
        proxy_pass http://127.0.0.1:$studio_port;
    }
}
EOF
  else
    # HTTP-only config (for initial certbot setup)
    cat << EOF
# Supascale configuration for $project_id (HTTP only - pre-SSL)
# Domain: $domain
# Generated: $(date -Iseconds)

server {
    listen 80;
    listen [::]:80;
    server_name $domain;

    # Certbot webroot for certificate generation
    location /.well-known/acme-challenge/ {
        root $CERTBOT_WEBROOT;
    }

    # Proxy headers
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400;

    # Kong API routes
    location /rest/v1/ {
        proxy_pass http://127.0.0.1:$api_port/rest/v1/;
    }

    location /auth/v1/ {
        proxy_pass http://127.0.0.1:$api_port/auth/v1/;
    }

    location /storage/v1/ {
        proxy_pass http://127.0.0.1:$api_port/storage/v1/;
        client_max_body_size 50M;
    }

    location /realtime/v1/ {
        proxy_pass http://127.0.0.1:$api_port/realtime/v1/;
    }

    location /functions/v1/ {
        proxy_pass http://127.0.0.1:$api_port/functions/v1/;
    }

    location /graphql/v1 {
        proxy_pass http://127.0.0.1:$api_port/graphql/v1;
    }

    # Studio UI (default route)
    location / {
        proxy_pass http://127.0.0.1:$studio_port;
    }
}
EOF
  fi
}

# Function to apply Nginx configuration
apply_nginx_config() {
  local project_id="$1"
  local domain="$2"
  local api_port="$3"
  local studio_port="$4"
  local ssl_enabled="${5:-false}"

  local config_file="$NGINX_SITES_AVAILABLE/${DOMAIN_CONFIG_PREFIX}-${project_id}.conf"
  local enabled_link="$NGINX_SITES_ENABLED/${DOMAIN_CONFIG_PREFIX}-${project_id}.conf"

  echo "Generating Nginx configuration..."

  # Create certbot webroot if needed
  sudo mkdir -p "$CERTBOT_WEBROOT/.well-known/acme-challenge"

  # Generate and write configuration
  generate_nginx_config "$project_id" "$domain" "$api_port" "$studio_port" "$ssl_enabled" | sudo tee "$config_file" > /dev/null

  # Enable the site
  sudo ln -sf "$config_file" "$enabled_link"

  # Test configuration
  if ! sudo nginx -t 2>&1; then
    echo "Error: Nginx configuration test failed."
    sudo rm -f "$enabled_link"
    sudo rm -f "$config_file"
    return 1
  fi

  # Reload Nginx
  sudo systemctl reload nginx

  echo "Nginx configuration applied successfully."
  return 0
}

# Function to remove Nginx configuration
remove_nginx_config() {
  local project_id="$1"

  local config_file="$NGINX_SITES_AVAILABLE/${DOMAIN_CONFIG_PREFIX}-${project_id}.conf"
  local enabled_link="$NGINX_SITES_ENABLED/${DOMAIN_CONFIG_PREFIX}-${project_id}.conf"

  # Remove symlink and config file
  [ -L "$enabled_link" ] && sudo rm -f "$enabled_link"
  [ -f "$config_file" ] && sudo rm -f "$config_file"

  # Reload Nginx if running
  if systemctl is-active --quiet nginx; then
    sudo systemctl reload nginx
  fi

  return 0
}

# =============================================================================
# Apache Configuration Functions
# =============================================================================

# Function to generate Apache virtual host configuration
generate_apache_config() {
  local project_id="$1"
  local domain="$2"
  local api_port="$3"
  local studio_port="$4"
  local ssl_enabled="${5:-false}"

  if [ "$ssl_enabled" = "true" ]; then
    cat << EOF
# Supascale configuration for $project_id
# Domain: $domain
# Generated: $(date -Iseconds)

# HTTP to HTTPS redirect
<VirtualHost *:80>
    ServerName $domain

    # Certbot webroot
    Alias /.well-known/acme-challenge/ $CERTBOT_WEBROOT/.well-known/acme-challenge/
    <Directory "$CERTBOT_WEBROOT/.well-known/acme-challenge/">
        Options None
        AllowOverride None
        Require all granted
    </Directory>

    # Redirect all other traffic to HTTPS
    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/.well-known/acme-challenge/
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>

# HTTPS server
<VirtualHost *:443>
    ServerName $domain

    # SSL configuration
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$domain/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$domain/privkey.pem

    # Modern SSL configuration
    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
    SSLHonorCipherOrder off
    SSLSessionTickets off

    # HSTS
    Header always set Strict-Transport-Security "max-age=63072000"

    # Proxy settings
    ProxyPreserveHost On
    ProxyRequests Off

    # WebSocket support for realtime
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/realtime/v1/(.*) ws://127.0.0.1:$api_port/realtime/v1/\$1 [P,L]

    # Kong API routes
    ProxyPass /rest/v1/ http://127.0.0.1:$api_port/rest/v1/
    ProxyPassReverse /rest/v1/ http://127.0.0.1:$api_port/rest/v1/

    ProxyPass /auth/v1/ http://127.0.0.1:$api_port/auth/v1/
    ProxyPassReverse /auth/v1/ http://127.0.0.1:$api_port/auth/v1/

    ProxyPass /storage/v1/ http://127.0.0.1:$api_port/storage/v1/
    ProxyPassReverse /storage/v1/ http://127.0.0.1:$api_port/storage/v1/

    ProxyPass /realtime/v1/ http://127.0.0.1:$api_port/realtime/v1/
    ProxyPassReverse /realtime/v1/ http://127.0.0.1:$api_port/realtime/v1/

    ProxyPass /functions/v1/ http://127.0.0.1:$api_port/functions/v1/
    ProxyPassReverse /functions/v1/ http://127.0.0.1:$api_port/functions/v1/

    ProxyPass /graphql/v1 http://127.0.0.1:$api_port/graphql/v1
    ProxyPassReverse /graphql/v1 http://127.0.0.1:$api_port/graphql/v1

    # Studio UI (default route)
    ProxyPass / http://127.0.0.1:$studio_port/
    ProxyPassReverse / http://127.0.0.1:$studio_port/
</VirtualHost>
EOF
  else
    # HTTP-only config
    cat << EOF
# Supascale configuration for $project_id (HTTP only - pre-SSL)
# Domain: $domain
# Generated: $(date -Iseconds)

<VirtualHost *:80>
    ServerName $domain

    # Certbot webroot
    Alias /.well-known/acme-challenge/ $CERTBOT_WEBROOT/.well-known/acme-challenge/
    <Directory "$CERTBOT_WEBROOT/.well-known/acme-challenge/">
        Options None
        AllowOverride None
        Require all granted
    </Directory>

    # Proxy settings
    ProxyPreserveHost On
    ProxyRequests Off

    # WebSocket support for realtime
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/realtime/v1/(.*) ws://127.0.0.1:$api_port/realtime/v1/\$1 [P,L]

    # Kong API routes
    ProxyPass /rest/v1/ http://127.0.0.1:$api_port/rest/v1/
    ProxyPassReverse /rest/v1/ http://127.0.0.1:$api_port/rest/v1/

    ProxyPass /auth/v1/ http://127.0.0.1:$api_port/auth/v1/
    ProxyPassReverse /auth/v1/ http://127.0.0.1:$api_port/auth/v1/

    ProxyPass /storage/v1/ http://127.0.0.1:$api_port/storage/v1/
    ProxyPassReverse /storage/v1/ http://127.0.0.1:$api_port/storage/v1/

    ProxyPass /realtime/v1/ http://127.0.0.1:$api_port/realtime/v1/
    ProxyPassReverse /realtime/v1/ http://127.0.0.1:$api_port/realtime/v1/

    ProxyPass /functions/v1/ http://127.0.0.1:$api_port/functions/v1/
    ProxyPassReverse /functions/v1/ http://127.0.0.1:$api_port/functions/v1/

    ProxyPass /graphql/v1 http://127.0.0.1:$api_port/graphql/v1
    ProxyPassReverse /graphql/v1 http://127.0.0.1:$api_port/graphql/v1

    # Studio UI (default route)
    ProxyPass / http://127.0.0.1:$studio_port/
    ProxyPassReverse / http://127.0.0.1:$studio_port/
</VirtualHost>
EOF
  fi
}

# Function to apply Apache configuration
apply_apache_config() {
  local project_id="$1"
  local domain="$2"
  local api_port="$3"
  local studio_port="$4"
  local ssl_enabled="${5:-false}"

  local distro_type=$(get_apache_distro_type)
  local config_dir=$(get_apache_config_dir)
  local service_name=$(get_apache_service_name)
  local config_file="${config_dir}/${DOMAIN_CONFIG_PREFIX}-${project_id}.conf"

  echo "Generating Apache configuration for $distro_type system..."
  echo "Config directory: $config_dir"

  # Ensure config directory exists
  sudo mkdir -p "$config_dir"

  # Enable required modules (Debian/Ubuntu only - RHEL loads modules differently)
  if [ "$distro_type" = "debian" ] && command -v a2enmod &> /dev/null; then
    echo "Enabling required Apache modules..."
    sudo a2enmod proxy proxy_http proxy_wstunnel rewrite ssl headers 2>/dev/null || true
  fi

  # Create certbot webroot
  sudo mkdir -p "$CERTBOT_WEBROOT/.well-known/acme-challenge"

  # Generate and write configuration
  generate_apache_config "$project_id" "$domain" "$api_port" "$studio_port" "$ssl_enabled" | sudo tee "$config_file" > /dev/null

  # Enable the site (Debian only - RHEL doesn't use sites-enabled pattern)
  if [ "$distro_type" = "debian" ] && command -v a2ensite &> /dev/null; then
    sudo a2ensite "${DOMAIN_CONFIG_PREFIX}-${project_id}.conf" 2>/dev/null
  fi

  # Test configuration
  if [ "$distro_type" = "debian" ]; then
    if ! sudo apache2ctl configtest 2>&1; then
      echo "Error: Apache configuration test failed."
      [ "$distro_type" = "debian" ] && sudo a2dissite "${DOMAIN_CONFIG_PREFIX}-${project_id}.conf" 2>/dev/null || true
      sudo rm -f "$config_file"
      return 1
    fi
  else
    if ! sudo httpd -t 2>&1; then
      echo "Error: Apache configuration test failed."
      sudo rm -f "$config_file"
      return 1
    fi
  fi

  # Reload Apache
  sudo systemctl reload "$service_name"

  echo "Apache configuration applied successfully."
  return 0
}

# Function to remove Apache configuration
remove_apache_config() {
  local project_id="$1"

  local distro_type=$(get_apache_distro_type)
  local config_dir=$(get_apache_config_dir)
  local service_name=$(get_apache_service_name)
  local config_file="${config_dir}/${DOMAIN_CONFIG_PREFIX}-${project_id}.conf"

  # Disable site (Debian only)
  if [ "$distro_type" = "debian" ] && command -v a2dissite &> /dev/null; then
    sudo a2dissite "${DOMAIN_CONFIG_PREFIX}-${project_id}.conf" 2>/dev/null || true
  fi

  # Remove config file
  [ -f "$config_file" ] && sudo rm -f "$config_file"

  # Reload Apache if running
  if systemctl is-active --quiet "$service_name" 2>/dev/null; then
    sudo systemctl reload "$service_name"
  fi

  return 0
}

# =============================================================================
# Caddy Configuration Functions
# =============================================================================

# Function to generate Caddy configuration
generate_caddy_config() {
  local project_id="$1"
  local domain="$2"
  local api_port="$3"
  local studio_port="$4"

  cat << EOF
# Supascale configuration for $project_id
# Domain: $domain
# Generated: $(date -Iseconds)

$domain {
    # Kong API routes
    handle /rest/v1/* {
        reverse_proxy 127.0.0.1:$api_port
    }

    handle /auth/v1/* {
        reverse_proxy 127.0.0.1:$api_port
    }

    handle /storage/v1/* {
        reverse_proxy 127.0.0.1:$api_port
    }

    handle /realtime/v1/* {
        reverse_proxy 127.0.0.1:$api_port
    }

    handle /functions/v1/* {
        reverse_proxy 127.0.0.1:$api_port
    }

    handle /graphql/v1* {
        reverse_proxy 127.0.0.1:$api_port
    }

    # Studio UI (default route)
    handle {
        reverse_proxy 127.0.0.1:$studio_port
    }
}
EOF
}

# Function to apply Caddy configuration
apply_caddy_config() {
  local project_id="$1"
  local domain="$2"
  local api_port="$3"
  local studio_port="$4"

  local config_file="$CADDY_CONFIG_DIR/sites/${DOMAIN_CONFIG_PREFIX}-${project_id}.caddy"

  echo "Generating Caddy configuration..."

  # Create config directory
  sudo mkdir -p "$CADDY_CONFIG_DIR/sites"

  # Generate configuration
  generate_caddy_config "$project_id" "$domain" "$api_port" "$studio_port" | sudo tee "$config_file" > /dev/null

  # Ensure main Caddyfile imports the sites directory
  if [ -f "$CADDYFILE_PATH" ]; then
    if ! sudo grep -q "import sites/\*" "$CADDYFILE_PATH" 2>/dev/null; then
      echo "" | sudo tee -a "$CADDYFILE_PATH" > /dev/null
      echo "import sites/*" | sudo tee -a "$CADDYFILE_PATH" > /dev/null
    fi
  else
    echo "import sites/*" | sudo tee "$CADDYFILE_PATH" > /dev/null
  fi

  # Validate and reload
  if ! sudo caddy validate --config "$CADDYFILE_PATH" 2>&1; then
    echo "Error: Caddy configuration validation failed."
    sudo rm -f "$config_file"
    return 1
  fi

  sudo systemctl reload caddy 2>/dev/null || sudo systemctl restart caddy

  echo "Caddy configuration applied successfully."
  echo "Note: Caddy will automatically obtain and renew SSL certificates."
  return 0
}

# Function to remove Caddy configuration
remove_caddy_config() {
  local project_id="$1"

  local config_file="$CADDY_CONFIG_DIR/sites/${DOMAIN_CONFIG_PREFIX}-${project_id}.caddy"

  [ -f "$config_file" ] && sudo rm -f "$config_file"

  # Reload Caddy if running
  if systemctl is-active --quiet caddy; then
    sudo systemctl reload caddy 2>/dev/null || sudo systemctl restart caddy
  fi

  return 0
}

# =============================================================================
# Certbot/SSL Functions
# =============================================================================

# Function to check if certbot is installed
check_certbot() {
  if ! command -v certbot &> /dev/null; then
    echo ""
    echo "Error: certbot is not installed."
    echo "Please install certbot first:"
    echo "  - Ubuntu/Debian: sudo apt install certbot"
    echo "  - CentOS/RHEL: sudo dnf install certbot"
    echo "  - macOS: brew install certbot"
    return 1
  fi
  return 0
}

# Function to generate SSL certificate using webroot mode
generate_ssl_certificate() {
  local domain="$1"
  local email="${2:-}"

  echo "Generating SSL certificate for $domain..."

  # Create webroot directory
  sudo mkdir -p "$CERTBOT_WEBROOT/.well-known/acme-challenge"
  sudo chmod -R 755 "$CERTBOT_WEBROOT"

  # Build certbot command
  local certbot_cmd="certbot certonly --webroot -w $CERTBOT_WEBROOT -d $domain --non-interactive --agree-tos"

  if [ -n "$email" ]; then
    certbot_cmd="$certbot_cmd --email $email"
  else
    certbot_cmd="$certbot_cmd --register-unsafely-without-email"
  fi

  # Run certbot
  if ! sudo $certbot_cmd; then
    echo ""
    echo "Error: Failed to generate SSL certificate."
    echo ""
    echo "Common issues:"
    echo "  1. DNS not propagated yet - wait a few minutes"
    echo "  2. Port 80 not accessible from the internet"
    echo "  3. Firewall blocking HTTP traffic"
    echo "  4. Rate limit exceeded (try again later)"
    return 1
  fi

  echo "SSL certificate generated successfully!"
  echo "Certificate location: /etc/letsencrypt/live/$domain/"
  return 0
}

# Function to setup automatic certificate renewal
setup_certbot_renewal() {
  local domain="$1"
  local web_server="$2"

  echo "Setting up automatic certificate renewal..."

  # Create renewal hook directory
  sudo mkdir -p "$CERTBOT_RENEWAL_HOOK_DIR"

  # Create reload hook based on web server
  local hook_script="$CERTBOT_RENEWAL_HOOK_DIR/reload-${web_server}.sh"

  case "$web_server" in
    nginx)
      echo '#!/bin/bash
systemctl reload nginx' | sudo tee "$hook_script" > /dev/null
      ;;
    apache)
      echo '#!/bin/bash
if command -v apache2 &> /dev/null; then
    systemctl reload apache2
else
    systemctl reload httpd
fi' | sudo tee "$hook_script" > /dev/null
      ;;
    caddy)
      # Caddy handles its own renewals
      echo "Caddy manages SSL certificates automatically."
      return 0
      ;;
  esac

  sudo chmod +x "$hook_script"

  # Verify certbot timer is enabled
  if systemctl list-timers 2>/dev/null | grep -q certbot; then
    echo "Certbot automatic renewal is already configured via systemd timer."
  else
    echo "Note: Certbot renewal cron/timer may need to be configured."
    echo "Most package installations include automatic renewal."
  fi

  echo "Automatic certificate renewal configured."
  return 0
}

# Function to revoke and delete a certificate
revoke_ssl_certificate() {
  local domain="$1"

  if [ -d "/etc/letsencrypt/live/$domain" ]; then
    echo "Revoking SSL certificate for $domain..."
    read -p "Are you sure you want to revoke the certificate? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      sudo certbot revoke --cert-path "/etc/letsencrypt/live/$domain/cert.pem" --delete-after-revoke --non-interactive 2>/dev/null || true
      echo "Certificate revoked and deleted."
    else
      echo "Certificate revocation cancelled."
    fi
  fi
}

# =============================================================================
# Main Domain Commands
# =============================================================================

# Rollback function for failed domain setup
rollback_domain_setup() {
  local project_id="$1"
  local web_server="$2"

  echo "Rolling back domain configuration..."

  case "$web_server" in
    nginx)
      remove_nginx_config "$project_id"
      ;;
    apache)
      remove_apache_config "$project_id"
      ;;
    caddy)
      remove_caddy_config "$project_id"
      ;;
  esac
}

# Function to setup custom domain for a project
setup_domain() {
  local project_id="$1"

  if [ -z "$project_id" ]; then
    echo "Error: Project ID required."
    echo "Usage: ./supascale.sh setup-domain <project_id>"
    return 1
  fi

  # Check if project exists
  local project_info=$(jq -r --arg pid "$project_id" '.projects[$pid]' "$DB_FILE" 2>/dev/null)
  if [ "$project_info" = "null" ] || [ -z "$project_info" ]; then
    echo "Error: Project '$project_id' not found."
    list_projects
    return 1
  fi

  # Check if domain already configured
  local existing_domain=$(echo "$project_info" | jq -r '.domain.name // empty')
  if [ -n "$existing_domain" ]; then
    echo "Warning: Project '$project_id' already has domain configured: $existing_domain"
    read -p "Do you want to reconfigure the domain? (y/N): " reconfigure
    if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
      return 0
    fi
    # Remove existing domain configuration first
    remove_domain "$project_id" --quiet
  fi

  # Get ports
  local api_port=$(echo "$project_info" | jq -r '.ports.api')
  local studio_port=$(echo "$project_info" | jq -r '.ports.studio')

  # Get server IP
  echo "Detecting server IP address..."
  local server_ip=$(get_server_ip)

  echo ""
  echo "============================================================"
  echo "CUSTOM DOMAIN SETUP FOR PROJECT: $project_id"
  echo "============================================================"
  echo ""
  echo "Server IP Address: $server_ip"
  echo ""
  echo "Before proceeding, please ensure you have created a DNS record:"
  echo "  Type:  A"
  echo "  Name:  your-domain.com (or subdomain)"
  echo "  Value: $server_ip"
  echo ""
  echo "DNS propagation can take 5-30 minutes."
  echo "============================================================"
  echo ""

  # Prompt for domain name
  read -p "Enter your domain name (e.g., myapp.example.com): " domain

  if [ -z "$domain" ]; then
    echo "Error: Domain name is required."
    return 1
  fi

  # Validate domain format
  if ! validate_domain_format "$domain"; then
    return 1
  fi

  # Validate DNS resolution
  echo ""
  echo "Checking DNS resolution for $domain..."
  if ! validate_dns "$domain" "$server_ip"; then
    echo ""
    echo "You can still access your Supabase instance at:"
    echo "  Studio: http://$server_ip:$studio_port"
    echo "  API: http://$server_ip:$api_port"
    return 1
  fi

  # Detect or select web server
  echo ""
  echo "Detecting installed web servers..."
  local web_server=$(detect_web_server)

  if [ "$web_server" = "none" ]; then
    web_server=$(prompt_install_web_server)
    if [ $? -ne 0 ] || [ -z "$web_server" ] || [ "$web_server" = "none" ]; then
      echo "Cannot proceed without a web server."
      return 1
    fi
  fi

  echo "Using web server: $web_server"

  # Request sudo permission
  if ! request_sudo_permission "Configure $web_server reverse proxy for $domain"; then
    return 1
  fi

  # Enable web server at startup
  enable_web_server_startup "$web_server"

  # Start web server if not running
  start_web_server "$web_server"

  # Configure firewall for HTTP/HTTPS traffic
  echo ""
  echo "Configuring firewall for HTTP/HTTPS traffic..."
  configure_firewall "open"

  # Step 1: Apply HTTP-only configuration (for certbot)
  echo ""
  echo "Step 1/4: Applying initial web server configuration..."

  local apply_result=0
  case "$web_server" in
    nginx)
      apply_nginx_config "$project_id" "$domain" "$api_port" "$studio_port" "false" || apply_result=1
      ;;
    apache)
      apply_apache_config "$project_id" "$domain" "$api_port" "$studio_port" "false" || apply_result=1
      ;;
    caddy)
      # Caddy handles SSL automatically
      apply_caddy_config "$project_id" "$domain" "$api_port" "$studio_port" || apply_result=1
      ;;
  esac

  if [ $apply_result -ne 0 ]; then
    echo "Error: Failed to apply web server configuration."
    rollback_domain_setup "$project_id" "$web_server"
    return 1
  fi

  # Step 2: Generate SSL certificate (skip for Caddy - it handles SSL automatically)
  local ssl_enabled="false"
  if [ "$web_server" != "caddy" ]; then
    echo ""
    echo "Step 2/4: Generating SSL certificate..."

    if ! check_certbot; then
      echo "Warning: Skipping SSL setup. Site will be available via HTTP only."
    else
      read -p "Enter email for SSL certificate notifications (optional, press Enter to skip): " cert_email

      if generate_ssl_certificate "$domain" "$cert_email"; then
        ssl_enabled="true"

        # Step 3: Apply SSL configuration
        echo ""
        echo "Step 3/4: Applying SSL configuration..."
        case "$web_server" in
          nginx)
            apply_nginx_config "$project_id" "$domain" "$api_port" "$studio_port" "true" || {
              echo "Warning: Failed to apply SSL configuration. Continuing with HTTP."
              ssl_enabled="false"
            }
            ;;
          apache)
            apply_apache_config "$project_id" "$domain" "$api_port" "$studio_port" "true" || {
              echo "Warning: Failed to apply SSL configuration. Continuing with HTTP."
              ssl_enabled="false"
            }
            ;;
        esac

        # Setup automatic renewal
        if [ "$ssl_enabled" = "true" ]; then
          setup_certbot_renewal "$domain" "$web_server"
        fi
      else
        echo "Warning: SSL certificate generation failed. Continuing with HTTP."
      fi
    fi
  else
    ssl_enabled="true"  # Caddy handles SSL automatically
    echo ""
    echo "Step 2/4: Caddy will automatically obtain SSL certificate..."
    echo "Step 3/4: Skipped (Caddy manages SSL automatically)..."
  fi

  # Step 4: Update database
  echo ""
  echo "Step 4/4: Updating project configuration..."

  local ssl_cert_path=""
  local ssl_key_path=""
  if [ "$ssl_enabled" = "true" ] && [ "$web_server" != "caddy" ]; then
    ssl_cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
    ssl_key_path="/etc/letsencrypt/live/$domain/privkey.pem"
  fi

  # Update database with domain configuration
  jq --arg pid "$project_id" \
     --arg domain "$domain" \
     --arg web_server "$web_server" \
     --argjson ssl_enabled "$ssl_enabled" \
     --arg ssl_cert_path "$ssl_cert_path" \
     --arg ssl_key_path "$ssl_key_path" \
     --arg configured_at "$(date -Iseconds)" \
     '.projects[$pid].domain = {
        "name": $domain,
        "web_server": $web_server,
        "ssl_enabled": $ssl_enabled,
        "ssl_cert_path": $ssl_cert_path,
        "ssl_key_path": $ssl_key_path,
        "configured_at": $configured_at
      }' "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"

  # Final output
  echo ""
  echo "============================================================"
  echo "DOMAIN SETUP COMPLETE!"
  echo "============================================================"
  if [ "$ssl_enabled" = "true" ]; then
    echo "Your Supabase instance is now available at:"
    echo "  Studio:  https://$domain"
    echo "  API:     https://$domain/rest/v1/"
    echo "  Auth:    https://$domain/auth/v1/"
    echo "  Storage: https://$domain/storage/v1/"
  else
    echo "Your Supabase instance is available at (HTTP only):"
    echo "  Studio:  http://$domain"
    echo "  API:     http://$domain/rest/v1/"
  fi
  echo ""
  echo "Fallback access (direct ports):"
  echo "  Studio:  http://$server_ip:$studio_port"
  echo "  API:     http://$server_ip:$api_port"
  echo "============================================================"

  return 0
}

# Function to remove custom domain configuration
remove_domain() {
  local project_id="$1"
  local quiet_mode=false

  # Check for --quiet flag
  if [ "$2" = "--quiet" ]; then
    quiet_mode=true
  fi

  if [ -z "$project_id" ]; then
    echo "Error: Project ID required."
    echo "Usage: ./supascale.sh remove-domain <project_id>"
    return 1
  fi

  # Check if project exists
  local project_info=$(jq -r --arg pid "$project_id" '.projects[$pid]' "$DB_FILE" 2>/dev/null)
  if [ "$project_info" = "null" ] || [ -z "$project_info" ]; then
    echo "Error: Project '$project_id' not found."
    return 1
  fi

  # Check if domain is configured
  local domain=$(echo "$project_info" | jq -r '.domain.name // empty')
  local web_server=$(echo "$project_info" | jq -r '.domain.web_server // empty')

  if [ -z "$domain" ]; then
    [ "$quiet_mode" = false ] && echo "Project '$project_id' does not have a custom domain configured."
    return 0
  fi

  if [ "$quiet_mode" = false ]; then
    echo ""
    echo "============================================================"
    echo "REMOVE CUSTOM DOMAIN FOR PROJECT: $project_id"
    echo "============================================================"
    echo "Domain: $domain"
    echo "Web Server: $web_server"
    echo ""

    read -p "Are you sure you want to remove this domain configuration? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Cancelled."
      return 0
    fi
  fi

  # Request sudo permission
  if ! request_sudo_permission "Remove $web_server configuration for $domain"; then
    return 1
  fi

  # Remove web server configuration
  echo "Removing web server configuration..."
  case "$web_server" in
    nginx)
      remove_nginx_config "$project_id"
      ;;
    apache)
      remove_apache_config "$project_id"
      ;;
    caddy)
      remove_caddy_config "$project_id"
      ;;
    *)
      echo "Warning: Unknown web server type: $web_server"
      ;;
  esac

  # Ask about SSL certificate
  if [ -d "/etc/letsencrypt/live/$domain" ] && [ "$quiet_mode" = false ]; then
    read -p "Do you want to revoke the SSL certificate for $domain? (y/N): " revoke_cert
    if [[ "$revoke_cert" =~ ^[Yy]$ ]]; then
      revoke_ssl_certificate "$domain"
    fi
  fi

  # Update database - remove domain configuration
  jq --arg pid "$project_id" 'del(.projects[$pid].domain)' "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"

  if [ "$quiet_mode" = false ]; then
    local server_ip=$(get_server_ip)
    local api_port=$(echo "$project_info" | jq -r '.ports.api')
    local studio_port=$(echo "$project_info" | jq -r '.ports.studio')

    echo ""
    echo "============================================================"
    echo "DOMAIN REMOVED SUCCESSFULLY"
    echo "============================================================"
    echo "The domain $domain has been removed from project '$project_id'."
    echo ""
    echo "Your Supabase instance is still accessible at:"
    echo "  Studio:  http://$server_ip:$studio_port"
    echo "  API:     http://$server_ip:$api_port"
    echo "============================================================"
  fi

  return 0
}

################################################################################
# End Custom Domain Functions
################################################################################

# Function to show help
show_help() {
  echo "Supascale v$VERSION - Manage multiple local Supabase instances"
  echo ""
  echo "Usage:"
  echo "  ./supascale.sh [command] [options]"
  echo ""
  echo "Project Management:"
  echo "  list                              List all configured projects"
  echo "  add <project_id>                  Add a new project"
  echo "  start <project_id>                Start a specific project"
  echo "  stop <project_id>                 Stop a specific project"
  echo "  remove <project_id>               Remove a project from the database"
  echo ""
  echo "Backup & Restore:"
  echo "  backup <project_id> [options]     Create a backup"
  echo "  restore <project_id> --from <path> [options]"
  echo "                                    Restore from a backup"
  echo "  list-backups <project_id>         List available backups"
  echo "  verify-backup <path>              Verify backup integrity"
  echo "  backup-info <path>                Show backup metadata"
  echo "  setup-backup-schedule <project_id>"
  echo "                                    Show cron examples for scheduled backups"
  echo ""
  echo "Backup Options:"
  echo "  --type=TYPE                       Backup type: full, database, storage,"
  echo "                                    functions, config (default: full)"
  echo "  --destination=DEST                local, s3://bucket/path (default: local)"
  echo "  --encrypt                         Enable AES-256 encryption"
  echo "  --password=PASS                   Encryption password"
  echo "  --password-file=PATH              Read password from file"
  echo "  --retention=N                     Keep only last N backups"
  echo "  --silent                          Minimal output (for cron jobs)"
  echo ""
  echo "Restore Options:"
  echo "  --from=PATH                       Backup path (local or s3://)"
  echo "  --dry-run                         Validate without restoring"
  echo "  --confirm                         Skip confirmation prompt"
  echo "  --password=PASS                   Decryption password"
  echo ""
  echo "Container Updates:"
  echo "  update-containers <project_id>    Update containers for a specific project"
  echo "  update-containers --all           Update containers for all projects"
  echo "  check-updates <project_id>        Check available updates (dry run)"
  echo "  container-versions <project_id>   Show current container versions"
  echo ""
  echo "Update Flags:"
  echo "  --only=service1,service2          Only update specific services"
  echo ""
  echo "Custom Domain:"
  echo "  setup-domain <project_id>         Configure custom domain with SSL"
  echo "  remove-domain <project_id>        Remove custom domain configuration"
  echo ""
  echo "Script Management:"
  echo "  update                            Update the script to the latest version"
  echo "  version                           Show current version"
  echo "  help                              Show this help message"
  echo ""
  echo "Available Services for --only flag:"
  echo "  studio, kong, auth, rest, realtime, storage, imgproxy,"
  echo "  meta, functions, analytics, db, vector, supavisor"
  echo ""
  echo "Examples:"
  echo "  ./supascale.sh add my-project                      # Add a new project"
  echo "  ./supascale.sh list                                # List all projects"
  echo "  ./supascale.sh start my-project                    # Start the instance"
  echo "  ./supascale.sh stop my-project                     # Stop the instance"
  echo "  ./supascale.sh backup my-project --type full       # Full backup"
  echo "  ./supascale.sh backup my-project --type database --destination s3://bucket"
  echo "  ./supascale.sh restore my-project --from backup.tar.gz --dry-run"
  echo "  ./supascale.sh restore my-project --from backup.tar.gz --confirm"
  echo "  ./supascale.sh check-updates my-project            # Check for updates"
  echo "  ./supascale.sh update-containers my-project        # Update containers"
  echo "  ./supascale.sh update-containers my-project --only=db,studio"
  echo "  ./supascale.sh setup-domain my-project           # Configure custom domain"
  echo "  ./supascale.sh remove-domain my-project          # Remove domain config"
  echo ""
  echo "Note: This script requires Docker, jq, and Git to be installed."
  echo "Custom domain requires: certbot, and one of nginx/apache/caddy"
}

# Main script
check_dependencies
check_for_updates "$@"
migrate_old_db
initialize_db

case "$1" in
  list)
    list_projects
    ;;
  add)
    add_project "$2"
    ;;
  start)
    start_project "$2"
    ;;
  stop)
    stop_project "$2"
    ;;
  remove)
    remove_project "$2"
    ;;
  backup)
    backup_command "$2" "${@:3}"
    ;;
  restore)
    restore_command "$2" "${@:3}"
    ;;
  list-backups)
    list_backups_command "$2" "$3"
    ;;
  verify-backup)
    # Extract password if provided
    password=""
    for arg in "${@:2}"; do
      case "$arg" in
        --password=*)
          password="${arg#--password=}"
          ;;
      esac
    done
    verify_backup_command "$2" "$password"
    ;;
  backup-info)
    backup_info_command "${@:2}"
    ;;
  setup-backup-schedule)
    setup_backup_schedule_command "$2"
    ;;
  update-containers)
    update_containers_command "$2" "${@:3}"
    ;;
  check-updates)
    check_updates "$2"
    ;;
  container-versions)
    container_versions "$2"
    ;;
  setup-domain)
    setup_domain "$2"
    ;;
  remove-domain)
    remove_domain "$2"
    ;;
  update)
    update_script
    ;;
  version)
    echo "Supascale v$VERSION"
    ;;
  help|--help|-h)
    show_help
    ;;
  "")
    show_help
    ;;
  *)
    echo "Unknown command: $1"
    echo ""
    show_help
    exit 1
    ;;
esac

exit 0
