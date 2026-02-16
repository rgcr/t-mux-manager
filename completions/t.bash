# bash completion for t

_t() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  local flags="-f --file -e --edit -p --print -s --save-project --reapply -d --dry-run -n --no-attach -k --kill --rm --sessions --projects -v --verbose --no-color -h --help -V --version"

  case "$prev" in
    -f|--file)
      COMPREPLY=($(compgen -f -X '!*.yml' -- "$cur"))
      return
      ;;
    -k|--kill)
      local sessions
      sessions=$(command tmux list-sessions -F '#{session_name}' 2>/dev/null)
      COMPREPLY=($(compgen -W "$sessions" -- "$cur"))
      return
      ;;
    -e|--edit|-p|--print|--rm)
      local projects
      if [[ -d ~/.config/tmux-projects ]]; then
        projects=$(cd ~/.config/tmux-projects && printf '%s\n' *.yml 2>/dev/null | sed 's/\.yml$//')
      fi
      COMPREPLY=($(compgen -W "$projects" -- "$cur"))
      return
      ;;
  esac

  if [[ "$cur" == -* ]]; then
    COMPREPLY=($(compgen -W "$flags" -- "$cur"))
    return
  fi

  # positional: sessions first, then projects (deduplicated)
  local sessions projects all=""

  sessions=$(command tmux list-sessions -F '#{session_name}' 2>/dev/null)
  if [[ -d ~/.config/tmux-projects ]]; then
    projects=$(cd ~/.config/tmux-projects && printf '%s\n' *.yml 2>/dev/null | sed 's/\.yml$//')
  fi

  # sessions first, then projects not already a session
  all="$sessions"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if ! printf '%s\n' $sessions | grep -qx "$p"; then
      all+=$'\n'"$p"
    fi
  done <<< "$projects"

  if [[ -z "$cur" ]]; then
    # no input yet — just show `t` listing
    printf '\n'
    command t 2>/dev/null
    printf '%s' "${PS1@P}${COMP_LINE}"
    return
  fi

  COMPREPLY=($(compgen -W "$all" -- "$cur"))
  compopt -o nosort 2>/dev/null
}

complete -F _t t
