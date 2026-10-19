{ lib, pkgs, ... }:
let
  port = 6379;
  irohPort = 7842;
  state = "/var/lib/agent-meta";
  bucket = "agent-home-007091975061-use1";
  metaUrl = "redis://:$(cat ${state}/redis.pass)@127.0.0.1:${toString port}/1";
in
{
  system.stateVersion = "26.05";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Access is through SSM Session Manager (amazon-image enables the agent); the
  # security group opens no inbound ports.
  services.openssh.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [ juicefs redis dumbpipe awscli2 ];

  # Secrets generated on first boot and kept on the volume: the Redis password
  # (handed to sandboxes through the Datum Secret agent-home) and the iroh key
  # (only its public half leaves the box, in the ticket).
  systemd.services.agent-meta-secrets = {
    wantedBy = [ "multi-user.target" ];
    before = [ "redis-juicefs.service" "agent-meta-dumbpipe.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    path = with pkgs; [ coreutils ];
    script = ''
      install -d -m 0700 ${state}
      cd ${state}
      umask 077
      [ -s redis.pass ] || head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > redis.pass
      [ -s iroh.secret ] || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > iroh.secret
    '';
  };

  # JuiceFS metadata. noeviction: evicting keys would corrupt the filesystem.
  # AOF everysec bounds loss to about a second; nightly dumps go to S3 below.
  services.redis.servers.juicefs = {
    enable = true;
    bind = "127.0.0.1";
    inherit port;
    requirePassFile = "${state}/redis.pass";
    appendOnly = true;
    appendFsync = "everysec";
    settings.maxmemory-policy = "noeviction";
  };
  systemd.services.redis-juicefs = {
    after = [ "agent-meta-secrets.service" ];
    requires = [ "agent-meta-secrets.service" ];
  };

  # Expose Redis as an iroh endpoint with a key that persists on the volume, so
  # the ticket is stable across reboots. The short ticket goes to
  # ${state}/ticket; clients add the relay URL (agent/agent-sandbox).
  systemd.services.agent-meta-dumbpipe = {
    wantedBy = [ "multi-user.target" ];
    after = [ "redis-juicefs.service" "network-online.target" "agent-meta-secrets.service" ];
    wants = [ "network-online.target" ];
    requires = [ "agent-meta-secrets.service" ];
    path = with pkgs; [ dumbpipe coreutils ];
    script = ''
      IROH_SECRET=$(cat ${state}/iroh.secret)
      export IROH_SECRET
      dumbpipe generate-ticket > ${state}/ticket
      exec dumbpipe listen-tcp --host 127.0.0.1:${toString port} \
        --ipv6-addr '[::]:${toString irohPort}' --ipv4-addr 0.0.0.0:${toString irohPort}
    '';
    serviceConfig.Restart = "always";
  };

  # A fixed iroh UDP port, so sandboxes (IPv6-only on Datum) can reach this host
  # directly over its public IPv6 instead of through the n0 relay. The NixOS
  # firewall would otherwise drop it even when the security group allows it.
  networking.firewall.allowedUDPPorts = [ irohPort ];

  # Nightly metadata dump to S3 (the instance role may write meta-backup/ only).
  # With the S3 data, a dump restores the whole filesystem: juicefs load.
  systemd.services.agent-meta-backup = {
    after = [ "redis-juicefs.service" ];
    path = with pkgs; [ juicefs awscli2 gzip coreutils ];
    script = ''
      ts=$(date -u +%Y%m%dT%H%M%SZ)
      juicefs dump "${metaUrl}" --keep-secret-key 2>/dev/null | gzip \
        | aws s3 cp - "s3://${bucket}/meta-backup/agent-home-$ts.json.gz" --region us-east-1
    '';
    serviceConfig.Type = "oneshot";
  };
  systemd.timers.agent-meta-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "1h"; };
  };
}
