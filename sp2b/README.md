Spike 2b: run s6 as the init/supervisor on a Datum unikernel.

Layout in the image:
  /init                 -> entrypoint: prepares /service, execs s6-svscan
  /sbin/s6-svscan       -> from pkgsStatic.s6
  /sbin/s6-supervise
  /sbin/s6-svstat
  /bin/spikeecho        -> our service binary (prints a banner, then stays alive)
  /service/echo/run     -> service definition s6-supervise runs

What we want to see in the instance logs:
  1. s6-svscan starts and does not crash (no /proc, signals gaps would show here)
  2. s6-supervise starts the service
  3. the service runs and its output appears
  4. svstat-style supervision keeps it up

If s6 dies immediately, its stderr tells us why (this is the whole point of the spike).
