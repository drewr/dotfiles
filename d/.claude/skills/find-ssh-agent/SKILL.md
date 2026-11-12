---
name: find-ssh-agent
description: Find a forwarded SSH agent socket with live identities and set SSH_AUTH_SOCK; if a running agent has no key, load a local private key from ~/.ssh into it
---

Run every `ssh-add` and `ssh` below with a `timeout`: a dead or prompting agent otherwise hangs the shell.

## 1. The stable symlink

First check the stable symlink that ~/.ssh/rc maintains on each inbound SSH connection:

```bash
sock=~/.ssh/ssh_auth_sock
if [ -S "$sock" ]; then
  result=$(SSH_AUTH_SOCK="$sock" timeout 5 ssh-add -l 2>&1)
  if echo "$result" | grep -qE "^[0-9]+ SHA256:"; then
    echo "FOUND (stable symlink): $sock"
    echo "$result"
  fi
fi
```

If that works, skip to step 3 with the stable symlink as the winning socket.

## 2. Scan for other agents

If the symlink is missing or dead, scan all candidate sockets:

Run it with bash, as written: zsh aborts the whole command when a glob such as `/tmp/ssh-*` matches nothing.

```bash
bash <<'EOF'
shopt -s nullglob
for sock in ~/.ssh/ssh_auth_sock /tmp/ssh-*/agent.* ~/.ssh/agent/*; do
  [ -S "$sock" ] || continue
  result=$(SSH_AUTH_SOCK="$sock" timeout 5 ssh-add -l 2>&1)
  case $? in
    0) echo "FOUND: $sock"; echo "$result" ;;
    1) echo "EMPTY (running, no identities): $sock" ;;
  esac
done
EOF
```

Report every socket that returned at least one identity. For each, show the key fingerprints. Note the empty ones too: step 4 can load a key into them.

If none did, go to step 4.

## 3. Test GitHub auth

For each socket found, test GitHub auth:

```bash
SSH_AUTH_SOCK=<socket> timeout 15 ssh -T git@github.com 2>&1
```

Report which socket authenticates successfully as the user. If none does, go to step 4.

## 4. Load a local private key

When no agent holds a key that works, load one from `~/.ssh` into an agent that is already running: one of the EMPTY sockets from step 2, or one whose keys failed GitHub auth.

**If no agent is running, stop and ask the human.** Don't start one with `ssh-agent`: a new agent outlives the session, holds a private key nobody chose to unlock, and isn't the one the human's shell uses. Say no agent is reachable, and suggest they reconnect with agent forwarding (`ssh -A`) or start an agent and `ssh-add` a key themselves; then run this skill again.

Prefer the keys `~/.ssh/allowed_signers` authorizes for commit signing (`~/bin/ssh-signing-key` uses the same order): `id_ecdsa`, then `id_ed25519`.

```bash
for key in ~/.ssh/id_ecdsa ~/.ssh/id_ed25519; do
  [ -f "$key" ] || continue
  if ssh-keygen -y -P "" -f "$key" >/dev/null 2>&1; then
    echo "USABLE (no passphrase): $key"
  else
    echo "PASSPHRASE: $key"
  fi
done
```

Never run `ssh-add` on a key with a passphrase: it prompts and hangs. For those, ask the human to run `! SSH_AUTH_SOCK=<socket> ssh-add <key>` themselves.

Load the first key without a passphrase into the running agent and check it:

```bash
SSH_AUTH_SOCK=<socket> timeout 10 ssh-add <key> </dev/null
SSH_AUTH_SOCK=<socket> timeout 5 ssh-add -l
SSH_AUTH_SOCK=<socket> timeout 15 ssh -T git@github.com 2>&1
```

Report the key loaded, its fingerprint, the socket, and the GitHub result.

## 5. Report

Finally, output the exact export command the user should run (or that you should use for the remainder of this session) to make git operations, including signed commits, work:

```
export SSH_AUTH_SOCK=<winning-socket>
```

Prefer `~/.ssh/ssh_auth_sock` when it works — it stays valid across reconnections. If no agent is running, or none could be given a working key, say so clearly and leave it to the human, as in step 4.
