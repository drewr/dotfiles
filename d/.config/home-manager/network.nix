{ config, pkgs, system, una, ... }:

{
  home.file = {
    "bin/my-ip".source = ./d/my-ip;
    "bin/latency-tcp".source = ./d/latency-tcp;
  };
}
