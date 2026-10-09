#!/bin/sh
# npx.sh — locate npx (via Node.js) and exec it.
#
# Usage: sh .initium/scripts/npx.sh [npx-args...]
#
# GUI-launched editors (Cursor, etc.) often start MCP servers without a login
# shell PATH — and sometimes without HOME. Probe common installs, then ask a
# login shell. Override with INITIUM_NPX or INITIUM_NODE (absolute paths).

ensure_home() {
  if [ -n "$HOME" ] && [ "$HOME" != "/" ] && [ -d "$HOME" ]; then
    return 0
  fi
  user="${USER:-$(id -un 2>/dev/null || true)}"
  if [ -n "$user" ]; then
    # ~user expansion works in sh when user exists
    guessed=$(eval "echo ~$user" 2>/dev/null || true)
    if [ -n "$guessed" ] && [ -d "$guessed" ]; then
      HOME="$guessed"
      export HOME
      return 0
    fi
  fi
  if [ -d /Users ] && [ -n "$user" ] && [ -d "/Users/$user" ]; then
    HOME="/Users/$user"
    export HOME
    return 0
  fi
  if [ -d "/home/$user" ]; then
    HOME="/home/$user"
    export HOME
  fi
}

# Load nvm in a bash subshell (nvm.sh is not reliable under plain sh).
from_nvm_sh() {
  name="$1"
  nvm_sh="${NVM_DIR:-${HOME:+$HOME/.nvm}}/nvm.sh"
  [ -n "$nvm_sh" ] && [ -s "$nvm_sh" ] || return 1
  command -v bash >/dev/null 2>&1 || [ -x /bin/bash ] || return 1
  bin=$(bash -c ". \"$nvm_sh\" >/dev/null 2>&1 && command -v $name" 2>/dev/null) || return 1
  if [ -n "$bin" ] && [ -x "$bin" ]; then
    echo "$bin"
    return 0
  fi
  return 1
}

# Ask zsh/bash for a command. Prefer interactive (-i) so ~/.zshrc (nvm) is loaded;
# login alone often only reads .zprofile and misses nvm.
from_login_shell() {
  name="$1"
  for shell in /bin/zsh /bin/bash zsh bash; do
    command -v "$shell" >/dev/null 2>&1 || [ -x "$shell" ] || continue
    for flags in -ilc -ic -lc; do
      bin=$("$shell" "$flags" "command -v $name" 2>/dev/null) || continue
      if [ -n "$bin" ] && [ -x "$bin" ]; then
        echo "$bin"
        return 0
      fi
    done
  done
  return 1
}

find_node() {
  if [ -n "$INITIUM_NODE" ] && [ -x "$INITIUM_NODE" ]; then
    echo "$INITIUM_NODE"
    return 0
  fi
  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi

  nvm_dir="${NVM_DIR:-${HOME:+$HOME/.nvm}}"
  if [ -n "$nvm_dir" ] && [ -d "$nvm_dir/versions/node" ]; then
    newest=$(ls "$nvm_dir/versions/node" 2>/dev/null | sort -V | tail -n 1)
    if [ -n "$newest" ] && [ -x "$nvm_dir/versions/node/$newest/bin/node" ]; then
      echo "$nvm_dir/versions/node/$newest/bin/node"
      return 0
    fi
  fi

  # fnm current symlink (macOS + Linux)
  for candidate in \
    "${HOME:+$HOME/.local/share/fnm/current/bin/node}" \
    "${HOME:+$HOME/Library/Application Support/fnm/current/bin/node}" \
    "${HOME:+$HOME/.fnm/current/bin/node}"; do
    [ -n "$candidate" ] || continue
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  for candidate in \
    "${HOME:+$HOME/.volta/bin/node}" \
    /opt/homebrew/bin/node \
    /usr/local/bin/node \
    /usr/bin/node \
    "${HOME:+$HOME/.local/share/mise/shims/node}" \
    "${HOME:+$HOME/.asdf/shims/node}" \
    "${HOME:+$HOME/.nix-profile/bin/node}" \
    /nix/var/nix/profiles/default/bin/node \
    "${HOME:+$HOME/.local/bin/node}"; do
    [ -n "$candidate" ] || continue
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  from_nvm_sh node && return 0
  from_login_shell node
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
  if node_bin=$(find_node); then
    npx_bin="$(dirname "$node_bin")/npx"
    if [ -x "$npx_bin" ]; then
      echo "$npx_bin"
      return 0
    fi
  fi
  from_nvm_sh npx && return 0
  from_login_shell npx
}

ensure_home

npx_bin=$(find_npx)
if [ -z "$npx_bin" ]; then
  echo "npx.sh: npx/Node.js not found (HOME=${HOME:-unset})." >&2
  echo "Install Node.js, or set INITIUM_NPX / INITIUM_NODE to an absolute path" >&2
  echo "(e.g. in .cursor/mcp.json → mcpServers.codegraph.env)." >&2
  exit 127
fi

# Ensure the sibling node binary stays first on PATH for npx's child processes.
node_bin=$(find_node 2>/dev/null || true)
if [ -n "$node_bin" ]; then
  export PATH="$(dirname "$node_bin"):/opt/homebrew/bin:/usr/local/bin:$PATH"
fi

exec "$npx_bin" "$@"
