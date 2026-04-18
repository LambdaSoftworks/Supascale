load 'helpers/setup'
load 'helpers/teardown'

setup() {
  require_integration_enabled
  setup_integration_environment
}

teardown() {
  teardown_project alpha
}

@test "add alpha provisions files, ports, containers, and list output" {
  local env_file="$HOME/alpha/supabase/docker/.env"
  local compose_file="$HOME/alpha/supabase/docker/docker-compose.yml"

  run "$SCRIPT" add alpha
  [ "$status" -eq 0 ]

  [ -f "$env_file" ]
  [ -f "$compose_file" ]

  for key in POSTGRES_PASSWORD JWT_SECRET ANON_KEY SERVICE_ROLE_KEY DASHBOARD_PASSWORD VAULT_ENC_KEY; do
    assert_env_key_non_empty "$env_file" "$key"
  done

  grep -q '^DASHBOARD_USERNAME=supabase$' "$env_file"

  grep -q '^KONG_HTTP_PORT=54321$' "$env_file"
  grep -q '^POSTGRES_PORT=54322$' "$env_file"
  grep -q '^KONG_HTTPS_PORT=54764$' "$env_file"
  grep -q '^POOLER_PROXY_PORT_TRANSACTION=54329$' "$env_file"

  grep -qE 'container_name:[[:space:]]+alpha-' "$compose_file"
  grep -q '\${KONG_HTTP_PORT}:8000/tcp' "$compose_file"
  grep -q '\${KONG_HTTPS_PORT}:8443/tcp' "$compose_file"
  grep -q '\${POSTGRES_PORT}:5432' "$compose_file"

  [ "$(jq -r '.projects.alpha.ports.studio' "$HOME/.supascale_database.json")" = '54323' ]
  [ "$(jq -r '.projects.alpha.ports.analytics' "$HOME/.supascale_database.json")" = '54327' ]

  run "$SCRIPT" start alpha
  [ "$status" -eq 0 ]

  run docker ps --filter name=alpha- --filter status=running --format '{{.Names}}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  wait_for_healthy 54321

  run "$SCRIPT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Project ID: alpha"* ]]
}
