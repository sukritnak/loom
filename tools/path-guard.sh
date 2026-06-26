#!/usr/bin/env zsh
# ponytail: Claude/CI sandboxes often strip PATH in subshells — restore before dirname/head/nc
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
