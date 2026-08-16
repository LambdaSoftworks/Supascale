setup_environment() {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	export LANG=C
	export LC_ALL=C

	echo "$(date +%s)" >"$HOME/.supascale_last_check"

	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	mkdir -p "$BATS_TEST_TMPDIR/bin"

	cat >"$BATS_TEST_TMPDIR/bin/docker" <<'EOF'
#!/bin/bash
echo "docker $*" >> "$BATS_TEST_TMPDIR/docker_calls.log"
exit 0
EOF

	cat >"$BATS_TEST_TMPDIR/bin/git" <<'EOF'
#!/bin/bash
echo "git $*" >> "$BATS_TEST_TMPDIR/git_calls.log"
if [[ "$1" == "clone" ]]; then
  dest="${@: -1}"
  mkdir -p "$dest/docker"
  if [[ -n "$FIXTURE_DIR" && -d "$FIXTURE_DIR" ]]; then
    cp -r "$FIXTURE_DIR/." "$dest/docker/"
  else
    touch "$dest/docker/.env.example"
    touch "$dest/docker/docker-compose.yml"
  fi
fi
exit 0
EOF

	cat >"$BATS_TEST_TMPDIR/bin/curl" <<'EOF'
#!/bin/bash
exit 1
EOF

	cat >"$BATS_TEST_TMPDIR/bin/wget" <<'EOF'
#!/bin/bash
exit 1
EOF

	cat >"$BATS_TEST_TMPDIR/bin/aws" <<'EOF'
#!/bin/bash
exit 1
EOF

	cat >"$BATS_TEST_TMPDIR/bin/sudo" <<'EOF'
#!/bin/bash
"$@"
EOF

	chmod +x "$BATS_TEST_TMPDIR/bin/"*

	local script_target="${SUPASCALE:-$BATS_TEST_DIRNAME/../../supascale.sh}"

	cat >"$BATS_TEST_TMPDIR/bin/supascale-under-test" <<EOF
#!/bin/bash
# Redirect stdin from /dev/null so interactive read -p prompts in the script
# (e.g. custom-domain and start-now in add_project) return immediately with
# an empty string instead of blocking the test runner indefinitely.
exec bash "$script_target" "\$@" </dev/null
EOF

	chmod +x "$BATS_TEST_TMPDIR/bin/supascale-under-test"
	export SCRIPT="$BATS_TEST_TMPDIR/bin/supascale-under-test"
}
