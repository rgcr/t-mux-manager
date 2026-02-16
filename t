#!/usr/bin/env bash
# t : tmux session & project manager
#
# Reads a YAML config file and creates/updates tmux sessions with windows,
# panes, and commands. Reuses existing sessions and windows,
# only creates what's missing.

set -euo pipefail

# -- Constants ----------------------------------------------------------------

_VERSION="v0.1.0"
_PROG_NAME="t"
_CONFIG_DIR="${HOME}/.config/tmux-projects"
mkdir -p "$_CONFIG_DIR"

_RED='1;31'
_YELLOW='1;33'
_CYAN='1;36'
_BLUE='1;34'

# -- Flag variables ------------------------------------------------------------

DRY_RUN=0
NO_ATTACH=0
REAPPLY=0
VERBOSE=0
NO_COLOR=0
EDIT_CONFIG=0
PRINT_CONFIG=0
KILL_SESSION=0
RM_CONFIG=0
LIST_SESSIONS=0
LIST_PROJECTS=0
SAVE_SESSION=0
CONFIG_FILE=""
PROJECT=""

# -- Messages ------------------------------------------------------------------


# handles NO_COLOR flag and printf formatting for colored output
_color() {
  local code="$1"; shift
  if (( NO_COLOR )); then
    printf '%s' "$*"
  else
    printf '\033[%sm%s\033[0m' "$code" "$*"
  fi
}

_yellow() { _color "$_YELLOW" "$*"; }
_red() { _color "$_RED" "$*"; }
_cyan() { _color "$_CYAN" "$*"; }
_blue() { _color "$_BLUE" "$*"; }

debug() {
    (( VERBOSE )) && printf 'DEBUG: %s\n' "$*" >&2
    return 0;
}

info()    { printf '%s\n' "$*" >&2; }
warn()    { printf 'Warning, %s\n' "$*" >&2; }
dry_msg() { printf 'DRY-RUN: %s\n' "$*"; }

die() {
    printf 'Error, %s\n' "$*" >&2
    exit 1
}

