#!/usr/bin/env bats
# cli_flags.bats — CLI flag and error-handling tests for t

load helpers

# -- help & version -----------------------------------------------------------

@test "-h exits 0" {
  run "$T" -h
  [ "$status" -eq 0 ]
}

@test "--help exits 0" {
  run "$T" --help
  [ "$status" -eq 0 ]
}

@test "-h shows usage" {
  run "$T" -h
  assert_contains "Usage:"
}

@test "-V exits 0" {
  run "$T" -V
  [ "$status" -eq 0 ]
}

@test "-V shows version" {
  run "$T" -V
  assert_contains "$T_VERSION"
}

# -- error handling -----------------------------------------------------------

@test "unknown flag exits 1" {
  run "$T" --unknown
  [ "$status" -eq 1 ]
}

@test "unknown flag message" {
  run "$T" --unknown
  assert_contains "unknown option"
}

@test "-f without arg exits 1" {
  run "$T" -f
  [ "$status" -eq 1 ]
}

@test "-f without arg message" {
  run "$T" -f
  assert_contains "requires a project config file"
}

@test "-f nonexistent file exits 1" {
  run "$T" --dry-run -f /tmp/nonexistent_config_$$.yml
  [ "$status" -eq 1 ]
}

@test "-f nonexistent file message" {
  run "$T" --dry-run -f /tmp/nonexistent_config_$$.yml
  assert_contains "project config not found"
}

@test "-k without session name exits 1" {
  run "$T" -k
  [ "$status" -eq 1 ]
}

@test "-k without session name message" {
  run "$T" -k
  assert_contains "requires a session name"
}

@test "-k nonexistent session exits 1" {
  run "$T" -k nonexistent_session_$$
  [ "$status" -eq 1 ]
}

@test "-k nonexistent session message" {
  run "$T" -k nonexistent_session_$$
  assert_contains "no tmux session"
}

@test "-e without project name exits 1" {
  run "$T" -e
  [ "$status" -eq 1 ]
}

@test "-e without project name message" {
  run "$T" -e
  assert_contains "requires a project name"
}

@test "-e nonexistent project exits 1" {
  run "$T" -e nonexistent_project_$$
  [ "$status" -eq 1 ]
}

@test "-e nonexistent project message" {
  run "$T" -e nonexistent_project_$$
  assert_contains "project config not found"
}

# -- rm (delete project config) -----------------------------------------------

@test "--rm without project name exits 1" {
  run "$T" --rm
  [ "$status" -eq 1 ]
}

@test "--rm without project name message" {
  run "$T" --rm
  assert_contains "requires a project name"
}

@test "--rm nonexistent project exits 1" {
  run "$T" --rm nonexistent_project_$$
  [ "$status" -eq 1 ]
}

@test "--rm nonexistent project message" {
  run "$T" --rm nonexistent_project_$$
  assert_contains "project config not found"
}

setup_rm_project() {
  _RM_PROJECT="t_test_rm_$$"
  _RM_YML="$TEST_CONFIG_DIR/${_RM_PROJECT}.yml"
  mkdir -p "$TEST_CONFIG_DIR"
  cat > "$_RM_YML" <<YAML
session: $_RM_PROJECT
root: ~/workspace
windows:
  - name: main
YAML
}

@test "--rm deletes project config" {
  setup_rm_project
  run bash -c "echo y | '$T' --rm '$_RM_PROJECT'"
  [ "$status" -eq 0 ]
  [ ! -f "$_RM_YML" ]
}

@test "--rm aborted does not delete" {
  setup_rm_project
  run bash -c "echo n | '$T' --rm '$_RM_PROJECT'"
  [ "$status" -eq 1 ]
  [ -f "$_RM_YML" ]
  rm -f "$_RM_YML"
}

# -- sessions/projects listing ------------------------------------------------

@test "--sessions exits 0" {
  run "$T" --sessions
  [ "$status" -eq 0 ]
}

@test "--projects exits 0" {
  run "$T" --projects
  [ "$status" -eq 0 ]
}

# -- dry-run kill -------------------------------------------------------------

@test "dry-run kill exits 0" {
  run "$T" --dry-run --no-color -k somesession
  [ "$status" -eq 0 ]
}

@test "dry-run kill output" {
  run "$T" --dry-run --no-color -k somesession
  assert_contains "DRY-RUN.*kill-session -t =somesession"
}

# -- dry-run new session (no config, no session) ------------------------------

@test "dry-run bare session exits 0" {
  run "$T" --dry-run --no-color nosuchproject_$$
  [ "$status" -eq 0 ]
}

