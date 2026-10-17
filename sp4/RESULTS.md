# Spike 4 — SSH into a unikernel instance over iroh

Date: 2026-10-17. Built on the EC2 box (`buildbox/ec2/build.sh sp4 …`).

## Result: PASS (exec and interactive PTY)

dropbear on `127.0.0.1:2222` inside a `unikernel` workload, exposed by
`dumbpipe listen-tcp`; the client uses `ssh -o ProxyCommand="dumbpipe connect
<ticket>"`. No inbound port, no Datum Connect gateway, no login or project.

```
$ ssh … root@sp4 'echo ssh-ok; id; uname -r'
ssh-ok
uid=0(root) gid=0(root) groups=0(root)
6.12.110+

$ ssh -tt … root@sp4          # interactive, under a local pty
~ # tty
/dev/pts/0
~ # stty size
40 120
~ # echo TERM=$TERM
TERM=xterm-256color
```

* The iroh connection goes through the n0 relay (`use1-1.relay.n0.iroh.link`);
  the instance's IPv6-only network reached it without the DNS failures seen on
  the Datum build box (#493), though that was one run, not a soak test.
* The ticket is computed **on the client** from an iroh secret the client
  generated and stored as the Datum Secret `sp4-iroh` (`secretKeyRef` →
  `IROH_SECRET`). The instance printed the same ticket. No log scraping is
  needed to find a session.
* PTY: devpts is mounted (`mode=600,ptmxmode=000`), `/dev/ptmx` is `0666`;
  dropbear allocates `pts/0` and passes the window size and `TERM`.

## Findings

1. **Loopback is down at boot.** `lo` comes up `state DOWN` with no addresses,
   so anything bound to `127.0.0.1` is unreachable and dumbpipe's forward closes
   the stream immediately (`ApplicationClosed`, "connection lost" on the
   client). `init.sh` now runs `ip link set lo up` and adds `127.0.0.1/8` and
   `::1/128` first. Every agent image needs this.
2. **The guest looks like a Linux microVM.** `uname -r` is `6.12.110+`, and
   `ps` shows PID 1 `/init unikraft` alongside `kthreadd` and `kworker/*`
   kernel threads. That would explain true COW `fork`, `/proc`, signals and
   devpts all behaving like Linux. Observation only; not confirmed with Datum.
3. `datumctl connect local` (the project-less tunnel) is not in the released
   datumctl, so dumbpipe stands in. It is the same iroh transport with the same
   no-gateway property; swap it in when the branch lands.
4. Packaging: dumbpipe and dropbear ship as their full nix closure at the
   original `/nix/store` paths (57 MB), with no patchelf, the same approach as
   sp5.
