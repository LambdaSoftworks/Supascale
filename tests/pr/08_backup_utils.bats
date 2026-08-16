load 'helpers/setup'

setup() {
  setup_environment
}

@test "verify-backup on non-existent file currently exits 0 but prints not found" {
  run "$SCRIPT" verify-backup "/tmp/does_not_exist.tar.gz"

  [ "$status" -eq 0 ]
  echo "$output" | grep -iq 'not found'
}

@test "backup-info on non-existent file currently exits 0 but prints not found" {
  run "$SCRIPT" backup-info "/tmp/does_not_exist.tar.gz"

  [ "$status" -eq 0 ]
  echo "$output" | grep -iq 'not found'
}

@test "restore without --from currently exits 0 but prints required flag error" {
  cat > "$HOME/.supascale_database.json" <<'EOF'
{
  "projects": {
    "known-project": {
      "directory": "/tmp/known-project",
      "ports": {
        "api": 54321,
        "db": 54322,
        "studio": 54323
      }
    }
  },
  "last_port_assigned": 54321
}
EOF

  run "$SCRIPT" restore "known-project"

  [ "$status" -eq 0 ]
  echo "$output" | grep -Eiq -- '--from|required'
}
