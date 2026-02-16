# fish completion for t

function __t_projects
  if test -d ~/.config/tmux-projects
    for f in ~/.config/tmux-projects/*.yml
      test -f "$f"; and printf '%s\t%s\n' (basename "$f" .yml) project
    end
  end
end

function __t_sessions
  command tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -l s
    printf '%s\t%s\n' "$s" session
  end
end

function __t_projects_and_sessions
  set -l token (commandline -ct)

  if test -z "$token"
    # no input yet — show `t` listing, no completions
    printf '\n' >/dev/tty
    command t 2>/dev/null >/dev/tty
    commandline -f repaint
    return
  end

  set -l proj_names
  if test -d ~/.config/tmux-projects
    for f in ~/.config/tmux-projects/*.yml
      test -f "$f"; and set -a proj_names (basename "$f" .yml)
    end
  end

  # sessions that don't have a project config
  command tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -l s
    if not contains -- "$s" $proj_names
      printf '%s\t%s\n' "$s" session
    end
  end

  # all projects
  for p in $proj_names
    printf '%s\t%s\n' "$p" project
  end
end

# flags
complete -c t -s f -l file         -d 'Explicit project config file' -rF
complete -c t -s e -l edit         -d 'Open project config in $EDITOR' -rxa '(__t_projects)'
complete -c t -s p -l print        -d 'Print project config to stdout' -rxa '(__t_projects)'
complete -c t -s s -l save-project -d 'Save current tmux session to config'
complete -c t      -l reapply      -d 'Re-apply config and re-send commands'
complete -c t -s d -l dry-run      -d 'Print tmux commands instead of executing'
complete -c t -s n -l no-attach    -d 'Create session but do not attach'
complete -c t -s k -l kill         -d 'Kill tmux session' -rxa '(__t_sessions)'
complete -c t      -l rm           -d 'Delete project config file' -rxa '(__t_projects)'
complete -c t      -l sessions     -d 'List tmux sessions'
complete -c t      -l projects     -d 'List available projects'
complete -c t -s v -l verbose      -d 'Verbose output'
complete -c t      -l no-color     -d 'Disable colored output'
complete -c t -s h -l help         -d 'Show help'
complete -c t -s V -l version      -d 'Show version'

# positional: project configs + tmux sessions
complete -c t -n '__fish_is_first_token' -kxa '(__t_projects_and_sessions)'
