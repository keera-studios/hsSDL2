#include "SDL.h"
-----------------------------------------------------------------------------
-- |
-- Module      :  Graphics.UI.SDL.Video
-- Copyright   :  (c) David Himmelstrup 2005
-- License     :  BSD-like
--
-- Maintainer  :  lemmih@gmail.com
-- Stability   :  provisional
-- Portability :  portable
--
-----------------------------------------------------------------------------
module Graphics.UI.SDL.Video where {-
    ( Palette
    , Toggle (..)
    , fromToggle
    , toToggle
    , tryGetVideoSurface
    , getVideoSurface
    , tryVideoDriverName
    , videoDriverName
    , getVideoInfo
    , ListModes(..)
    , listModes
    , videoModeOK
    , trySetVideoMode
    , setVideoMode
    , updateRect
    , updateRects
    , tryFlip
    , flip
    , setColors
    , setPalette
    , setGamma
    , tryGetGammaRamp
    , getGammaRamp
    , trySetGammaRamp
    , setGammaRamp
    , mapRGB
    , mapRGBA
    , getRGB
    , getRGBA
    , tryCreateRGBSurface
    , createRGBSurface
    , tryCreateRGBSurfaceEndian
    , createRGBSurfaceEndian
    , tryCreateRGBSurfaceFrom
    , createRGBSurfaceFrom
    , freeSurface
    , lockSurface
    , unlockSurface
    , loadBMP
    , saveBMP
    , setColorKey
    , setAlpha
    , setClipRect
    , getClipRect
    , withClipRect
    , tryConvertSurface
    , convertSurface
    , blitSurface
    , fillRect
    , tryDisplayFormat
    , displayFormat
    , tryDisplayFormatAlpha
    , displayFormatAlpha
    , warpMouse
    , showCursor
    , queryCursorState
    , GLAttr, GLValue
    , glRedSize, glGreenSize, glBlueSize, glAlphaSize, glBufferSize, glDoubleBuffer
    , glDepthSize, glStencilSize, glAccumRedSize, glAccumGreenSize, glAccumBlueSize
    , glAccumAlphaSize, glStereo, glMultiSampleBuffers, glMultiSampleSamples
    , tryGLGetAttribute, glGetAttribute
    , tryGLSetAttribute, glSetAttribute
    , glSwapBuffers
    , mkFinalizedSurface
    ) where


import Foreign (Ptr, FunPtr, Storable(peek), castPtr, plusPtr, nullPtr, newForeignPtr_,
               finalizeForeignPtr, alloca, withForeignPtr, newForeignPtr)
import Foreign.C (peekCString, CString, CInt(..))
import Foreign.Marshal.Array (withArrayLen, peekArray0, peekArray, allocaArray)
import Foreign.Marshal.Utils (with, toBool, maybeWith, maybePeek, fromBool)
import Control.Exception (bracket)
import Data.Word (Word8, Word16, Word32)
import Data.Int (Int32)

import Graphics.UI.SDL.General (unwrapMaybe, unwrapBool)
import Graphics.UI.SDL.Rect (Rect(rectY, rectX, rectW, rectH))
import Graphics.UI.SDL.Color (Pixel(..), Color)
import Graphics.UI.SDL.Types (SurfaceFlag, PixelFormat, PixelFormatStruct, RWops,
                              RWopsStruct, VideoInfo, VideoInfoStruct, Surface, SurfaceStruct)
import qualified Graphics.UI.SDL.RWOps as RW

import Prelude hiding (flip,Enum(..))
-}

import Control.Applicative
import Foreign.C.Types
import Foreign.C
import Foreign
import Control.Exception  (bracket, bracket_)
import Data.Text.Encoding
import qualified Data.Text as T
import Data.Text ( Text )
import Data.ByteString

import Graphics.UI.SDL.Types
import Graphics.UI.SDL.Utilities (toBitmask)

{-
SDL_Window* SDL_CreateWindow(const char* title,
                             int         x,
                             int         y,
                             int         w,
                             int         h,
                             Uint32      flags)
-}
foreign import ccall unsafe "SDL_CreateWindow"
  sdlCreateWindow :: CString -> CInt -> CInt -> CInt -> CInt -> CUInt -> IO (Ptr WindowStruct)

-- XXX: Will SDL2 always copy the given cstring?
withUtf8CString :: String -> (CString -> IO a) -> IO a
withUtf8CString = useAsCString . encodeUtf8 . T.pack

