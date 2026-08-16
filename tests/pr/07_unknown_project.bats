load 'helpers/setup'

setup() {
  setup_environment
}

@test "start on unknown project currently exits 0 but prints not found" {
  run "$SCRIPT" start "ghost-project"
  [ "$status" -eq 0 ]
  echo "$output" | grep -iq 'not found'
}

@test "stop on unknown project currently exits 0 but prints not found" {
  run "$SCRIPT" stop "ghost-project"
  [ "$status" -eq 0 ]
  echo "$output" | grep -iq 'not found'
}

@test "backup on unknown project currently exits 0 but prints not found" {
  run "$SCRIPT" backup "ghost-project"
  [ "$status" -eq 0 ]
  echo "$output" | grep -iq 'not found'
}

@test "restore on unknown project currently exits 0 but prints not found" {
  run "$SCRIPT" restore "ghost-project" --from "/tmp/fake.tar.gz"
  [ "$status" -eq 0 ]
  echo "$output" | grep -iq 'not found'
}

@test "check-updates on unknown project currently exits 0 but prints not found" {
  run "$SCRIPT" check-updates "ghost-project"
  [ "$status" -eq 0 ]
  echo "$output" | grep -iq 'not found'
}

@test "container-versions on unknown project currently exits 0 but prints not found" {
  run "$SCRIPT" container-versions "ghost-project"
  [ "$status" -eq 0 ]
  echo "$output" | grep -iq 'not found'
}

@test "setup-domain on unknown project currently exits 0 but prints not found" {
  run "$SCRIPT" setup-domain "ghost-project"
  [ "$status" -eq 0 ]
  echo "$output" | grep -iq 'not found'
}

@test "remove-domain on unknown project currently exits 0 but prints not found" {
  run "$SCRIPT" remove-domain "ghost-project"
  [ "$status" -eq 0 ]
  echo "$output" | grep -iq 'not found'
}
