{ config, lib, pkgs, una, ... }:

{
  home.packages = [
    # Lookups: bind's dnsutils output ships dig/nslookup/delv/nsupdate and the
    # host output ships host; taking those two beats the whole bind package.
    # `dnslookup` in default.nix is an unrelated DoH/DoT client.
    pkgs.bind.dnsutils
    pkgs.bind.host
    pkgs.whois

    # Connectivity and transfer.
    pkgs.iperf3
    pkgs.netcat          # libressl nc: netcat-openbsd has no aarch64-darwin build
    pkgs.rsync
    pkgs.socat
    pkgs.wget

    # Latency and path.
    pkgs.gping
    pkgs.mtr             # raw ICMP, so: sudo mtr
    pkgs.pssh
    pkgs.s6-dns
    pkgs.tcping-go

    # Packet / port inspection. Raw sockets need root: sudo tcpdump,
    # sudo nmap -sS, sudo bandwhich. Unprivileged nmap connect scans still work.
    pkgs.bandwhich
    pkgs.nmap
    pkgs.tcpdump
  ]
  # nixpkgs' GNU traceroute is Linux-only; Darwin keeps /usr/sbin/traceroute.
  ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.traceroute ];

  home.file = {
    "bin/my-ip".source = ./d/bin/my-ip;
    "bin/latency-tcp".source = ./d/bin/latency-tcp;
    "bin/ping1".source = ./d/bin/ping1;
    "bin/pingn".source = ./d/bin/pingn;
  };
}
