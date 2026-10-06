#!/bin/bash
# Link this clone's statusline into ~/.claude and register it in settings.json.
# Safe to re-run: existing files are backed up once with a timestamp suffix.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")" && pwd)
claude_dir="$HOME/.claude"
target="$claude_dir/statusline.sh"
settings="$claude_dir/settings.json"
stamp=$(date +%Y%m%d%H%M%S)

for bin in jq git; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 1; }
done

mkdir -p "$claude_dir"

if [ -L "$target" ] && [ "$(readlink "$target")" = "$repo_dir/statusline.sh" ]; then
  echo "✓ $target already linked"
else
  if [ -e "$target" ] || [ -L "$target" ]; then
    mv "$target" "$target.bak.$stamp"
    echo "• backed up old statusline to $target.bak.$stamp"
  fi
  ln -s "$repo_dir/statusline.sh" "$target"
  echo "✓ linked $target -> $repo_dir/statusline.sh"
fi

[ -f "$settings" ] || echo '{}' > "$settings"
want='{"type":"command","command":"bash \"$HOME/.claude/statusline.sh\"","refreshInterval":1}'
if jq -e --argjson w "$want" '.statusLine == $w' "$settings" >/dev/null; then
  echo "✓ settings.json already configured"
else
  cp "$settings" "$settings.bak.$stamp"
  jq --argjson w "$want" '.statusLine = $w' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
  echo "✓ updated statusLine in settings.json (backup: $settings.bak.$stamp)"
fi

echo "done — restart Claude Code or wait for the next refresh"