createWindow :: String -> Int -> Int -> Int -> Int -> IO Window
createWindow title x y w h =
  withUtf8CString title $ \cstr -> do
    window <- sdlCreateWindow cstr (fromIntegral x) (fromIntegral y) (fromIntegral w) (fromIntegral h) 0
    newForeignPtr sdlDestroyWindow_finalizer window

withWindow :: String -> Int -> Int -> Int -> Int -> (Window -> IO r) -> IO r
withWindow title x y w h action =
  bracket (createWindow title x y w h) destroyWindow action

data RenderingDevice = Device Int | FirstSupported

data RendererFlag = Software | Accelerated | PresentVSync | TargetTexture

instance Enum RendererFlag where
  fromEnum Software = #{const SDL_RENDERER_SOFTWARE}
  fromEnum Accelerated = #{const SDL_RENDERER_ACCELERATED}
  fromEnum PresentVSync = #{const SDL_RENDERER_PRESENTVSYNC}
  fromEnum TargetTexture = #{const SDL_RENDERER_TARGETTEXTURE}

  toEnum #{const SDL_RENDERER_SOFTWARE} = Software
  toEnum #{const SDL_RENDERER_ACCELERATED} = Accelerated
  toEnum #{const SDL_RENDERER_PRESENTVSYNC} = PresentVSync
  toEnum #{const SDL_RENDERER_TARGETTEXTURE} = TargetTexture
  toEnum _ = error "Graphics.UI.SDL.Video.toEnum (RendererFlag): bad argument"

  succ Software = Accelerated
  succ Accelerated = PresentVSync
  succ PresentVSync = TargetTexture
  succ _ = error "Graphics.UI.SDL.Video.succ (RendererFlag): bad argument"

  pred Accelerated = Software
  pred PresentVSync = Accelerated
  pred TargetTexture = PresentVSync
  pred _ = error "Graphics.UI.SDL.Video.pred (RendererFlag): bad argument"

foreign import ccall unsafe "SDL_CreateRenderer"
  sdlCreateRenderer :: Ptr WindowStruct -> CInt -> CUInt -> IO (Ptr RendererStruct)

createRenderer :: Window -> RenderingDevice -> [RendererFlag] -> IO Renderer
createRenderer w d flags = withForeignPtr w $ \cW -> do
  renderer <- sdlCreateRenderer cW device (toBitmask flags)
  if renderer == nullPtr
    then error "createRenderer: Failed to create rendering context"
    else newForeignPtr sdlDestroyRenderer_finalizer renderer
  where device = case d of
                   Device n -> fromIntegral n
                   FirstSupported -> 0

withRenderer :: Window -> RenderingDevice -> [RendererFlag] -> (Renderer -> IO r) -> IO r
withRenderer w d f a = bracket (createRenderer w d f) destroyRenderer a

foreign import ccall unsafe "&SDL_DestroyRenderer"
  sdlDestroyRenderer_finalizer :: FunPtr (Ptr RendererStruct -> IO ())

destroyRenderer :: Renderer -> IO ()
destroyRenderer = finalizeForeignPtr

foreign import ccall unsafe "SDL_SetRenderDrawColor"
  sdlSetRenderDrawColor :: Ptr RendererStruct -> Word8 -> Word8 -> Word8 -> Word8 -> IO Int

setRenderDrawColor :: Renderer -> Word8 -> Word8 -> Word8 -> Word8 -> IO Bool
setRenderDrawColor renderer r g b a = withForeignPtr renderer $ \cR ->
  (== 0) <$> sdlSetRenderDrawColor cR r g b a

foreign import ccall unsafe "SDL_RenderClear"
  sdlRenderClear :: Ptr RendererStruct -> IO Int

renderClear :: Renderer -> IO Bool
renderClear renderer = withForeignPtr renderer $
  fmap (== 0) . sdlRenderClear

foreign import ccall unsafe "SDL_RenderPresent"
  sdlRenderPresent :: Ptr RendererStruct -> IO Int

renderPresent :: Renderer -> IO Bool
renderPresent renderer = withForeignPtr renderer $
  fmap (== 0) . sdlRenderPresent

-- void SDL_DestroyWindow(SDL_Window* window)

foreign import ccall unsafe "&SDL_DestroyWindow"
  sdlDestroyWindow_finalizer :: FunPtr (Ptr WindowStruct -> IO ())

destroyWindow :: Window -> IO ()
destroyWindow = finalizeForeignPtr

-- void SDL_DisableScreenSaver(void)
foreign import ccall unsafe "SDL_DisableScreenSaver"
  disableScreenSaver :: IO ()

