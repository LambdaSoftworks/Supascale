load 'helpers/setup'
load 'helpers/teardown'

setup() {
  require_integration_enabled
  setup_integration_environment
}

teardown() {
  teardown_project alpha
  teardown_project beta
}

@test "alpha and beta get isolated ports, containers, and compose-scoped logs" {
  local alpha_compose="$HOME/alpha/supabase/docker/docker-compose.yml"
  local beta_compose="$HOME/beta/supabase/docker/docker-compose.yml"
  local env_db="$HOME/.supascale_database.json"
  local alpha_env="$HOME/alpha/supabase/docker/.env"
  local beta_env="$HOME/beta/supabase/docker/.env"
  local alpha_logs
  local beta_logs

  run "$SCRIPT" add alpha
  [ "$status" -eq 0 ]
  run "$SCRIPT" add beta
  [ "$status" -eq 0 ]

  grep -qE 'container_name:[[:space:]]+alpha-' "$alpha_compose"
  grep -qE 'container_name:[[:space:]]+beta-' "$beta_compose"

  [ "$(jq -r '.projects.alpha.ports.api' "$env_db")" = '54321' ]
  [ "$(jq -r '.projects.alpha.ports.studio' "$env_db")" = '54323' ]
  [ "$(jq -r '.projects.alpha.ports.analytics' "$env_db")" = '54327' ]
  [ "$(jq -r '.projects.alpha.ports.kong_https' "$env_db")" = '54764' ]
  [ "$(jq -r '.projects.beta.ports.api' "$env_db")" = '55321' ]
  [ "$(jq -r '.projects.beta.ports.studio' "$env_db")" = '55323' ]
  [ "$(jq -r '.projects.beta.ports.analytics' "$env_db")" = '55327' ]
  [ "$(jq -r '.projects.beta.ports.kong_https' "$env_db")" = '55764' ]

  grep -q '^KONG_HTTP_PORT=54321$' "$alpha_env"
  grep -q '^POSTGRES_PORT=54322$' "$alpha_env"
  grep -q '^KONG_HTTPS_PORT=54764$' "$alpha_env"
  grep -q '^POOLER_PROXY_PORT_TRANSACTION=54329$' "$alpha_env"
  grep -q '^KONG_HTTP_PORT=55321$' "$beta_env"
  grep -q '^POSTGRES_PORT=55322$' "$beta_env"
  grep -q '^KONG_HTTPS_PORT=55764$' "$beta_env"
  grep -q '^POOLER_PROXY_PORT_TRANSACTION=55329$' "$beta_env"

  run "$SCRIPT" start alpha
  [ "$status" -eq 0 ]
  run "$SCRIPT" start beta
  [ "$status" -eq 0 ]

  run docker ps --filter name=alpha- --filter status=running --format '{{.Names}}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  run docker ps --filter name=beta- --filter status=running --format '{{.Names}}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]

  wait_for_healthy 54321
  wait_for_healthy 55321

  run "$SCRIPT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Project ID: alpha"* ]]
  [[ "$output" == *"Project ID: beta"* ]]

  alpha_logs=$(docker compose -f "$alpha_compose" --project-name alpha logs --no-color 2>&1)
  beta_logs=$(docker compose -f "$beta_compose" --project-name beta logs --no-color 2>&1)

  [ -n "$alpha_logs" ]
  [ -n "$beta_logs" ]

  grep -q 'alpha-' <<<"$alpha_logs"
  grep -q 'beta-' <<<"$beta_logs"
  ! grep -q 'beta-' <<<"$alpha_logs"
  ! grep -q 'alpha-' <<<"$beta_logs"
}
