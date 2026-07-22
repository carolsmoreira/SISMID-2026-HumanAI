#!/usr/bin/env bash
set -euo pipefail

if [ -d "$HOME/.claude" ]; then
  sudo chown -R "$(id -u):$(id -g)" "$HOME/.claude" 2>/dev/null || true
fi

# Codex ships its terminal agent separately; install so `codex` also works
# in the terminal. Claude Code's CLI is bundled with its extension.
if command -v npm >/dev/null 2>&1; then
  npm install -g @openai/codex >/dev/null 2>&1 || echo "Codex CLI install skipped"
fi

echo "==> Tool versions"
R --version | head -n 1 || true
quarto --version || true
node --version || true
codex --version 2>/dev/null || true
echo "==> Ready."