-- void SDL_EnableScreenSaver(void)
foreign import ccall unsafe "SDL_EnableScreenSaver"
  enableScreenSaver :: IO ()

withoutScreenSaver :: IO a -> IO a
withoutScreenSaver = bracket_ disableScreenSaver enableScreenSaver

-- SDL_bool SDL_IsScreenSaverEnabled(void)
foreign import ccall unsafe "SDL_IsScreenSaverEnabled"
  sdlIsScreenSaverEnabled :: IO SDL_bool

isScreenSaverEnabled :: IO Bool
isScreenSaverEnabled = fmap (/= 0) sdlIsScreenSaverEnabled

-- void SDL_HideWindow(SDL_Window* window)
-- void SDL_MaximizeWindow(SDL_Window* window)
-- void SDL_MinimizeWindow(SDL_Window* window)
-- void SDL_RaiseWindow(SDL_Window* window)
-- void SDL_RestoreWindow(SDL_Window* window)
-- void SDL_ShowWindow(SDL_Window* window)

-- int SDL_SetWindowBrightness(SDL_Window* window, float brightness)
-- float SDL_GetWindowBrightness(SDL_Window* window)
-- void* SDL_SetWindowData(SDL_Window* window, const char* name, void* userdata)
-- void* SDL_GetWindowData(SDL_Window* window, const char* name)
-- int SDL_SetWindowDisplayMode(SDL_Window* window, const SDL_DisplayMode* mode)
-- int SDL_GetWindowDisplayMode(SDL_Window* window, SDL_DisplayMode* mode)
-- int SDL_SetWindowFullscreen(SDL_Window* window, Uint32 flags)
-- int SDL_SetWindowGammaRamp(SDL_Window*window,const Uint16* red,const Uint16* green,const Uint16* blue)
-- int SDL_GetWindowGammaRamp(SDL_Window* window,Uint16*red,Uint16*green,Uint16*blue)
-- void SDL_SetWindowGrab(SDL_Window* window, SDL_bool    grabbed)
-- SDL_bool SDL_GetWindowGrab(SDL_Window* window)
-- void SDL_SetWindowIcon(SDL_Window*  window, SDL_Surface* icon)
-- void SDL_SetWindowMaximumSize(SDL_Window* window,int max_w,int max_h)
-- void SDL_GetWindowMaximumSize(SDL_Window* window,int*w,int*h)
-- void SDL_SetWindowMinimumSize(SDL_Window* window,int min_w,int min_h)
-- void SDL_GetWindowMinimumSize(SDL_Window* window, int*w, int*h)
-- void SDL_SetWindowPosition(SDL_Window* window, int x, int y)
-- void SDL_GetWindowPosition(SDL_Window* window, int*x, int*y)
-- void SDL_SetWindowSize(SDL_Window* window, int w, int h)
-- void SDL_GetWindowSize(SDL_Window* window, int*w, int*h)
-- void SDL_SetWindowTitle(SDL_Window* window, const char* title)
-- const char* SDL_GetWindowTitle(SDL_Window* window)




-------------------------------------------------------------------
-- Clipboard Handling

foreign import ccall unsafe "SDL_free"
  sdlFree :: Ptr a -> IO ()

-- char* SDL_GetClipboardText(void)
-- | Use this function to get UTF-8 text from the clipboard.
foreign import ccall unsafe "SDL_GetClipboardText"
  sdlGetClipboardText :: IO CString

getClipboardText :: IO Text
getClipboardText = do
  cstr <- sdlGetClipboardText
  bs <- packCString cstr
  sdlFree cstr
  return $! decodeUtf8 bs

-- int SDL_SetClipboardText(const char* text)
-- | Use this function to put UTF-8 text into the clipboard.
foreign import ccall unsafe "SDL_SetClipboardText"
  sdlSetClipboardText :: CString -> IO CInt

setClipboardText :: Text -> IO ()
setClipboardText txt =
  useAsCString (encodeUtf8 txt) $ \cstr -> do
    n <- sdlSetClipboardText cstr
    -- FIXME: throw an error if n/=0
    return ()


-- SDL_bool SDL_HasClipboardText(void)
-- | Use this function to return a flag indicating whether the clipboard
--   exists and contains a text string that is non-empty.
foreign import ccall unsafe "SDL_HasClipboardText"
  sdlHasClipboardText :: IO SDL_bool

hasClipboardText :: IO Bool
hasClipboardText = fmap (/=0) sdlHasClipboardText

