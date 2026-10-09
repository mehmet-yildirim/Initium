#!/bin/sh
# npx.sh — locate npx (via Node.js) and exec it.
#
# Usage: sh .initium/scripts/npx.sh [npx-args...]
#
# GUI-launched editors (Cursor, etc.) often start MCP servers without the shell's
# PATH, so nvm/volta/Homebrew installs are probed explicitly. Override with
# INITIUM_NPX or INITIUM_NODE.

find_node() {
  if [ -n "$INITIUM_NODE" ] && [ -x "$INITIUM_NODE" ]; then
    echo "$INITIUM_NODE"
    return 0
  fi
  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi
  nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  if [ -d "$nvm_dir/versions/node" ]; then
    newest=$(ls "$nvm_dir/versions/node" 2>/dev/null | sort -V | tail -n 1)
    if [ -n "$newest" ] && [ -x "$nvm_dir/versions/node/$newest/bin/node" ]; then
      echo "$nvm_dir/versions/node/$newest/bin/node"
      return 0
    fi
  fi
  for candidate in \
    "$HOME/.volta/bin/node" \
    /opt/homebrew/bin/node \
    /usr/local/bin/node \
    /usr/bin/node \
    "$HOME/.local/share/mise/shims/node" \
    "$HOME/.asdf/shims/node"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

find_npx() {
  if [ -n "$INITIUM_NPX" ] && [ -x "$INITIUM_NPX" ]; then
    echo "$INITIUM_NPX"
    return 0
  fi
  if command -v npx >/dev/null 2>&1; then
    command -v npx
    return 0
  fi
  node_bin=$(find_node) || return 1
  npx_bin="$(dirname "$node_bin")/npx"
  if [ -x "$npx_bin" ]; then
    echo "$npx_bin"
    return 0
  fi
  return 1
}

npx_bin=$(find_npx)
if [ -z "$npx_bin" ]; then
  echo "npx.sh: npx/Node.js not found. Install Node.js or set INITIUM_NPX / INITIUM_NODE." >&2
  exit 127
fi

# Ensure the sibling node binary stays first on PATH for npx's child processes.
node_bin=$(find_node 2>/dev/null || true)
if [ -n "$node_bin" ]; then
  export PATH="$(dirname "$node_bin"):$PATH"
fi

exec "$npx_bin" "$@"
