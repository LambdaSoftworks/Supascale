load 'helpers/setup'

setup() {
  setup_environment
}

@test "add with no project_id currently exits 0 but prints an error" {
  run "$SCRIPT" add
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "add with no project_id prints usage" {
  run "$SCRIPT" add
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "start with no project_id currently exits 0 but prints an error" {
  run "$SCRIPT" start
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "stop with no project_id currently exits 0 but prints an error" {
  run "$SCRIPT" stop
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "remove with no project_id currently exits 0 but prints an error" {
  run "$SCRIPT" remove
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "backup with no project_id currently exits 0 but prints an error" {
  run "$SCRIPT" backup
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "restore with no project_id currently exits 0 but prints an error" {
  run "$SCRIPT" restore
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "check-updates with no project_id currently exits 0 but prints an error" {
  run "$SCRIPT" check-updates
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "container-versions with no project_id currently exits 0 but prints an error" {
  run "$SCRIPT" container-versions
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "update-containers with no project_id and no --all currently exits 0 but prints an error" {
  run "$SCRIPT" update-containers
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "setup-domain with no project_id currently exits 0 but prints an error" {
  run "$SCRIPT" setup-domain
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "remove-domain with no project_id currently exits 0 but prints an error" {
  run "$SCRIPT" remove-domain
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "list-backups with no project_id currently exits 0 but prints an error" {
  run "$SCRIPT" list-backups
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "verify-backup with no path currently exits 0 but prints an error" {
  run "$SCRIPT" verify-backup
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "backup-info with no path currently exits 0 but prints an error" {
  run "$SCRIPT" backup-info
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}

@test "setup-backup-schedule with no project_id currently exits 0 but prints an error" {
  run "$SCRIPT" setup-backup-schedule
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'usage|required'
}
