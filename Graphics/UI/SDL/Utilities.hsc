#include "SDL.h"
-----------------------------------------------------------------------------
-- |
-- Module      :  Graphics.UI.SDL.General
-- Copyright   :  (c) David Himmelstrup 2005
-- License     :  BSD-like
--
-- Maintainer  :  lemmih@gmail.com
-- Stability   :  provisional
-- Portability :  portable
--
-- Various small functions which makes the binding process easier.
-----------------------------------------------------------------------------
module Graphics.UI.SDL.Utilities where

import Control.Monad (when)
import Data.Int
import Foreign (Bits((.|.), (.&.)))
import Foreign.C

--class Enum a b | a -> b where
--  succ :: a -> a
--  pred :: a -> a
--  toEnum :: b -> a
--  fromEnum :: a -> b
--  enumFromTo :: a -> a -> [a]



intToBool :: Int -> IO Int -> IO Bool
intToBool err action
    = fmap (err/=) action

toBitmask :: (Bits b,Num b) => (a -> b) -> [a] -> b
toBitmask from = foldr (.|.) 0 . map from

fromBitmask :: (Bounded a,Enum a,Bits b,Num b) => (a -> b) -> b -> [a]
fromBitmask fn mask = foldr worker [] lst
    where lst = enumFromTo minBound maxBound
          worker v
            | mask .&. fn v /= 0 = (:) v
            | otherwise          = id

{-
toBitmaskW :: (UnsignedEnum a) => [a] -> Word32
toBitmaskW = foldr (.|.) 0 . map fromEnumW

fromBitmaskW :: (Bounded a,UnsignedEnum a) => Word32 -> [a]
fromBitmaskW mask = foldr worker [] lst
    where lst = enumFromToW minBound maxBound
          worker v
              = if (mask .&. fromEnumW v) /= 0
                   then (:) v
                   else id

-}

fromCInt :: Num a => CInt -> a
fromCInt = fromIntegral

toCInt :: Int -> CInt
toCInt = fromIntegral

foreign import ccall unsafe "SDL_GetError"
  sdlGetError :: IO CString

fatalSDLBool :: String -> IO #{type int} -> IO ()
fatalSDLBool functionName f = do
  i <- f
  when (i < 0) $
    sdlGetError >>= peekCString >>= error . (\msg -> functionName ++ " failed: " ++ msg)