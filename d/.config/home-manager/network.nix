{ config, pkgs, system, una, ... }:

{
  home.packages = [
    (pkgs.writeShellScriptBin "latency-tcp" ''
      #!/bin/sh

      while true; do
        /bin/echo -n `date +%H:%M` \  
        tcping -c 1 dns9.quad9.net:443 | grep -E 'time=|failed:'
        sleep 11
      done
    '')

    (pkgs.writeShellScriptBin "my-ip" ''
      #!/bin/sh

      while true; do
        curl -s ipinfo.io | jq -r ". | \"\(.ip) \(.city) \(.region)/\(.country) \(.org)\"" 2>/dev/null || echo waiting...
        sleep 300;
      done
    '')
  ];
}
