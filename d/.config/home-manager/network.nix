{ config, pkgs, system, una, ... }:

{
  home.packages = [
    pkgs.s6-dns
    pkgs.tcping-go
  ];

  home.file = {
    "bin/my-ip".source = ./d/my-ip;
    "bin/latency-tcp".source = ./d/latency-tcp;
  };
}
