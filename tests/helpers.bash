# helpers.bash — Shared env setup for bats tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
T="$PROJECT_DIR/t"
EXPECTED_DIR="$SCRIPT_DIR/expected"
TEST_CONFIG_DIR="${HOME}/.config/tmux-projects"

T_VERSION=$(grep -m1 '^_VERSION=' "$T" | sed 's/^_VERSION="//;s/"$//')

export PROJECT_DIR T EXPECTED_DIR TEST_CONFIG_DIR T_VERSION

# assert_contains — check that $output contains a pattern (extended regex)
assert_contains() {
  local pattern="$1"
  if ! printf '%s' "$output" | grep -qE "$pattern"; then
    printf 'pattern "%s" not found in output:\n%s\n' "$pattern" "$output" >&2
    return 1
  fi
}

# skip_if_no_tmux — skip test when tmux is unavailable
skip_if_no_tmux() {
  if ! command -v tmux &>/dev/null; then
    skip "tmux not available"
  fi
}
