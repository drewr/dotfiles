{ config, pkgs, system, una, ... }:

{
  home.packages = [
    pkgs.pssh
    pkgs.s6-dns
    pkgs.tcping-go
  ];

  home.file = {
    "bin/my-ip".source = ./d/bin/my-ip;
    "bin/latency-tcp".source = ./d/bin/latency-tcp;
    "bin/ping1".source = ./d/bin/ping1;
    "bin/pingn".source = ./d/bin/pingn;
  };
}
