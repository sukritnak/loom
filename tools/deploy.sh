#!/usr/bin/env zsh
# ponytail: backward-compat alias — use init.sh
exec zsh "$(cd "$(dirname "$0")" && pwd)/init.sh" "$@"
