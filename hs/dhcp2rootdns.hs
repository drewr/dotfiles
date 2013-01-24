#!/usr/bin/env runhaskell

import System.Cmd
import System.Environment
import Data.String.Utils (join)

main = do
  let outFile = "/etc/perp/dnscache/root/servers/@"
  ips <- getEnv "new_domain_name_servers"
  let out = join "\n" $
              filter (\ip -> ip /= "127.0.0.1") $
              words ips
  writeFile outFile (out ++ "\n")
  rawSystem "perpctl" ["-b", "/etc/perp", "t", "dnscache"]
