{-# LANGUAGE CPP #-}
module CLaSH.GHC.Compat.DynFlags where

#if __GLASGOW_HASKELL__ >= 707
import           DynFlags (DynFlags,GeneralFlag)
#else
import           DynFlags (DynFlags,DynFlag)
#endif
import qualified DynFlags

dopt_unset ::
  DynFlags
#if __GLASGOW_HASKELL__ >= 707
  -> GeneralFlag
#else
  -> DynFlag
#endif
  -> DynFlags
#if __GLASGOW_HASKELL__ >= 707
dopt_unset = DynFlags.gopt_unset
#else
dopt_unset = DynFlags.dopt_unset
#endif

dopt_set ::
  DynFlags
#if __GLASGOW_HASKELL__ >= 707
  -> GeneralFlag
#else
  -> DynFlag
#endif
  -> DynFlags
#if __GLASGOW_HASKELL__ >= 707
dopt_set = DynFlags.gopt_set
#else
dopt_set = DynFlags.dopt_set
#endif
