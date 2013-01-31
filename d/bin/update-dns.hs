#!/usr/bin/env runhaskell

import System.Cmd
import System.Environment

avoid = [ 
   "127.0.0.1"
 , "192.168.5.10"  -- bogus router at friend's office
 ]

hupCache = rawSystem "perpctl" ["-b", "/etc/perp", "t", "dnscache"]

main :: IO ()
main = do
  (iface:updown:_) <- getArgs
  let rootFile = "/etc/perp/dnscache/root/servers/@"
  dnsIPs <- getEnv "DHCP4_DOMAIN_NAME_SERVERS"
  let out = unlines $ filter (`notElem` avoid) $ words dnsIPs
  writeFile rootFile out
  exit <- hupCache
  return ()

