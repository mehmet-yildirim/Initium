#!/bin/sh
# node.sh — locate Node.js and run a guardrail script with it.
#
# Usage: sh .initium/guardrails/node.sh [--cursor] <script> [args...]
#
# GUI-launched editors often run hooks without the shell's PATH, so nvm/volta/Homebrew
# installs are probed explicitly. If Node cannot be found, the guardrail fails closed
# only when INITIUM_AGENT_MODE=autonomous; interactive sessions get a warning instead.
# --cursor prints the JSON permission response Cursor requires on those fallback paths.

EXIT_BLOCK=2

emit_cursor=false
if [ "$1" = "--cursor" ]; then
  emit_cursor=true
  shift
fi

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

node_bin=$(find_node)
if [ -n "$node_bin" ]; then
  exec "$node_bin" "$@"
fi

if [ "$INITIUM_AGENT_MODE" = "autonomous" ]; then
  echo "[guardrails] Node.js not found; blocking because INITIUM_AGENT_MODE=autonomous." >&2
  if [ "$emit_cursor" = true ]; then
    echo '{"permission":"deny","user_message":"Initium guardrails could not find Node.js.","agent_message":"Initium guardrails could not find Node.js."}'
  fi
  exit "$EXIT_BLOCK"
fi

echo "[guardrails] Node.js not found; guardrails skipped. Set INITIUM_NODE to the node binary." >&2
if [ "$emit_cursor" = true ]; then
  echo '{"permission":"allow"}'
fi
exit 0
