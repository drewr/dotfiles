{ lib, pkgs, ... }:
let
  port = 1234;

  buildkitdConfig = pkgs.writeText "buildkitd.toml" ''
    [worker.oci]
      enabled = true
      snapshotter = "overlayfs"
      gc = true
      gckeepstorage = 8000

    [worker.containerd]
      enabled = false
  '';
in
{
  system.stateVersion = "26.05";

  # Compressed swap in RAM. Without any swap, a large image (nix copy plus
  # BuildKit export) thrashed the page cache until the box stopped responding,
  # with no OOM kill, which wedged builds of the bigger harness images.
  zramSwap.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Access is through SSM Session Manager (amazon-image enables the agent); the
  # security group opens no inbound ports.
  services.openssh.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [ buildkit dumbpipe git ];

  # BuildKit's TCP listener is unauthenticated, so it binds to loopback only and
  # is reached through dumbpipe below. Its root is on the EBS volume (ext4), not
  # tmpfs, which is what broke the build on Datum (sp3/RESULTS.md).
  systemd.services.buildkitd = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ runc buildkit git ];
    serviceConfig = {
      ExecStart = "${pkgs.buildkit}/bin/buildkitd --config ${buildkitdConfig}"
        + " --addr tcp://127.0.0.1:${toString port} --root /var/lib/buildkit"
        + " --oci-worker-net host";
      StateDirectory = "buildkit";
      Delegate = true;
      KillMode = "mixed";
      Restart = "always";
    };
  };

  # Expose BuildKit as an iroh endpoint. The secret key persists on the volume,
  # so the ticket is stable across stop/start; only a ticket holder can connect.
  # The ticket is written to /var/lib/dumbpipe/ticket.
  systemd.services.dumbpipe-buildkit = {
    wantedBy = [ "multi-user.target" ];
    after = [ "buildkitd.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ dumbpipe openssl ];
    script = ''
      cd /var/lib/dumbpipe
      [ -s secret ] || (umask 077 && openssl rand -hex 32 > secret)
      IROH_SECRET=$(cat secret)
      export IROH_SECRET
      dumbpipe generate-ticket > ticket
      exec dumbpipe listen-tcp --host 127.0.0.1:${toString port}
    '';
    serviceConfig = {
      StateDirectory = "dumbpipe";
      StateDirectoryMode = "0700";
      Restart = "always";
    };
  };

  # Stop the instance after 30 idle minutes (no client connected to BuildKit and
  # no build running), so a box started from a phone does not run all month.
  # Shutdown from inside the instance stops it (EC2's default shutdown behaviour).
  systemd.services.buildbox-idle-stop = {
    path = with pkgs; [ iproute2 procps coreutils systemd ];
    script = ''
      stamp=/run/buildbox-last-active
      [ -e "$stamp" ] || touch "$stamp"
      if [ -n "$(ss -Htn state established '( sport = :${toString port} )')" ] \
         || pgrep -x runc >/dev/null; then
        touch "$stamp"
      elif [ $(( $(date +%s) - $(stat -c %Y "$stamp") )) -ge 1800 ]; then
        echo "idle 30m; powering off"
        systemctl poweroff
      fi
    '';
    serviceConfig.Type = "oneshot";
  };
  systemd.timers.buildbox-idle-stop = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "5m"; OnUnitActiveSec = "1m"; };
  };
}
