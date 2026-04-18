load 'helpers/setup'

setup() {
  setup_environment
}

@test "no arguments shows help and exits 0" {
  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" =~ [Uu]sage ]]
}

@test "help command exits 0" {
  run "$SCRIPT" help

  [ "$status" -eq 0 ]
}

@test "help output contains Usage section" {
  run "$SCRIPT" help

  [ "$status" -eq 0 ]
  [[ "$output" =~ [Uu]sage ]]
}

@test "help output lists add command" {
  run "$SCRIPT" help

  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "add <project_id>"
}

@test "help output lists backup command" {
  run "$SCRIPT" help

  [ "$status" -eq 0 ]
  echo "$output" | grep -Fq "backup <project_id>"
}

@test "--help flag exits 0" {
  run "$SCRIPT" --help

  [ "$status" -eq 0 ]
}

@test "-h flag exits 0" {
  run "$SCRIPT" -h

  [ "$status" -eq 0 ]
}

@test "version command exits 0" {
  run "$SCRIPT" version

  [ "$status" -eq 0 ]
}

@test "version command prints Supascale v<semver>" {
  run "$SCRIPT" version

  [ "$status" -eq 0 ]
  [[ "$output" =~ Supascale\ v[0-9]+\.[0-9]+\.[0-9]+ ]]
}
