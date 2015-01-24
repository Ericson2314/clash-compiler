{-# LANGUAGE TemplateHaskell     #-}

-- | Module that connects all the parts of the CLaSH compiler library
module CLaSH.Driver where

import qualified Control.Concurrent.Supply    as Supply
import           Control.DeepSeq
import           Control.Monad.State          (evalState, get)
import           Data.HashMap.Strict          (HashMap)
import qualified Data.HashMap.Strict          as HashMap
import qualified Data.HashSet                 as HashSet
import           Data.List                    (isSuffixOf)
-- import           Data.Maybe                   (listToMaybe)
import qualified Data.Text.Lazy               as Text
import qualified System.Directory             as Directory
import qualified System.FilePath              as FilePath
import qualified System.IO                    as IO
import           Text.PrettyPrint.Leijen.Text (Doc, hPutDoc)
import           Unbound.LocallyNameless      (name2String)

import           CLaSH.Backend
import           CLaSH.Core.Term              (Term)
import           CLaSH.Core.Type              (Type)
import           CLaSH.Core.TyCon             (TyCon, TyConName)
--import           CLaSH.Driver.TestbenchGen
import           CLaSH.Driver.Types
import           CLaSH.Netlist                (genNetlist)
import           CLaSH.Netlist.Types          (Component (..), HWType)
import           CLaSH.Normalize              (checkNonRecursive, cleanupGraph,
                                               normalize, runNormalization)
import           CLaSH.Primitives.Types
import           CLaSH.Rewrite.Types          (DebugLevel (..))
import           CLaSH.Util

import qualified Data.Time.Clock              as Clock

-- | Create a set of .VHDL files for a set of functions
generateVHDL :: Backend backend
             => BindingMap -- ^ Set of functions
             -> backend
             -> PrimMap -- ^ Primitive / BlackBox Definitions
             -> HashMap TyConName TyCon -- ^ TyCon cache
             -> (HashMap TyConName TyCon -> Type -> Maybe (Either String HWType)) -- ^ Hardcoded 'Type' -> 'HWType' translator
             -> (HashMap TyConName TyCon -> Term -> Term) -- ^ Hardcoded evaluator (delta-reduction)
             -> DebugLevel -- ^ Debug information level for the normalization process
             -> IO ()
generateVHDL bindingsMap vhdlState primMap tcm typeTrans eval dbgLevel = do
  start <- Clock.getCurrentTime

  -- Dependency loading
  prepTime <- start `deepseq` bindingsMap `deepseq` tcm `deepseq` Clock.getCurrentTime
  let prepStartDiff = Clock.diffUTCTime prepTime start
  putStrLn $ "Loading dependencies took " ++ show prepStartDiff

  let topEntities     = HashMap.filterWithKey
                          (\var _ -> isSuffixOf ".topEntity" $ name2String var)
                          bindingsMap

      testInputs      = HashMap.filterWithKey
                          (\var _ -> isSuffixOf ".testInput" $ name2String var)
                          bindingsMap

      expectedOutputs = HashMap.filterWithKey
                          (\var _ -> isSuffixOf ".expectedOutput" $ name2String var)
                          bindingsMap

  let topEntity = case HashMap.toList topEntities of
        [topE] -> topE
        []     -> error $ $(curLoc) ++ "No 'topEntity' found"
        _      -> error $ $(curLoc) ++ "Multiple 'topEntity's found"

  -- Create unique supplies for normalisation and TB generation
  (supplyN,supplyTB) <- Supply.splitSupply
                      . snd
                      . Supply.freshId
                     <$> Supply.newSupply

  let doNorm = do norm <- normalize [fst topEntity]
                  let normChecked = checkNonRecursive (fst topEntity) norm
                  cleanupGraph (fst topEntity) normChecked
      transformedBindings = runNormalization dbgLevel supplyN bindingsMap typeTrans tcm eval doNorm

  -- Normalization
  normTime <- transformedBindings `deepseq` Clock.getCurrentTime
  let prepNormDiff = Clock.diffUTCTime normTime prepTime
  putStrLn $ "Normalisation took " ++ show prepNormDiff

  (netlist, cmpCnt) <- genNetlist Nothing transformedBindings primMap tcm
                       typeTrans Nothing (fst topEntity)

  netlistTime <- netlist `deepseq` Clock.getCurrentTime
  let normNetDiff = Clock.diffUTCTime netlistTime normTime
  putStrLn $ "Netlist generation took " ++ show normNetDiff

  let topComponent = head
                   $ filter (\(Component cName _ _ _ _) ->
                                Text.isSuffixOf (Text.pack "topEntity_0")
                                  cName)
                            netlist

  --(testBench,vhdlState'') <- genTestBench dbgLevel supplyTB primMap
  --                           typeTrans tcm eval vhdlState' cmpCnt bindingsMap
  --                           (listToMaybe $ map fst $ HashMap.toList testInputs)
  --                           (listToMaybe $ map fst $ HashMap.toList expectedOutputs)
  --                           topComponent


  --testBenchTime <- testBench `seq` Clock.getCurrentTime
  --let netTBDiff = Clock.diffUTCTime testBenchTime netlistTime
  --putStrLn $ "Testbench generation took " ++ show netTBDiff

  let vhdlDocs = createVHDL vhdlState netlist --(netlist ++ testBench)
      dir = concat [ "./vhdl/"
                   , takeWhile (/= '.') (name2String $ fst topEntity)
                   , "/"
                   ]
  prepareDir dir
  mapM_ (writePretty dir) vhdlDocs

  end <- vhdlDocs `seq` Clock.getCurrentTime
  let startEndDiff = Clock.diffUTCTime end start
  putStrLn $ "Total compilation took " ++ show startEndDiff

-- | Pretty print Components to VHDL Documents
createVHDL :: Backend backend
           => backend
           -> [Component]
           -> [(String,Doc)]
createVHDL backend components = flip evalState backend $ do
  (vhdlNms,vhdlDocs) <- unzip <$> mapM genVHDL components
  let vhdlNmDocs = zip vhdlNms vhdlDocs
  hwtys <- HashSet.toList <$> extractTypes <$> get
  typesPkg <- mkTyPackage hwtys
  return (("types",typesPkg):vhdlNmDocs)

-- | Prepares the directory for writing VHDL files. This means creating the
--   dir if it does not exist and removing all existing .vhdl files from it.
prepareDir :: String -> IO ()
prepareDir dir = do
  -- Create the dir if needed
  Directory.createDirectoryIfMissing True dir
  -- Find all .vhdl files in the directory
  files <- Directory.getDirectoryContents dir
  let to_remove = filter ((==".vhdl") . FilePath.takeExtension) files
  -- Prepend the dirname to the filenames
  let abs_to_remove = map (FilePath.combine dir) to_remove
  -- Remove the files
  mapM_ Directory.removeFile abs_to_remove

-- | Writes a Pretty Doc file to the given directory
writePretty :: FilePath -> (String, Doc) -> IO ()
writePretty dir (cname, vhdl) = do
  handle <- IO.openFile (dir ++ cname ++ ".vhdl") IO.WriteMode
  IO.hPutStrLn handle "-- Automatically generated VHDL"
  hPutDoc handle vhdl
  IO.hPutStr handle "\n"
  IO.hClose handle
