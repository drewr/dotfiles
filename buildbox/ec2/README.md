# EC2 build box

Builds Datum Compute images until Datum offers instance types large enough to
build on-platform (datum-cloud/compute#492). Sizing and cost:
`docs/datum-build-box-ec2.md`.

- **Box:** NixOS on `t3a.medium`, `us-east-2`, profile `datum-sandbox-admin`. The
  whole config is `configuration.nix`, pinned by `flake.lock`. At first boot the
  box applies the config itself from `github:drewr/dotfiles/<rev>?dir=buildbox/ec2`.
- **Access:** no inbound ports. BuildKit listens on `127.0.0.1:1234` and is reached
  only through a dumbpipe (iroh) ticket. Shell access goes through SSM Session Manager.
- **Idle stop:** after 30 minutes with no client and no build, the box powers
  itself off (stopped, not terminated). Start it again from the AWS console or app.
- **Reproducibility:** the image's inputs are pinned by the context's
  `flake.lock` and the base image digest in `Dockerfile.datum`. Building the same
  commit twice gives the same image digest.

## Once

```sh
aws sso login --sso-session Datum
git push origin datum-unikraft-sessions        # the box fetches its config from GitHub
buildbox/ec2/provision.sh launch               # pinned to origin's branch head
buildbox/ec2/provision.sh ticket               # after ~5 min; save it, it is stable
```

The ticket works like a password for BuildKit. Store it as a secret.

## Each build (from any client with dumbpipe and datumctl)

```sh
BUILDBOX_TICKET=... buildbox/ec2/build.sh sp3 ghcr.io/drewr/sp3-node:dev
```

The nix build and the BuildKit solve run on the box. datumctl then packages the
image and pushes it from the client, so the client transfers the image (~300 MB
for sp3) but does no heavy compute.

## Updating the box

Change `configuration.nix`, push, and either `provision.sh terminate && provision.sh
launch`, or run this in an SSM session:
`nixos-rebuild switch --flake 'github:drewr/dotfiles/<rev>?dir=buildbox/ec2#buildbox'`.
A new instance gets a new ticket, because the iroh key lives on the instance's volume.
