import XMonad
import XMonad.Hooks.DynamicLog
import XMonad.Hooks.ManageDocks
-- import XMonad.Hooks.EwmhDesktops
import XMonad.Util.Run(spawnPipe)
import XMonad.Util.EZConfig(additionalKeys)
import XMonad.Hooks.SetWMName
import System.IO

main = xmonad defaultConfig
              { manageHook = manageDocks <+> manageHook defaultConfig
              , layoutHook = avoidStruts $ layoutHook defaultConfig
              , modMask    = mod4Mask
              , startupHook = setWMName "LG3D"
              }