@test "dry-run bare session output" {
  run "$T" --dry-run --no-color nosuchproject_$$
  assert_contains "new-session -d -s nosuchproject_$$"
}

# -- project resolution from config dir ---------------------------------------

setup_resolution_project() {
  _TEST_PROJECT="t_test_resolution_$$"
  _TEST_YML="$TEST_CONFIG_DIR/${_TEST_PROJECT}.yml"
  mkdir -p "$TEST_CONFIG_DIR"
  cat > "$_TEST_YML" <<YAML
session: $_TEST_PROJECT
root: ~/workspace
windows:
  - name: main
    commands:
      - echo hello
YAML
}

teardown_resolution_project() {
  rm -f "$_TEST_YML"
}

@test "project resolution via config dir exits 0" {
  setup_resolution_project
  run "$T" --dry-run --no-color "$_TEST_PROJECT"
  teardown_resolution_project
  [ "$status" -eq 0 ]
}

@test "project resolution creates session from config" {
  setup_resolution_project
  run "$T" --dry-run --no-color "$_TEST_PROJECT"
  teardown_resolution_project
  assert_contains "new-session -d -s $_TEST_PROJECT"
}

# -- save-project outside tmux ------------------------------------------------

@test "-s outside tmux exits 1" {
  run env -u TMUX "$T" -s
  [ "$status" -eq 1 ]
}

@test "-s outside tmux message" {
  run env -u TMUX "$T" -s
  assert_contains "must be run from inside a tmux session"
}

# -- print config (-p) -------------------------------------------------------

@test "-p with config file exits 0" {
  run "$T" -p -f "$PROJECT_DIR/examples/minimal.yml"
  [ "$status" -eq 0 ]
}

@test "-p prints config content" {
  run "$T" -p -f "$PROJECT_DIR/examples/minimal.yml"
  assert_contains "session: minimal"
}

@test "-p nonexistent project exits 1" {
  run "$T" -p nonexistent_project_$$
  [ "$status" -eq 1 ]
}

@test "-p nonexistent project message" {
  run "$T" -p nonexistent_project_$$
  assert_contains "project config not found"
}

@test "-p outside tmux with no project exits 1" {
  run env -u TMUX "$T" -p
  [ "$status" -eq 1 ]
}

@test "-p outside tmux message" {
  run env -u TMUX "$T" -p
  assert_contains "must be run from inside tmux"
}

# -- print config by project name ---------------------------------------------

setup_print_project() {
  _PRINT_PROJECT="t_test_print_$$"
  _PRINT_YML="$TEST_CONFIG_DIR/${_PRINT_PROJECT}.yml"
  mkdir -p "$TEST_CONFIG_DIR"
  cat > "$_PRINT_YML" <<YAML
session: $_PRINT_PROJECT
root: ~/workspace
windows:
  - name: main
YAML
}

teardown_print_project() {
  rm -f "$_PRINT_YML"
}

@test "-p project name exits 0" {
  setup_print_project
  run "$T" -p "$_PRINT_PROJECT"
  teardown_print_project
  [ "$status" -eq 0 ]
}

@test "-p project name prints content" {
  setup_print_project
  run "$T" -p "$_PRINT_PROJECT"
  teardown_print_project
  assert_contains "session: $_PRINT_PROJECT"
}

# -- session name must match config filename ----------------------------------

setup_mismatch() {
  _MISMATCH_YML=$(mktemp /tmp/mismatch_XXXXXX.yml)
  cat > "$_MISMATCH_YML" <<'YAML'
session: wrong_name
root: ~/workspace
windows:
  - name: main
YAML
}

teardown_mismatch() {
  rm -f "$_MISMATCH_YML"
}

@test "mismatched session name exits 1" {
  setup_mismatch
  run "$T" --dry-run -f "$_MISMATCH_YML"
  teardown_mismatch
  [ "$status" -eq 1 ]
}

@test "mismatched session name message" {
  setup_mismatch
  run "$T" --dry-run -f "$_MISMATCH_YML"
  teardown_mismatch
  assert_contains "does not match config filename"
}

# -- no ANSI codes with --no-color --------------------------------------------

@test "no-color dry-run exits 0" {
  run "$T" --dry-run --no-color -f "$PROJECT_DIR/examples/minimal.yml"
  [ "$status" -eq 0 ]
}

@test "no-color has no ANSI codes" {
  run "$T" --dry-run --no-color -f "$PROJECT_DIR/examples/minimal.yml"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q $'\033\['
}
