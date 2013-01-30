#!/usr/bin/env runhaskell

import System.Cmd
import System.Environment

main :: IO ()
main = do
  inputs <- getContents
  avoid <- getArgs
  putStr $ (unlines . filter (`notElem` avoid) . words) inputs


