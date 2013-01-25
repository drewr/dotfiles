#!/usr/bin/env runhaskell

import System.Cmd
import System.Environment
import Data.String.Utils (join)

main :: IO ()
main = do
  let outFile = "/etc/perp/dnscache/root/servers/@"
  args <- getArgs
  let out = join "\n" $
              filter (\ip -> ip /= "127.0.0.1") args
  writeFile outFile (out ++ "\n")
  exit <- rawSystem "perpctl" ["-b", "/etc/perp", "t", "dnscache"]
  return ()
