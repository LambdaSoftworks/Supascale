load 'helpers/setup'

setup() {
  setup_environment
}

@test "running list creates DB file under isolated HOME" {
  run "$SCRIPT" list

  [ "$status" -eq 0 ]
  [ -f "$HOME/.supascale_database.json" ]
}

@test "DB file contains valid JSON after first run" {
  run "$SCRIPT" list
  [ "$status" -eq 0 ]

  run jq '.' "$HOME/.supascale_database.json"
  [ "$status" -eq 0 ]
}

@test "DB file initializes with empty projects object" {
  run "$SCRIPT" list
  [ "$status" -eq 0 ]

  run jq -c '.projects' "$HOME/.supascale_database.json"
  [ "$status" -eq 0 ]
  [ "$output" = '{}' ]
}

@test "DB file initializes last_port_assigned to BASE_PORT (54321)" {
  run "$SCRIPT" list
  [ "$status" -eq 0 ]

  run jq -r '.last_port_assigned' "$HOME/.supascale_database.json"
  [ "$status" -eq 0 ]
  [ "$output" = '54321' ]
}
