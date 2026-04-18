# Tests

This directory contains the test harness for `supascale.sh`.

The test strategy is intentionally split into two layers:

- a fast mocked baseline suite for CLI and config-generation behavior
- a slower Docker-backed integration suite for real end-to-end verification

This keeps day-to-day feedback fast while still covering the parts of the system that only show up under real Docker and real generated config.

## Layout

```text
tests/
  bats/
  fixtures/
  integration/
    helpers/
    01_add_single.bats
    02_add_multi.bats
    03_lifecycle.bats
    04_backup_restore.bats
  pr/
    helpers/
    01_bootstrap.bats
    02_help_version.bats
    03_unknown_command.bats
    04_missing_args.bats
    05_project_id_validation.bats
    06_list.bats
    07_unknown_project.bats
    08_backup_utils.bats
    09_golden_master.bats
    baseline_run.log
    baseline_run_override.log
  run_tests.sh
```

## Top-Level Breakdown

### `tests/bats/`

Vendored `bats-core`, the shell test framework used by this project. This is framework infrastructure rather than project-specific test logic.

### `tests/fixtures/`

Static fixture inputs used by mocked tests. These files let the suite validate config rewriting against realistic source material without requiring a live clone or a running Docker stack.

### `tests/pr/`

Fast baseline tests. This suite verifies `supascale.sh` behavior in isolation and avoids real Docker, network, and cloud dependencies.

### `tests/integration/`

Real Docker-backed integration tests. This suite verifies that generated config and runtime commands work against a real local Supabase checkout and a live Docker daemon.

### `tests/run_tests.sh`

Unified runner for both suites. It selects which suite to run and performs preflight checks before integration runs.

## Baseline Suite: `tests/pr/`

The `pr/` suite is the fast regression layer. Its job is to preserve current behavior quickly and deterministically.

It covers:

- help and version output
- argument validation
- project ID validation
- unknown command and unknown project handling
- backup utility edge cases
- generated config structure and port assignments

### Shared Helper

`tests/pr/helpers/setup.bash` is the shared harness for this suite.

It:

- isolates `HOME` under a Bats temp directory
- suppresses the update-check path
- prepends mocked binaries to `PATH`
- wraps `supascale.sh` with stdin redirected from `/dev/null`

The mocked commands include:

- `docker`
- `git`
- `curl`
- `wget`
- `aws`
- `sudo`

This keeps the suite fast and prevents it from touching real infrastructure.

### Test Files

The numbered files group related behavior and make the suite easy to scan:

- `01_bootstrap.bats`
- `02_help_version.bats`
- `03_unknown_command.bats`
- `04_missing_args.bats`
- `05_project_id_validation.bats`
- `06_list.bats`
- `07_unknown_project.bats`
- `08_backup_utils.bats`
- `09_golden_master.bats`

`09_golden_master.bats` is the main config-generation test. It validates generated `.env`, `docker-compose.yml`, and stored port data against realistic fixture inputs.

### Baseline Logs

The following committed files capture known-good suite output:

- `tests/pr/baseline_run.log`
- `tests/pr/baseline_run_override.log`

These are intentional checked-in artifacts.

## Integration Suite: `tests/integration/`

The integration suite verifies that Supascale works in a real runtime environment.

It covers behavior that mocked tests cannot prove, including:

- containers actually starting
- port isolation between projects
- log scoping between compose projects
- lifecycle behavior across stop/start
- backup and restore working end-to-end

### Shared Helpers

`tests/integration/helpers/setup.bash` is the shared setup harness.

It:

- isolates `HOME`
- preserves Docker client config through `DOCKER_CONFIG`
- mocks `git clone` by copying the local Supabase repo from `/Users/ericzhou03/Projects/supabase`
- strips local runtime state from the copied checkout
- redirects stdin from `/dev/null`

It also provides helper functions such as:

- `require_integration_enabled()`
- `wait_for_healthy()`
- `assert_env_key_non_empty()`

`tests/integration/helpers/teardown.bash` contains the shared cleanup helper.

It tears projects down with:

- `docker compose down -v --remove-orphans`

and removes the isolated project directory.

The `-v` behavior is intentional: integration tests start fresh instead of reusing previous database state.

### Test Files

- `01_add_single.bats`
  Single-project provisioning and startup
- `02_add_multi.bats`
  Multi-project port and log isolation
- `03_lifecycle.bats`
  Stop/start lifecycle behavior
- `04_backup_restore.bats`
  Backup, verification, metadata inspection, and restore

### Why It Is Slower

Even when Docker is already running, the integration suite still does real startup work:

- each test gets a fresh isolated `HOME`
- each test gets a fresh copied Supabase checkout
- containers are started from scratch
- teardown removes volumes
- some tests recreate the stack more than once
- the multi-project test boots two projects

This suite optimizes for realism, not speed.

## Fixtures

Fixtures are committed static inputs used by mocked tests.

The main fixture directory is:

- `tests/fixtures/supabase_docker/`

It contains realistic source files such as:

- `.env.example`
- `docker-compose.yml`

In the baseline suite, the mocked `git clone` path copies these fixtures into the fake clone destination when a test exports `FIXTURE_DIR`.

This allows config-generation tests to validate real file rewriting without depending on a live upstream checkout.

## Shared Isolation Model

Both suites follow the same basic isolation pattern:

- `HOME` is redirected into a Bats temp directory
- stdin is redirected from `/dev/null`
- temporary wrapper binaries are injected through `PATH`

The difference is what gets mocked:

- `tests/pr/` mocks most external commands
- `tests/integration/` preserves real Docker behavior while still isolating Supascale state

## Running the Tests

Use the unified runner:

```bash
./tests/run_tests.sh
```

By default, this runs the baseline suite only.

### Common Commands

Run the baseline suite only:

```bash
./tests/run_tests.sh --unit
```

Run the integration suite only:

```bash
./tests/run_tests.sh --integration
```

Run both suites:

```bash
./tests/run_tests.sh --all
```

Run with verbose Bats output:

```bash
./tests/run_tests.sh --all --verbose
```

Show usage:

```bash
./tests/run_tests.sh --help
```

## Integration Prerequisites

The integration suite requires:

- a reachable Docker daemon
- a local Supabase repo at `/Users/ericzhou03/Projects/supabase`
- required host ports to be free

`tests/run_tests.sh` checks these conditions before running integration tests.

## Choosing the Right Suite

Use `tests/pr/` when:

- iterating quickly
- changing CLI behavior
- refactoring shell logic
- validating config generation without real Docker startup

Use `tests/integration/` when:

- changing Docker-related behavior
- changing startup or lifecycle behavior
- changing backup or restore logic
- changing multi-project isolation logic

Run both when:

- preparing final verification
- testing a broader refactor
- touching both control flow and real infrastructure behavior

## Artifacts and Logs

Committed artifacts currently include:

- `tests/pr/baseline_run.log`
- `tests/pr/baseline_run_override.log`

Most temporary test data is not stored in the repo. It lives in Bats temp directories during execution.

This includes:

- mock command call logs
- isolated `HOME` contents
- temporary wrapper scripts
- intermediate runtime state

The integration suite inspects Docker Compose logs during test execution, but it does not currently persist those logs into committed files under `tests/`.

## Typical Workflows

Quick local regression check:

```bash
./tests/run_tests.sh --unit
```

Infrastructure-focused verification:

```bash
./tests/run_tests.sh --integration
```

Full verification pass:

```bash
./tests/run_tests.sh --all
```
