setup_integration_environment() {
	local docker_config_dir="${DOCKER_CONFIG:-$HOME/.docker}"

	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	export LANG=C
	export LC_ALL=C
	export DOCKER_CONFIG="$docker_config_dir"

	echo "$(date +%s)" >"$HOME/.supascale_last_check"

	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	mkdir -p "$BATS_TEST_TMPDIR/bin"

	cat >"$BATS_TEST_TMPDIR/bin/git" <<'EOF'
#!/bin/bash
echo "git $*" >> "$BATS_TEST_TMPDIR/git_calls.log"
if [[ "$1" == "clone" ]]; then
  dest="${@: -1}"
  mkdir -p "$dest"
  cp -R "/Users/ericzhou03/Projects/supabase/." "$dest/"
  rm -rf "$dest/.git"
  rm -rf "$dest/docker/.env"
  rm -rf "$dest/docker/volumes/db/data"
  rm -rf "$dest/docker/volumes/storage"
  rm -rf "$dest/docker/volumes/functions"
fi
exit 0
EOF

	cat >"$BATS_TEST_TMPDIR/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF

	local script_target="${SUPASCALE:-$BATS_TEST_DIRNAME/../../supascale.sh}"

	cat >"$BATS_TEST_TMPDIR/bin/supascale-under-test" <<EOF
#!/bin/bash
exec bash "$script_target" "\$@" </dev/null
EOF

	chmod +x "$BATS_TEST_TMPDIR/bin/"*
	export SCRIPT="$BATS_TEST_TMPDIR/bin/supascale-under-test"
}

require_integration_enabled() {
	[ -n "$SUPASCALE_INTEGRATION" ] || skip "set SUPASCALE_INTEGRATION=1 to run integration tests"
}

wait_for_healthy() {
	local port="$1"
	local timeout="${2:-300}"
	local interval=5
	local elapsed=0
	local status_code

	while true; do
		status_code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/health" || true)
		if [ "$status_code" = "200" ] || [ "$status_code" = "401" ]; then
			return 0
		fi

		sleep "$interval"
		elapsed=$((elapsed + interval))
		[ "$elapsed" -lt "$timeout" ] || return 1
	done
}

assert_env_key_non_empty() {
	local env_file="$1"
	local key="$2"
	local value

	value=$(grep -E "^${key}=" "$env_file" | cut -d= -f2-)
	[ -n "$value" ]
}
