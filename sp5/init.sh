#!/bin/sh
# Spike 5 entrypoint: probe the claude-code Bun binary under Unikraft.
# Step A runs without credentials. Step B runs only if ANTHROPIC_API_KEY is
# supplied (secretKeyRef) and exercises the network and a Bash tool call.
export PATH=/bin
export HOME=/tmp/home
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
mkdir -p "$HOME"

mem() { grep -E 'MemTotal|MemAvailable' /proc/meminfo | tr -s ' ' | tr '\n' ' '; echo; }

echo "[sp5] mem at start: $(mem)"
echo "[sp5] A1 claude --version"
timeout 60 /bin/claude --version; echo "[sp5] A1 rc=$?"

echo "[sp5] A2 claude --help (first lines)"
timeout 60 /bin/claude --help 2>&1 | head -3; echo "[sp5] A2 done"

if [ -n "$ANTHROPIC_API_KEY" ]; then
  echo "[sp5] B1 claude -p with a Bash tool call"
  timeout 180 /bin/claude -p 'Run exactly this shell command and reply with its output only: echo tool-ok' \
    --allowedTools Bash 2>&1 | tail -5
  echo "[sp5] B1 rc=$?"
else
  echo "[sp5] B skipped: no ANTHROPIC_API_KEY"
  echo "[sp5] A3 claude -p without a key (expect an auth error, not a crash)"
  timeout 60 /bin/claude -p 'hi' 2>&1 | head -3; echo "[sp5] A3 done"
fi

echo "[sp5] mem at end: $(mem)"
echo "[sp5] done; idling so logs are read once"
exec sleep 86400
