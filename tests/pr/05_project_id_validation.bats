load 'helpers/setup'

setup() {
  setup_environment
}

@test "add with dots currently exits 0 but prints invalid project id" {
  run "$SCRIPT" add "my.project"

  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'invalid|dots|special'
}

@test "add with uppercase letters currently exits 0 but prints invalid project id" {
  run "$SCRIPT" add "MyProject"

  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'invalid|dots|special'
}

@test "add starting with hyphen currently exits 0 but prints invalid project id" {
  run "$SCRIPT" add "-badstart"

  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'invalid|dots|special'
}

@test "add with spaces currently exits 0 but prints invalid project id" {
  run "$SCRIPT" add "my project"

  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'invalid|dots|special'
}

@test "add with special characters currently exits 0 but prints invalid project id" {
  run "$SCRIPT" add "my@project"

  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq 'invalid|dots|special'
}
