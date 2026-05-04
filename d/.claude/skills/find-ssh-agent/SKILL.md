---
name: find-ssh-agent
description: Find a forwarded SSH agent socket with live identities and set SSH_AUTH_SOCK
---

Run the following bash command to locate all candidate SSH agent sockets:

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

If no socket is found with identities, say so clearly and suggest the user run `ssh-add` or check that agent forwarding (`-A`) is enabled in their SSH session.
