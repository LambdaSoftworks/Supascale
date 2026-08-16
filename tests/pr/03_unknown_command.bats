load 'helpers/setup'

setup() {
  setup_environment
}

@test "unknown command exits non-zero" {
  run "$SCRIPT" notacommand

  [ "$status" -ne 0 ]
}

@test "unknown command prints 'Unknown command' message" {
  run "$SCRIPT" notacommand

  [ "$status" -ne 0 ]
  [[ "$output" =~ [Uu]nknown\ command ]]
}

@test "unknown command still shows help output" {
  run "$SCRIPT" notacommand

  [ "$status" -ne 0 ]
  [[ "$output" =~ [Uu]sage|[Cc]ommands ]]
}
