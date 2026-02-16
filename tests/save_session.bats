#!/usr/bin/env bats
# save_session.bats — Tests for save-session (-s) and print (-p) with live tmux

load helpers

# -- File-level setup/teardown: isolated tmux servers -------------------------

setup_file() {
  skip_if_no_tmux

  export SOCK="t_bats_$$"
  export SESSION="t_bats_save_$$"
  export OUTFILE=$(mktemp)

  command tmux -L "$SOCK" new-session -d -s "$SESSION" -n editor
  command tmux -L "$SOCK" new-window -t "=$SESSION" -n server
  export TMUX_SOCKET=$(command tmux -L "$SOCK" display-message -p '#{socket_path}')

  export DUP_SOCK="t_bats_dup_$$"
  export DUP_SESSION="t_bats_dup_$$"
  export DUP_OUTFILE=$(mktemp)

  command tmux -L "$DUP_SOCK" new-session -d -s "$DUP_SESSION" -n code
  command tmux -L "$DUP_SOCK" new-window -t "=$DUP_SESSION:" -n code
  command tmux -L "$DUP_SOCK" new-window -t "=$DUP_SESSION:" -n code
  export DUP_SOCKET=$(command tmux -L "$DUP_SOCK" display-message -p '#{socket_path}')
}

teardown_file() {
  command tmux -L "$SOCK" kill-server 2>/dev/null || true
  command tmux -L "$DUP_SOCK" kill-server 2>/dev/null || true
  rm -f "$OUTFILE" "$DUP_OUTFILE"
}

# -- Helper: run t inside a tmux session via run-shell ------------------------

run_t_in_session() {
  local socket="$1" session="$2" outfile="$3"
  shift 3
  local runner
  runner=$(mktemp)
  printf '#!/bin/bash\nTMUX=%s %s %s > %s 2>/dev/null\n' "$socket" "$T" "$*" "$outfile" > "$runner"
  chmod +x "$runner"
  # Determine the -L name from the socket path
  local sock_name
  if [[ "$socket" == "$TMUX_SOCKET" ]]; then
    sock_name="$SOCK"
  else
    sock_name="$DUP_SOCK"
  fi
  command tmux -L "$sock_name" run-shell -t "=$session" "$runner" 2>/dev/null || true
  rm -f "$runner"
}

# -- Tests: basic save-session ------------------------------------------------

@test "-p captures current session" {
  skip_if_no_tmux
  run_t_in_session "$TMUX_SOCKET" "$SESSION" "$OUTFILE" -p
  [ -s "$OUTFILE" ]
}

@test "-p output has correct session name" {
  skip_if_no_tmux
  run_t_in_session "$TMUX_SOCKET" "$SESSION" "$OUTFILE" -p
  grep -qF "session: $SESSION" "$OUTFILE"
}

@test "-p output has window names" {
  skip_if_no_tmux
  run_t_in_session "$TMUX_SOCKET" "$SESSION" "$OUTFILE" -p
  grep -qF "name: editor" "$OUTFILE"
  grep -qF "name: server" "$OUTFILE"
}

@test "-p output has root" {
  skip_if_no_tmux
  run_t_in_session "$TMUX_SOCKET" "$SESSION" "$OUTFILE" -p
  grep -qF "root:" "$OUTFILE"
}

# -- Tests: duplicate window names --------------------------------------------

@test "-p with duplicate window names" {
  skip_if_no_tmux
  run_t_in_session "$DUP_SOCKET" "$DUP_SESSION" "$DUP_OUTFILE" -p
  [ -s "$DUP_OUTFILE" ]
}

@test "-p duplicate names has all windows" {
  skip_if_no_tmux
  run_t_in_session "$DUP_SOCKET" "$DUP_SESSION" "$DUP_OUTFILE" -p
  local count
  count=$(grep -c 'name: code' "$DUP_OUTFILE") || true
  [ "$count" -eq 3 ]
}
