# Build box

A Datum Compute **general-purpose** instance used to build **unikernel** images.
`datumctl compute build` needs Docker/BuildKit, and there is no Docker on the Mac,
so an instance does the building.

## Why general-purpose (not unikernel)

The build box runs a full `buildkitd`, `runc`, and a Nix toolchain. That needs a
real kernel and a shell, so it is `general-purpose`. The *images it produces* are
unikernel images; only the factory is general-purpose.

## Files

- `workload.yaml` — the build-box workload (nixos-gp image, SYS_ADMIN, ghcr pull secret).
- `setup.sh` — installs tooling and starts `buildkitd` inside the instance.
- `ghcr-secret.yaml.tmpl` — template for the `ghcr-drewr` pull secret.
- `buildkitd.toml` — reference config (not strictly needed; the fix is `--root /dev/shm`).

## Deploy the box

```sh
datumctl apply -f buildbox/workload.yaml
datumctl compute instances            # wait for Available
```

## Push credentials

Private ghcr images need a pull token in a Secret. The token must be able to
**read** packages. Generate and apply:

```sh
GHCR_TOKEN=$(gh auth token)
python3 -c "
import json,base64,os
t=os.environ['GHCR_TOKEN']
a=base64.b64encode(('drewr:'+t).encode()).decode()
print(json.dumps({'auths':{'ghcr.io':{'username':'drewr','password':t,'auth':a}}}))
" > /tmp/dc.json
{ printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: ghcr-drewr-v2\ntype: kubernetes.io/dockerconfigjson\nstringData:\n  .dockerconfigjson: |\n'; sed 's/^/    /' /tmp/dc.json; } \
  | datumctl apply -f -
```

## Build and push an image

Because instances have **no persistence** — any workload replace wipes `/root`,
`/tmp`, and the nix profile — do setup + build in one invocation:

```sh
GHCR_TOKEN=$(gh auth token)
tar czf /tmp/src.tgz -C your-app-dir .        # include Dockerfile.datum
cat /tmp/src.tgz | datumctl compute exec <buildbox-instance> -i -- sh -c '
  cat > /tmp/src.tgz
  # install tooling + start buildkitd (see setup.sh), unpack, compile, then:
  datumctl compute build --push -o ghcr.io/drewr/IMAGE:TAG /root/app
'
```

## Gotchas (all cost real time; kept here)

1. **SYS_ADMIN required.** Without it BuildKit's mounts fail with
   `operation not permitted`. Set `securityContext.capabilities.add` (a list
   *replaces* the class default, so list everything you need).
2. **BuildKit root must be on tmpfs.** The writable fs is **fuse** (no xattrs), so
   the native snapshotter dies with `failed to get xattr ... not supported`. Use
   `--root /dev/shm/buildkit`.
3. **Publish the OCI index, not a flat manifest.** `datumctl compute build --push`
   writes an index with `platform: {x86_64, kraftcloud}`. `crane push` of a
   layout dir flattens it and the platform cannot pull the result.
4. **`nix profile install` one package at a time.** A multi-package install
   collides and drops tools.
5. **Static-PIE for the app.** Unikraft's ELF loader needs PIE. With musl:
   `cc -static-pie -fPIE -O2`. (`pkgsStatic.stdenv.cc` provides
   `x86_64-unknown-linux-musl-cc`.)
