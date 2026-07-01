#!/usr/bin/env zsh
# wizard-menu.sh — numbered menus for terminal wizards (loom-start, init-config)
# Usage: source tools/wizard-menu.sh
#   menu_pick "Prompt" default_index option1 option2 ...
#   → prints selected option text to stdout
set -euo pipefail

menu_pick() {
  local prompt="$1" default_n="${2:-1}"
  shift 2
  local -a opts=("$@")
  local n=${#opts[@]} i pick
  echo
  echo "$prompt"
  for i in {1..$n}; do
    echo "  $i) ${opts[$i]}"
  done
  read -r "pick?Choice [${default_n}]: " || true
  pick="${pick:-$default_n}"
  if [[ "$pick" =~ '^[0-9]+$' ]] && (( pick >= 1 && pick <= n )); then
    print -r -- "${opts[$pick]}"
    return 0
  fi
  # ponytail: allow typing the option label verbatim
  for i in {1..$n}; do
    [[ "${opts[$i]}" == "$pick" ]] && { print -r -- "$pick"; return 0; }
  done
  print -r -- "${opts[$default_n]}"
}

menu_yesno() {
  local prompt="$1" default_yes="${2:-1}"
  local yn
  if (( default_yes )); then
    yn="$(menu_pick "$prompt" 1 "Yes" "No")"
  else
    yn="$(menu_pick "$prompt" 2 "Yes" "No")"
  fi
  [[ "$yn" == "Yes" ]]
}
