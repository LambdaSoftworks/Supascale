load 'helpers/setup'

setup() {
  export FIXTURE_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/tests/fixtures/supabase_docker"
  setup_environment
}

run_add() {
  run "$SCRIPT" add "golden-test"
  [ "$status" -eq 0 ]
  [ -f "$HOME/golden-test/supabase/docker/.env" ]
  [ -f "$HOME/golden-test/supabase/docker/docker-compose.yml" ]
}

assert_env_key_non_empty() {
  local key="$1"
  local value
  value=$(grep -E "^${key}=" "$HOME/golden-test/supabase/docker/.env" | cut -d= -f2-)
  [ -n "$value" ]
}

@test "add: .env contains non-empty POSTGRES_PASSWORD" {
  run_add
  assert_env_key_non_empty "POSTGRES_PASSWORD"
}

@test "add: .env contains non-empty JWT_SECRET" {
  run_add
  assert_env_key_non_empty "JWT_SECRET"
}

@test "add: .env contains non-empty ANON_KEY" {
  run_add
  assert_env_key_non_empty "ANON_KEY"
}

@test "add: .env contains non-empty SERVICE_ROLE_KEY" {
  run_add
  assert_env_key_non_empty "SERVICE_ROLE_KEY"
}

@test "add: .env contains non-empty DASHBOARD_PASSWORD" {
  run_add
  assert_env_key_non_empty "DASHBOARD_PASSWORD"
}

@test "add: .env contains non-empty VAULT_ENC_KEY" {
  run_add
  assert_env_key_non_empty "VAULT_ENC_KEY"
}

@test "add: .env sets DASHBOARD_USERNAME to 'supabase'" {
  local value

  run_add
  value=$(grep '^DASHBOARD_USERNAME=' "$HOME/golden-test/supabase/docker/.env" | cut -d= -f2-)
  [ "$value" = "supabase" ]
}

@test "add: DB record contains api port 54321 for first project" {
  local port

  run_add
  port=$(jq -r '.projects["golden-test"].ports.api' "$HOME/.supascale_database.json")
  [ "$port" = "54321" ]
}

@test "add: DB record contains db port 54322 for first project" {
  local port

  run_add
  port=$(jq -r '.projects["golden-test"].ports.db' "$HOME/.supascale_database.json")
  [ "$port" = "54322" ]
}

@test "add: DB record contains studio port 54323 for first project" {
  local port

  run_add
  port=$(jq -r '.projects["golden-test"].ports.studio' "$HOME/.supascale_database.json")
  [ "$port" = "54323" ]
}

@test "add: last_port_assigned advances by PORT_INCREMENT (1000) after add" {
  local next_port

  run_add
  next_port=$(jq -r '.last_port_assigned' "$HOME/.supascale_database.json")
  [ "$next_port" = "55321" ]
}

@test "add: docker-compose.yml contains api port binding 54321 on :8000" {
  run_add
  grep -qE '54321:8000' "$HOME/golden-test/supabase/docker/docker-compose.yml"
}

@test "add: docker-compose.yml contains db port binding 54322 on :5432" {
  run_add
  grep -qE '54322:5432' "$HOME/golden-test/supabase/docker/docker-compose.yml"
}

@test "add: docker-compose.yml contains studio port binding 54323 on :3000" {
  run_add
  grep -qE '54323:3000' "$HOME/golden-test/supabase/docker/docker-compose.yml"
}

@test "add: docker-compose.yml contains analytics port binding 54327 on :4000" {
  run_add
  grep -qE '54327:4000' "$HOME/golden-test/supabase/docker/docker-compose.yml"
}

@test "add: docker-compose.yml contains inbucket port binding 54324 on :9000" {
  run_add
  grep -qE '54324:9000' "$HOME/golden-test/supabase/docker/docker-compose.yml"
}

@test "add: docker-compose.yml contains kong https port binding 54764 on :8443" {
  run_add
  grep -qE '54764:8443' "$HOME/golden-test/supabase/docker/docker-compose.yml"
}

@test "add: DB record contains all required port keys" {
  local key
  local value

  run_add

  for key in api db shadow studio inbucket smtp pop3 pooler analytics kong_https; do
    value=$(jq -r --arg k "$key" '.projects["golden-test"].ports[$k]' "$HOME/.supascale_database.json")
    [ "$value" != "null" ]
    [ -n "$value" ]
  done
}
