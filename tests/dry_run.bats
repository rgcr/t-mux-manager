#!/usr/bin/env bats
# dry_run.bats — Golden-output tests for t --dry-run

load helpers

@test "dry-run minimal" {
  run "$T" --dry-run --no-color -f "$PROJECT_DIR/examples/minimal.yml"
  [ "$status" -eq 0 ]
  actual=$(printf '%s' "$output" | sed "s|$HOME|\$HOME|g")
  expected=$(cat "$EXPECTED_DIR/minimal.txt")
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual")
}

@test "dry-run minimal-commands" {
  run "$T" --dry-run --no-color -f "$PROJECT_DIR/examples/minimal-commands.yml"
  [ "$status" -eq 0 ]
  actual=$(printf '%s' "$output" | sed "s|$HOME|\$HOME|g")
  expected=$(cat "$EXPECTED_DIR/minimal-commands.txt")
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual")
}

@test "dry-run fullstack" {
  run "$T" --dry-run --no-color -f "$PROJECT_DIR/examples/fullstack.yml"
  [ "$status" -eq 0 ]
  actual=$(printf '%s' "$output" | sed "s|$HOME|\$HOME|g")
  expected=$(cat "$EXPECTED_DIR/fullstack.txt")
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual")
}

@test "dry-run custom-layout" {
  run "$T" --dry-run --no-color -f "$PROJECT_DIR/examples/custom-layout.yml"
  [ "$status" -eq 0 ]
  actual=$(printf '%s' "$output" | sed "s|$HOME|\$HOME|g")
  expected=$(cat "$EXPECTED_DIR/custom-layout.txt")
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual")
}
