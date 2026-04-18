load 'helpers/setup'

setup() {
  setup_environment
}

@test "list exits 0 with empty DB" {
  run "$SCRIPT" list

  [ "$status" -eq 0 ]
}

@test "list prints no-projects message with empty DB" {
  run "$SCRIPT" list

  [ "$status" -eq 0 ]
  [[ "$output" =~ [Nn]o\ projects ]]
}
