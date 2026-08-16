load 'helpers/setup'
load 'helpers/teardown'

setup() {
  require_integration_enabled
  setup_integration_environment
}

teardown() {
  teardown_project alpha
}

@test "backup, verify-backup, backup-info, and restore complete end-to-end" {
  local backup_dir="$HOME/.supascale_backups/alpha/backups"
  local backup_path
  local backup_matches=()

  run "$SCRIPT" add alpha
  [ "$status" -eq 0 ]

  run "$SCRIPT" start alpha
  [ "$status" -eq 0 ]
  wait_for_healthy 54321

  run "$SCRIPT" backup alpha
  [ "$status" -eq 0 ]
  [ -d "$backup_dir" ]

  shopt -s nullglob
  backup_matches=("$backup_dir"/*.tar.gz)
  shopt -u nullglob
  [ "${#backup_matches[@]}" -ge 1 ]
  backup_path="${backup_matches[0]}"
  [ -n "$backup_path" ]
  [ -f "$backup_path" ]

  run "$SCRIPT" verify-backup "$backup_path"
  [ "$status" -eq 0 ]

  run "$SCRIPT" backup-info "$backup_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Project ID: alpha"* ]]

  run "$SCRIPT" stop alpha
  [ "$status" -eq 0 ]

  run "$SCRIPT" restore alpha --from "$backup_path" --confirm
  [ "$status" -eq 0 ]

  wait_for_healthy 54321
}