confirm() {
  local reply
    printf '%s [y/N]: ' "$*" >&2
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# -- Dependency check ---------------------------------------------------------

require_deps() {
  for cmd in tmux yq; do
    if ! command -v "$cmd" &>/dev/null; then
        die "missing required dependency <$cmd>"
    fi
  done
}

# -- tmux wrapper (supports dry-run) ------------------------------------------

exec_tmux() {
  if (( DRY_RUN )); then
      dry_msg "$*"
  else
    command tmux "$@"
  fi
}

# -- YAML getters (via yq) ---------------------------------------------------

yaml_get() {
  local file="$1" path="$2"
  local val
  val=$(yq "$path" "$file")
  [[ "$val" == "null" ]] && val=""
  printf '%s' "$val"
}

yaml_get_length() {
  local file="$1" path="$2"
  local len
  len=$(yq "$path | length" "$file" 2>/dev/null) || len=0
  printf '%s' "$len"
}

yaml_count() {
  local file="$1" path="$2"
  local result
  result=$(yq "$path | length // 0" "$file" 2>/dev/null) || result=0
  printf '%s' "$result"
}

# -- Path helpers -------------------------------------------------------------

expand_path() {
  local p="$1"
  [[ -z "$p" ]] && return
  # Expand leading ~
  if [[ "$p" == "~"* ]]; then
    p="${HOME}${p#"~"}"
  fi
  # Expand $HOME and ${HOME}
  p="${p/\$\{HOME\}/$HOME}"
  p="${p/\$HOME/$HOME}"
  printf '%s' "$p"
}

resolve_root() {
  local session_root="$1" window_root="${2:-}" pane_root="${3:-}"
  local base
  base=$(expand_path "$session_root")

  if [[ -n "$pane_root" ]]; then
    local expanded
    expanded=$(expand_path "$pane_root")
    if [[ "$expanded" == /* ]]; then
      printf '%s' "$expanded"
    else
      printf '%s/%s' "${base}" "$expanded"
    fi
    return
  fi

  if [[ -n "$window_root" ]]; then
    local expanded
    expanded=$(expand_path "$window_root")
    if [[ "$expanded" == /* ]]; then
      printf '%s' "$expanded"
    else
      printf '%s/%s' "${base}" "$expanded"
    fi
    return
  fi

  printf '%s' "$base"
}

# -- tmux helpers -------------------------------------------------------------

session_exists() {
  local name="$1"
  if (( DRY_RUN )); then
    return 1
  fi
  command tmux has-session -t "=$name" 2>/dev/null
}

window_exists() {
  local session="$1" window="$2"
  if (( DRY_RUN )); then
    return 1
  fi
  command tmux list-windows -t "=$session" -F '#{window_name}' 2>/dev/null | grep -qxF "$window"
}

window_name_count() {
  local session="$1" window="$2"
  if (( DRY_RUN )); then
    printf '0'
    return
  fi
  local count
  count=$(command tmux list-windows -t "=$session" -F '#{window_name}' 2>/dev/null | grep -cxF "$window") || true
  printf '%s' "${count:-0}"
}

pane_count() {
  local session="$1" window="$2"
  if (( DRY_RUN )); then
    printf '1'
    return
  fi
  command tmux list-panes -t "=${session}:${window}" -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' '
}

# -- Session / window / pane creation ----------------------------------------

create_session() {
  local name="$1" root="$2" first_window="$3"
  local resolved
  resolved=$(expand_path "$root")

  local -a cmd=(new-session -d -s "$name" -n "$first_window")
  if [[ -n "$resolved" ]]; then
    cmd+=(-c "$resolved")
  fi
  exec_tmux "${cmd[@]}"
}

create_window() {
  local session="$1" name="$2" root="$3"
  local -a cmd=(new-window -t "=${session}:" -n "$name")
  if [[ -n "$root" ]]; then
    cmd+=(-c "$root")
  fi
  exec_tmux "${cmd[@]}"
}

create_panes() {
  local file="$1" session="$2" window="$3" wi="$4" session_root="$5" window_root="$6"
  local pane_count_yaml current_panes

  pane_count_yaml=$(yaml_count "$file" ".windows[$wi].panes")
  if (( pane_count_yaml == 0 )); then
    return
  fi

  current_panes=$(pane_count "$session" "$window")

  for (( pi = current_panes; pi < pane_count_yaml; pi++ )); do
    local split pane_root_raw pane_root_resolved size
    split=$(yaml_get "$file" ".windows[$wi].panes[$pi].split")
    pane_root_raw=$(yaml_get "$file" ".windows[$wi].panes[$pi].root")
    size=$(yaml_get "$file" ".windows[$wi].panes[$pi].size")

    pane_root_resolved=$(resolve_root "$session_root" "$window_root" "$pane_root_raw")

    local -a cmd=(split-window -t "=${session}:${window}")
    if [[ "$split" == "vertical" ]]; then
      cmd+=(-v)
    else
      cmd+=(-h)
    fi
    if [[ -n "$size" ]]; then
      cmd+=(-p "$size")
    fi
    if [[ -n "$pane_root_resolved" ]]; then
      cmd+=(-c "$pane_root_resolved")
    fi

    exec_tmux "${cmd[@]}"
  done
}

send_commands() {
  local session="$1" window="$2" pane_index="$3"
  shift 3

  local target="=${session}:${window}.${pane_index}"

  for cmd in "$@"; do
    exec_tmux send-keys -t "$target" -l -- "$cmd"
    exec_tmux send-keys -t "$target" Enter
  done
}

apply_layout() {
  local session="$1" window="$2" layout="$3"
  if [[ -n "$layout" ]]; then
    if (( DRY_RUN )); then
      exec_tmux select-layout -t "=${session}:${window}" "$layout"
    else
      command tmux select-layout -t "=${session}:${window}" "$layout" 2>/dev/null \
        || warn "failed to apply layout '$layout' to ${session}:${window}"
    fi
  fi
}

# -- Main logic ---------------------------------------------------------------

apply_config() {
  local file="$1"

  [[ -f "$file" ]] || die "project config not found: ${file/$HOME/\~}"

  local session_name session_root window_count
  session_name=$(yaml_get "$file" ".session")
  session_root=$(yaml_get "$file" ".root")
  window_count=$(yaml_get_length "$file" ".windows")

  [[ -n "$session_name" ]] || die "missing 'session' key in $file"
  (( window_count > 0 )) || die "no windows defined in $file"

  debug "session=$session_name root=$session_root windows=$window_count"

  local session_is_new=0

  # -- Session ----------------------------------------------------------------

  if session_exists "$session_name"; then
    debug "session '$session_name' already exists, reusing"
  else
    local first_window_name first_window_root first_window_root_resolved
    first_window_name=$(yaml_get "$file" ".windows[0].name")
    first_window_root=$(yaml_get "$file" ".windows[0].root")
    first_window_root_resolved=$(resolve_root "$session_root" "$first_window_root")

    # If panes[0] has a root, use it for the session's start directory
    local first_pane_root
    first_pane_root=$(yaml_get "$file" ".windows[0].panes[0].root")
    if [[ -n "$first_pane_root" ]]; then
      first_window_root_resolved=$(resolve_root "$session_root" "$first_window_root" "$first_pane_root")
    fi

    create_session "$session_name" "${first_window_root_resolved:-$session_root}" "$first_window_name"
    session_is_new=1
    debug "created session '$session_name'"
  fi

  # -- Windows ----------------------------------------------------------------

  local -a _claimed_windows=()
  local _first_win_target=""

  for (( wi = 0; wi < window_count; wi++ )); do
    local win_name win_root win_root_resolved layout
    win_name=$(yaml_get "$file" ".windows[$wi].name")
    win_root=$(yaml_get "$file" ".windows[$wi].root")
    win_root_resolved=$(resolve_root "$session_root" "$win_root")
    layout=$(yaml_get "$file" ".windows[$wi].layout")

    # If panes[0] has a root, use it for the window's start directory
    local first_pane_root
    first_pane_root=$(yaml_get "$file" ".windows[$wi].panes[0].root")
    if [[ -n "$first_pane_root" ]]; then
      win_root_resolved=$(resolve_root "$session_root" "$win_root" "$first_pane_root")
    fi

    [[ -n "$win_name" ]] || die "window at index $wi has no name"

    # Count how many windows with this name we've already claimed
    local _claimed=0
    for _cw in "${_claimed_windows[@]}"; do
      [[ "$_cw" == "$win_name" ]] && (( _claimed++ )) || true
    done

    local window_is_new=0

    if (( session_is_new && wi == 0 )); then
      # First window was created with the session
      window_is_new=1
      debug "window '$win_name' created with session"
    else
      local _existing
      _existing=$(window_name_count "$session_name" "$win_name")
      if (( _existing > _claimed )); then
        debug "window '$win_name' already exists, reusing"
      else
        create_window "$session_name" "$win_name" "$win_root_resolved"
        window_is_new=1
        debug "created window '$win_name'"
      fi
    fi

    _claimed_windows+=("$win_name")

    # Resolve window target: use index in real mode (handles duplicate names),
    # use name in dry-run (no tmux to query)
    local win_target="$win_name"
    if ! (( DRY_RUN )); then
      local _nth=$(( _claimed + 1 ))
      local _idx _count=0
      while IFS= read -r _idx; do
        (( ++_count ))
        if (( _count == _nth )); then
          win_target="$_idx"
          break
        fi
      done < <(command tmux list-windows -t "=$session_name" \
        -F '#{window_name}	#{window_index}' 2>/dev/null \
        | awk -F'\t' -v name="$win_name" '$1 == name {print $2}')
    fi

    if (( window_is_new )); then
      exec_tmux set-option -t "=${session_name}:${win_target}" -w automatic-rename off
    fi

    [[ -z "$_first_win_target" ]] && _first_win_target="$win_target"

    # -- Panes ----------------------------------------------------------------

    local pane_count_yaml
    pane_count_yaml=$(yaml_count "$file" ".windows[$wi].panes")

    if (( pane_count_yaml > 0 )); then
      create_panes "$file" "$session_name" "$win_target" "$wi" "$session_root" "$win_root"
    fi

    # -- Commands (window-level → first pane) ---------------------------------

    local should_send=0
    if (( window_is_new || REAPPLY )); then
      should_send=1
    fi

    if (( should_send )); then
      # Resolve actual pane indices (respects pane-base-index)
      local -a pane_indices=()
      if (( DRY_RUN )); then
        local total=$(( pane_count_yaml > 0 ? pane_count_yaml : 1 ))
        for (( pi = 0; pi < total; pi++ )); do
          pane_indices+=("$pi")
        done
      else
        while IFS= read -r idx; do
          pane_indices+=("$idx")
        done < <(tmux list-panes -t "=${session_name}:${win_target}" -F '#{pane_index}')
      fi

      # Window-level commands go to first pane
      local win_cmd_count
      win_cmd_count=$(yaml_count "$file" ".windows[$wi].commands")
      if (( win_cmd_count > 0 )); then
        local -a win_cmds=()
        for (( ci = 0; ci < win_cmd_count; ci++ )); do
          win_cmds+=("$(yaml_get "$file" ".windows[$wi].commands[$ci]")")
        done
        send_commands "$session_name" "$win_target" "${pane_indices[0]}" "${win_cmds[@]}"
      fi

      # Per-pane commands
      for (( pi = 0; pi < pane_count_yaml; pi++ )); do
        local pane_cmd_count
        pane_cmd_count=$(yaml_count "$file" ".windows[$wi].panes[$pi].commands")
        if (( pane_cmd_count > 0 )); then
          local -a pane_cmds=()
          for (( pci = 0; pci < pane_cmd_count; pci++ )); do
            pane_cmds+=("$(yaml_get "$file" ".windows[$wi].panes[$pi].commands[$pci]")")
          done
          send_commands "$session_name" "$win_target" "${pane_indices[$pi]}" "${pane_cmds[@]}"
        fi
      done
    fi

    # -- Layout ---------------------------------------------------------------

    apply_layout "$session_name" "$win_target" "$layout"
  done

  # Select first window
  exec_tmux select-window -t "=${session_name}:${_first_win_target}"
}

# -- Attach / switch ----------------------------------------------------------

attach_or_switch() {
  local session_name="$1"

  if (( NO_ATTACH || DRY_RUN )); then
    return
  fi

  if [[ -n "${TMUX:-}" ]]; then
    command tmux switch-client -t "=$session_name"
  else
    command tmux attach-session -t "=$session_name"
  fi
}

# -- Config resolution --------------------------------------------------------

resolve_config() {
  local project="$1"
  if [[ -n "$CONFIG_FILE" ]]; then
    # Explicit -f path takes priority
    return
  fi
  local path="${_CONFIG_DIR}/${project}.yml"
  if [[ -f "$path" ]]; then
    debug "found config: $path"
    CONFIG_FILE="$path"
  elif session_exists "$project"; then
    debug "no config found, attaching to existing session '$project'"
    attach_or_switch "$project"
    exit 0
  else
    debug "no config or session found, creating new session '$project'"
    exec_tmux new-session -d -s "$project" -n "$project"
    attach_or_switch "$project"
    exit 0
  fi
}

# -- Save session to config ---------------------------------------------------

save_session() {
  [[ -n "${TMUX:-}" ]] || die "-s/--save-project must be run from inside a tmux session"

  local session
  session=$(command tmux display-message -p '#{session_name}')
  local outfile="${1:-${_CONFIG_DIR}/${session}.yml}"

  if [[ -z "${1:-}" && -f "$outfile" ]]; then
    confirm "config for '$session' already exists, overwrite?" || { warn "aborted"; exit 1; }
  fi

  # Session root from first window's first pane
  local first_win
  first_win=$(command tmux list-windows -t "=$session" -F '#{window_index}' | head -1)
  local session_root
  session_root=$(command tmux list-panes -t "=${session}:${first_win}" -F '#{pane_current_path}' | head -1)
  session_root="${session_root/$HOME/\~}"

  {
    printf 'session: %s\n' "$session"
    printf 'root: %s\n' "$session_root"
    printf '\nwindows:\n'

    local win_index win_name win_layout
    while IFS=$'\t' read -r win_index win_name win_layout; do
      printf '  - name: %s\n' "$win_name"

      # Collect panes for this window (use index to handle duplicate names)
      local pane_lines=()
      while IFS= read -r pane_path; do
        pane_lines+=("${pane_path/$HOME/\~}")
      done < <(command tmux list-panes -t "=${session}:${win_index}" -F '#{pane_current_path}')

      local win_root="${pane_lines[0]}"

      if (( ${#pane_lines[@]} == 1 )); then
        # Single-pane window: emit root only if different from session root
        if [[ "$win_root" != "$session_root" ]]; then
          printf '    root: %s\n' "$win_root"
        fi
      else
        # Multi-pane window: emit window root, layout, and per-pane roots
        if [[ "$win_root" != "$session_root" ]]; then
          printf '    root: %s\n' "$win_root"
        fi
        printf '    layout: "%s"\n' "$win_layout"
        printf '    panes:\n'
        for pane_path in "${pane_lines[@]}"; do
          if [[ "$pane_path" != "$win_root" ]]; then
            printf '      - root: %s\n' "$pane_path"
          else
            printf '      - {}\n'
          fi
        done
      fi
    done < <(command tmux list-windows -t "=$session" -F '#{window_index}	#{window_name}	#{window_layout}')
  } > "$outfile"

  if [[ -z "${1:-}" ]]; then
    info "project config saved in ${outfile/#"$HOME"/\~}"
  fi
}

# -- CLI parsing --------------------------------------------------------------

usage() {
  cat <<EOF

  ⚡ [t - mux] session and project manager
  ----------------------------------------

Usage: $_PROG_NAME [options] [<project>]
       $_PROG_NAME -f <project.yml> [options]

Resolution order for <project>:
  1. Config ~/.config/tmux-projects/<project>.yml exists — apply it
  2. tmux session <project> exists — attach to it
  3. Neither — create a new session named <project>

Use -f to specify an explicit project config file.
With no arguments, lists active tmux sessions and available projects.

Options:
  -f, --file <path>    Explicit project config file
  -e, --edit           Open project config in \$EDITOR
  -p, --print          Print project config to stdout
  -s, --save-project   Save current tmux session to a project config file inside config directory
      --reapply        Re-apply config and re-send commands to existing session
  -d, --dry-run        Print tmux commands instead of executing
  -n, --no-attach      Create session but don't attach
  -k, --kill <session> Kill tmux session
      --rm             Delete project config file
      --sessions       List tmux sessions
      --projects       List available projects
  -v, --verbose        Verbose output
      --no-color       Disable colored output
  -h, --help           Show this help
  -V, --version        Show version
EOF
}

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      -d|--dry-run)   DRY_RUN=1 ;;
      -n|--no-attach) NO_ATTACH=1 ;;
      -f|--file)
        [[ -n "${2:-}" ]] || die "'-f/--file' requires a project config file"
        CONFIG_FILE="$2"
        shift
        ;;
      -e|--edit)      EDIT_CONFIG=1 ;;
      -p|--print)     PRINT_CONFIG=1 ;;
      -k|--kill)      KILL_SESSION=1 ;;
      --rm)           RM_CONFIG=1 ;;
      --sessions)     LIST_SESSIONS=1 ;;
      --projects)     LIST_PROJECTS=1 ;;
      -s|--save-project) SAVE_SESSION=1 ;;
      --reapply)      REAPPLY=1 ;;
      -v|--verbose)   VERBOSE=1 ;;
      --no-color)     NO_COLOR=1 ;;
      -h|--help)      usage; exit 0 ;;
      -V|--version)   printf '%s version: %s\n' "$_PROG_NAME" "$_VERSION"; exit 0 ;;
      -*)             die "unknown option: $1" ;;
      *)
        if [[ -n "$PROJECT" ]]; then
          die "unexpected argument: $1"
        fi
        PROJECT="$1"
        ;;
    esac
    shift
  done

  # --edit only applies to project config files
  if (( EDIT_CONFIG )); then
    [[ -n "$CONFIG_FILE" || -n "$PROJECT" ]] || die "-e/--edit requires a project name"
    local path="${CONFIG_FILE:-${_CONFIG_DIR}/${PROJECT}.yml}"
    [[ -f "$path" ]] || die "project config not found: ${path/$HOME/\~}"
    exec "${EDITOR:-vi}" "$path"
  fi

  # --rm, delete a project config file
  if (( RM_CONFIG )); then
    [[ -n "$CONFIG_FILE" || -n "$PROJECT" ]] || die "--rm requires a project name"
    local path="${CONFIG_FILE:-${_CONFIG_DIR}/${PROJECT}.yml}"
    [[ -f "$path" ]] || die "project config not found: ${path/$HOME/\~}"
    confirm "Do you want to delete '${path/$HOME/\~}'?" || { warn "aborted"; exit 1; }
    rm -f "$path"
    info "config deleted!"
    exit 0
  fi

  # --sessions, list only tmux sessions
  if (( LIST_SESSIONS )); then
    list_sessions
    exit 0
  fi

  # --projects, list only available project configs
  if (( LIST_PROJECTS )); then
    list_projects
    exit 0
  fi

  # --print, print project config or current session snapshot to stdout
  if (( PRINT_CONFIG )); then
    if [[ -n "$CONFIG_FILE" || -n "$PROJECT" ]]; then
      local path="${CONFIG_FILE:-${_CONFIG_DIR}/${PROJECT}.yml}"
      [[ -f "$path" ]] || die "project config not found: ${path/$HOME/\~}"
      cat "$path"
    else
      [[ -n "${TMUX:-}" ]] || die "-p/--print with no project must be run from inside tmux"
      local tmpfile
      tmpfile=$(mktemp)
      save_session "$tmpfile"
      cat "$tmpfile"
      rm -f "$tmpfile"
    fi
    exit 0
  fi

  # --kill, kill the tmux session by name and exit
  if (( KILL_SESSION )); then
    [[ -n "$PROJECT" ]] || die "-k/--kill requires a session name"
    if ! (( DRY_RUN )); then
      session_exists "$PROJECT" || die "there is no tmux session '$PROJECT' "
    fi
    exec_tmux kill-session -t "=$PROJECT"
    if (( ! DRY_RUN )); then
      warn "session killed: '$PROJECT'"
    fi
    exit 0
  fi

  # --save, snapshot current tmux session to a project config file
  if (( SAVE_SESSION )); then
    save_session
    exit 0
  fi

  # resolve config, explicit -f takes priority, then project-name lookup
  if [[ -z "$CONFIG_FILE" && -n "$PROJECT" ]]; then
    resolve_config "$PROJECT"
  fi

  if [[ -z "$CONFIG_FILE" ]]; then
    list_session_projects
    exit 0
  fi
}

# -- Session listing ----------------------------------------------------------

list_sessions() {
  command tmux list-sessions \
    -F '#{?session_attached,●,} #{session_name}	#{session_windows} windows	(created #{t:session_created})' \
    2>/dev/null | column -t -s '	' || printf "no active sessions\n"
}

list_projects() {
  if [[ -d "$_CONFIG_DIR" ]]; then
    find "$_CONFIG_DIR" -maxdepth 1 -name '*.yml' -type f 2>/dev/null | sort \
      | sed "s|${HOME}|~|" \
      | awk -F/ '{file=$0; name=$NF; sub(/\.yml$/,"",name); printf "  %-20s %s\n", name, file}'
  fi
}

list_session_projects() {
  printf '\n%s\n' "$(_yellow 'current tmux sessions:')"
  list_sessions

  local listing
  listing=$(list_projects)
  if [[ -n "$listing" ]]; then
    printf '\n%s\n' "$(_blue 'available projects:')"
    printf '%s\n' "$listing"
  fi
}

# -- Main ---------------------------------------------------------------------

main() {
  require_deps

  parse_args "$@"

  [[ -f "$CONFIG_FILE" ]] || die "project config not found: ${CONFIG_FILE/$HOME/\~}"

  local session_name
  session_name=$(yaml_get "$CONFIG_FILE" ".session")
  [[ -n "$session_name" ]] || die "missing 'session' key in $CONFIG_FILE"

  local config_basename
  config_basename=$(basename "$CONFIG_FILE" .yml)
  if [[ "$session_name" != "$config_basename" ]]; then
    die "session name '$session_name' does not match config filename '$config_basename.yml', change the session name in the config or rename the file"
  fi

  if session_exists "$session_name" && (( ! REAPPLY && ! DRY_RUN )); then
    attach_or_switch "$session_name"
    return
  fi

  apply_config "$CONFIG_FILE"
  attach_or_switch "$session_name"
}

main "$@"
