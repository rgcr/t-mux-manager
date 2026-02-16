#compdef t

_t() {
  local state

  _arguments -s -S \
    '(-f --file)'{-f,--file}'[Explicit project config file]:config file:_files -g "*.yml"' \
    '(-e --edit)'{-e,--edit}'[Open project config in $EDITOR]:project:->projects' \
    '(-p --print)'{-p,--print}'[Print project config to stdout]:project:->projects' \
    '(-s --save-project)'{-s,--save-project}'[Save current tmux session to config]' \
    '--reapply[Re-apply config and re-send commands]' \
    '(-d --dry-run)'{-d,--dry-run}'[Print tmux commands instead of executing]' \
    '(-n --no-attach)'{-n,--no-attach}'[Create session but do not attach]' \
    '(-k --kill)'{-k,--kill}'[Kill tmux session]:session:->sessions' \
    '--rm[Delete project config file]:project:->projects' \
    '--sessions[List tmux sessions]' \
    '--projects[List available projects]' \
    '(-v --verbose)'{-v,--verbose}'[Verbose output]' \
    '--no-color[Disable colored output]' \
    '(- *)'{-h,--help}'[Show help]' \
    '(- *)'{-V,--version}'[Show version]' \
    '1:project:->project_or_session' \
  && return 0

  # helpers: build parallel value/display arrays
  __t_add_projects() {
    local f
    if [[ -d ~/.config/tmux-projects ]]; then
      for f in ~/.config/tmux-projects/*.yml(N:t:r); do
        _values+=("$f")
        _display+=("$f (project)")
      done
    fi
  }

  __t_add_sessions() {
    local s
    for s in ${${(f)"$(command tmux list-sessions -F '#{session_name}' 2>/dev/null)"}:#}; do
      _values+=("$s")
      _display+=("$s (session)")
    done
  }

  local -a _values _display

  case "$state" in
    projects)
      __t_add_projects
      (( ${#_values} )) && compadd -V projects -d _display -a _values
      ;;
    sessions)
      __t_add_sessions
      (( ${#_values} )) && compadd -V sessions -d _display -a _values
      ;;
    project_or_session)
      # collect projects first to deduplicate
      local -a _proj_names
      if [[ -d ~/.config/tmux-projects ]]; then
        _proj_names=(~/.config/tmux-projects/*.yml(N:t:r))
      fi

      # sessions that don't have a project config
      local s
      for s in ${${(f)"$(command tmux list-sessions -F '#{session_name}' 2>/dev/null)"}:#}; do
        if (( ! ${_proj_names[(Ie)$s]} )); then
          _values+=("$s")
        fi
      done

      # all projects
      local f
      for f in $_proj_names; do
        _values+=("$f")
      done

      if [[ -z "$PREFIX" ]]; then
        # no input yet — just show `t` listing
        compadd -x "$(command t 2>/dev/null)"
      elif (( ${#_values} )); then
        compadd -V t-list -a _values
      fi
      ;;
  esac
}

# register when sourced directly; #compdef header handles fpath loading
if [[ -z "${_comps[t]+set}" ]]; then
  compdef _t t
fi
