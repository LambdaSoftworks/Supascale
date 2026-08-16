load 'helpers/setup'
load 'helpers/teardown'

setup() {
  require_integration_enabled
  setup_integration_environment
}

teardown() {
  teardown_project alpha
}

@test "stop tears down alpha and start recreates it successfully" {
  # stop invokes `docker compose down -v`, so volumes are destroyed.
  # This test verifies tear-down and successful recreation, not soft-stop/resume.
  run "$SCRIPT" add alpha
  [ "$status" -eq 0 ]

  run "$SCRIPT" start alpha
  [ "$status" -eq 0 ]
  wait_for_healthy 54321

  run "$SCRIPT" stop alpha
  [ "$status" -eq 0 ]

  run docker ps --filter name=alpha- --filter status=running --format '{{.ID}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run "$SCRIPT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Project ID: alpha"* ]]

  run "$SCRIPT" start alpha
  [ "$status" -eq 0 ]
  wait_for_healthy 54321

  run docker ps --filter name=alpha- --filter status=running --format '{{.Names}}'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
