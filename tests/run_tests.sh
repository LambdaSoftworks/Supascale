#!/usr/bin/env bash
# Unified Bats runner for Supascale test suites.
#
# Default behavior runs the fast unit-style baseline under tests/pr/.
# Integration tests under tests/integration/ are opt-in, require a local Docker
# daemon plus a local Supabase checkout at /Users/ericzhou03/Projects/supabase,
# and are intended for local development rather than CI unless Docker support is
# explicitly provisioned.

set -euo pipefail

BATS=./tests/bats/bin/bats
SUPABASE_REPO=/Users/ericzhou03/Projects/supabase
RUN_UNIT=false
RUN_INTEGRATION=false
BATS_FLAGS=()
INTEGRATION_PORTS=(54321 54322 54323 54324 54327 54329 54764 55321 55322 55323 55324 55327 55329 55764)

print_usage() {
	cat <<'EOF'
Usage:
  ./tests/run_tests.sh                 Run unit tests only (default)
  ./tests/run_tests.sh --unit          Run unit tests only
  ./tests/run_tests.sh --integration   Run integration tests only
  ./tests/run_tests.sh --all           Run both suites
  ./tests/run_tests.sh --all --verbose Run both suites with verbose Bats output
EOF
}

fail_preflight() {
	echo "Integration preflight failed: $1" >&2
	exit 1
}

check_port_free() {
	local port="$1"

	if lsof -i ":$port" >/dev/null 2>&1; then
		fail_preflight "port $port is already in use"
	fi
}

run_integration_preflight() {
	if ! docker info >/dev/null 2>&1; then
		fail_preflight "Docker daemon is not running or not reachable"
	fi

	if [ ! -d "$SUPABASE_REPO/docker" ]; then
		fail_preflight "local Supabase repo not found at $SUPABASE_REPO/docker"
	fi

	for port in "${INTEGRATION_PORTS[@]}"; do
		check_port_free "$port"
	done
}

for arg in "$@"; do
	case "$arg" in
	--unit)
		RUN_UNIT=true
		;;
	--integration)
		RUN_INTEGRATION=true
		;;
	--all)
		RUN_UNIT=true
		RUN_INTEGRATION=true
		;;
	--verbose | -v)
		BATS_FLAGS+=(--verbose-run)
		;;
	--help | -h)
		print_usage
		exit 0
		;;
	*)
		echo "Unknown flag: $arg" >&2
		print_usage >&2
		exit 1
		;;
	esac
done

if ! $RUN_UNIT && ! $RUN_INTEGRATION; then
	RUN_UNIT=true
fi

UNIT_STATUS=0
INTEGRATION_STATUS=0

if $RUN_UNIT; then
	echo "=== Running unit test baseline (tests/pr/) ==="
	"$BATS" "${BATS_FLAGS[@]}" tests/pr/ || UNIT_STATUS=$?
fi

if $RUN_INTEGRATION; then
	echo "=== Running integration tests (tests/integration/) ==="
	run_integration_preflight
	SUPASCALE_INTEGRATION=1 "$BATS" "${BATS_FLAGS[@]}" tests/integration/ || INTEGRATION_STATUS=$?
fi

echo ""
echo "=== Results ==="
$RUN_UNIT && echo "Unit:        $([ "$UNIT_STATUS" -eq 0 ] && echo PASS || echo FAIL)"
$RUN_INTEGRATION && echo "Integration: $([ "$INTEGRATION_STATUS" -eq 0 ] && echo PASS || echo FAIL)"

[ "$UNIT_STATUS" -eq 0 ] && [ "$INTEGRATION_STATUS" -eq 0 ]
