# Diagnosis: is the buildbox instability a Datum Compute problem?

Date: 2026-10-17. Project `project-xx4hh`, org `org-7zr94`, user `draines@datum.net`.
Workload `buildbox`, image `ghcr.io/drewr/nixos-gp:26.05`,
instance type `datumcloud/d1-standard-2`, runtime class `general-purpose`.

## Symptom

While building unikernel images for Spike 3, the `buildbox` container appeared to
reset repeatedly: files written in one `datumctl compute exec` call (`/tmp/dc`,
`/root/sp3`, `~/.docker/config.json`) were missing in the next call, sometimes
within minutes. `datumctl compute exec` interittently returned
`Error: session ended: InstanceNotRunning: The container "buildbox" is not running`,
then recovered on the next call.

## Method

1. Wrote unique markers and recorded `/proc/sys/kernel/random/boot_id` and
   `btime` from `/proc/stat` on each probe.
2. Checked the control plane for events, workload conditions, and instance status.
3. Read the container's cgroup limits and accounting from `/sys/fs/cgroup`.
4. Reproduced the failure deliberately by exceeding the observed limit.

## Findings

### The control plane never saw a restart

* `datumctl get events` returned 304 events, **all** of them
  `InstanceConsoleSession` started/ended. Zero kill, OOM, restart, eviction, or
  backoff events.
* `datumctl get workload buildbox -o yaml` showed a healthy status: `Available`,
  `readyReplicas: 1`, `desiredReplicas: 1`, no degraded conditions.
* The instance name never changed: `buildbox-default-us-central-1-0`.

### The container is memory-capped at the instance type's 2 GiB

```
$ cat /sys/fs/cgroup/memory.max
2147483648            # exactly 2 GiB

$ free -m
Mem:  3936 ...        # the VM reports ~4 GiB, but the container gets 2 GiB

$ cat /sys/fs/cgroup/memory.peak
1587765248            # ~1.48 GiB peak already observed
```

The VM has ~4 GiB, but the container's cgroup is limited to exactly the instance
type's advertised 2 GiB. Memory is enforced per-container via cgroup, not merely
as a VM size.

### Exceeding 2 GiB silently recreates the container

Deliberate reproduction: allocate 2.6 GiB inside the container.

```
$ datumctl compute exec buildbox -- sh -c \
    'dd if=/dev/zero of=/dev/shm/huge bs=1M count=2600'
start
<no further output; exec returns, exit code 0>
```

Immediately afterwards:

```
boot_id   331f9e7b-...  ->  4cf4603e-...     # CHANGED: new sandbox
/root/oom-marker        ->  No such file      # filesystem gone
/proc/stat btime        ->  1792253553        # VM boot time = moment of the alloc
```

Yet at the same moment:

* `datumctl compute instances` still reported `buildbox` `Available`, age `2h`.
* `datumctl compute instances describe` still reported `Age 2h ago`.
* No event, warning, or status change was recorded.

So the sandbox VM (and its container filesystem) is torn down and recreated when
the container exceeds its 2 GiB cgroup limit, and this is invisible to the user
through every surface `datumctl` exposes.

## Conclusion

The instability is **a real gap in Datum Compute's behaviour**, not user error and
not a transient network fault:

1. **Container memory is capped at the instance type's 2 GiB** via
   `memory.max = 2147483648`, even though the VM has ~4 GiB. This is
   undocumented; the docs describe the instance type as "1 vCPU, 2 GiB" without
   saying memory is a hard container cgroup limit.
2. **On exceeding the limit, the container is killed and its sandbox recreated**,
   taking the whole filesystem with it. This contradicts the docs' claim that
   "files written at runtime are lost when Datum replaces an Instance" — here the
   instance is *not* shown as replaced at all.
3. **The recreation is invisible**: no event, no condition, and a stale, incorrect
   `Age` on the instance. An operator has no way to learn that their instance was
   silently recycled or why.

## Consequences for this work

* Any build that needs more than 2 GiB of address space/RSS inside a
  `d1-standard-2` container will be silently recycled mid-build. Node's rootfs
  assembly, `nix` store extraction, and BuildKit all reach that size.
* Detached (`nohup`) work does survive session end (verified: a background job ran
  across several sessions with a constant `boot_id`), but it does **not** survive a
  cgroup OOM.
* A stable build path is needed: either a host with more memory, or a build that
  stays under 2 GiB, or a remote BuildKit that is not subject to this limit.

## Recommendation

* Report to Datum: surface sandbox recreation as an event/condition, correct the
  reported instance `Age`, and document the container memory cap. The docs say
  memory is "2 GiB" for the instance type; they should say it is a hard container
  cgroup limit that recycles the container.
* For this work: do not build inside `d1-standard-2` under load. Use a build host
  with more memory or an external BuildKit.
