#!/usr/bin/env runhaskell

import System.Process
import System.Environment

avoid = [ 
   "127.0.0.1"
 , "192.168.5.10"  -- bogus router at friend's office
 ]

hupCache = rawSystem "sv" ["term", "/etc/service/dnscache"]

main :: IO ()
main = do
  (iface:updown:_) <- getArgs
  let rootFile = "/etc/service/dnscache/root/servers/@"
  dnsIPs <- getEnv "DHCP4_DOMAIN_NAME_SERVERS"
  let out = unlines $ filter (`notElem` avoid) $ words dnsIPs
  writeFile rootFile out
  exit <- hupCache
  return ()

