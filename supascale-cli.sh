#!/bin/bash

################################################################################
# Supascale
# Original Development: Lambda Softworks - https://www.lambdasoftworks.com
#
# MIT License
#
# Copyright (c) 2025 Lambda Softworks
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
# ports and configuration files.
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
# 6. Dependency Check:
#    - Verifies that `jq` (JSON processor) is installed.
# 7. Database Initialization:
#    - Creates the central JSON configuration file if it doesn't exist.
################################################################################

# Supascale - Script Content Starts Below

# Configuration
VERSION="1.2.9"
GITHUB_RAW_URL="https://raw.githubusercontent.com/LambdaSoftworks/supascale/main/supascale.sh"
UPDATE_CHECK_FILE="$HOME/.supascale_last_check"
DB_FILE="$HOME/.supascale_database.json"
BASE_PORT=54321  # Default starting port for Supabase services
PORT_INCREMENT=1000  # How much to increment for a new project's port range

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
  jq -r '.projects | to_entries[] | "Project ID: \(.key)\n  API Port: \(.value.ports.api)\n  DB Port: \(.value.ports.db)\n  Studio Port: \(.value.ports.studio)\n  Directory: \(.value.directory)\n"' "$DB_FILE"
}

# Function to generate a random password (alphanumeric, 40 chars)
generate_password() {
  # Use /dev/urandom, filter for alphanumeric, take first 40 chars
  tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 40
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
  local project_id directory postgres_password jwt_secret anon_key_placeholder service_key_placeholder docker_env_file

  # Prompt for project ID
  read -p "Enter project ID (lowercase alphanumeric, hyphens, underscores only): " project_id

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
  local vault_enc_key=$(generate_password)

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
  echo "  Studio URL: http://$host_ip:$api_port"
  echo "  API URL: http://$host_ip:$api_port/rest/v1/"
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

# Function to show help
show_help() {
  echo "Supascale CLI v$VERSION - Manage multiple local Supabase instances"
  echo ""
  echo "Usage:"
  echo "  ./supascale.sh [command] [options]"
  echo ""
  echo "Commands:"
  echo "  list                    List all configured projects"
  echo "  add                     Add a new project"
  echo "  start <project_id>      Start a specific project"
  echo "  stop <project_id>       Stop a specific project"
  echo "  remove <project_id>     Remove a project from the database"
  echo "  update                  Update the script to the latest version"
  echo "  version                 Show current version"
  echo "  help                    Show this help message"
  echo ""
  echo "Examples:"
  echo "  ./supascale.sh add                    # Add a new project"
  echo "  ./supascale.sh list                   # List all projects"
  echo "  ./supascale.sh start my-project       # Start the 'my-project' instance"
  echo "  ./supascale.sh stop my-project        # Stop the 'my-project' instance"
  echo ""
  echo "Note: This script requires the Supabase CLI to be installed and in your PATH."
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
    add_project
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
  update)
    update_script
    ;;
  version)
    echo "Supascale CLI v$VERSION"
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
