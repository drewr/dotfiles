---
name: find-ssh-agent
description: Find a forwarded SSH agent socket with live identities and set SSH_AUTH_SOCK
---

First check the stable symlink that ~/.ssh/rc maintains on each inbound SSH connection:

```bash
sock=~/.ssh/ssh_auth_sock
if [ -S "$sock" ]; then
  result=$(SSH_AUTH_SOCK="$sock" ssh-add -l 2>&1)
  if echo "$result" | grep -qE "^[0-9]+ SHA256:"; then
    echo "FOUND (stable symlink): $sock"
    echo "$result"
  fi
fi
```

If that works, skip the scan below and report the stable symlink as the winning socket.

If the symlink is missing or dead, scan all candidate sockets:

```bash
for sock in /tmp/ssh-*/agent.* ~/.ssh/agent/*; do
  [ -S "$sock" ] || continue
  result=$(SSH_AUTH_SOCK="$sock" ssh-add -l 2>&1)
  if echo "$result" | grep -qE "^[0-9]+ SHA256:"; then
    echo "FOUND: $sock"
    echo "$result"
  fi
done
```

Report every socket that returned at least one identity. For each, show the key fingerprints.

Then, for each socket found, test GitHub auth:

```bash
SSH_AUTH_SOCK=<socket> ssh -T git@github.com 2>&1
```

Report which socket authenticates successfully as the user.

Finally, output the exact export command the user should run (or that you should use for the remainder of this session) to make git operations work:

```
export SSH_AUTH_SOCK=<winning-socket>
```

Prefer `~/.ssh/ssh_auth_sock` as the winning socket when it works — it stays valid across reconnections. If no socket is found with identities, say so clearly and suggest the user run `ssh-add` or check that agent forwarding (`-A`) is enabled in their SSH session.
