#!/usr/bin/env runhaskell

import System.Cmd
import System.Environment
import Data.String.Utils (join)

avoid = ["127.0.0.1", "192.168.5.10"]

main :: IO ()
main = do
  let outFile = "/etc/perp/dnscache/root/servers/@"
  args <- getArgs
  let out = join "\n" $ filter (`notElem` avoid) args
  writeFile outFile (out ++ "\n")
  exit <- rawSystem "perpctl" ["-b", "/etc/perp", "t", "dnscache"]
  return ()
