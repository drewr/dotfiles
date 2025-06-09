{ config, pkgs, system, una, ... }:

{
  home.packages = [
    pkgs.s6-dns
    pkgs.tcping-go
  ];

  home.file = {
    "bin/my-ip".source = ./d/bin/my-ip;
    "bin/latency-tcp".source = ./d/bin/latency-tcp;
  };
}
