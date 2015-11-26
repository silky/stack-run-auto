{-# LANGUAGE RecordWildCards #-}
module Development.FileModules where

import           Control.Concurrent.Async (mapConcurrently)
import           Control.Concurrent.STM
import           Control.Monad            (forM)
import           Data.String.Utils        (split)
import           Language.Haskell.Exts    (ImportDecl (..),
                                           ModuleHeadAndImports (..),
                                           ModuleName (..), NonGreedy (..),
                                           ParseResult (..), parse)
import qualified STMContainers.Set        as Set
import           System.Directory
import           System.FilePath

fileModulesRecur :: Set.Set String -> FilePath -> IO [String]
fileModulesRecur seen fname = do
    modules <- fileModules fname
    modules' <- flip mapConcurrently modules $ \m -> do
        let pth = takeDirectory fname </> joinPath (split "." m) ++ ".hs"
        isSeen <- atomically $ Set.lookup pth seen
        if isSeen
           then return [m]
           else do
               atomically $ Set.insert pth seen
               isLocalModule <- doesFileExist pth
               if isLocalModule
                   -- If we're hitting a local modules, ignore it on the
                   -- output (this may not be what we want)
                   then fileModulesRecur seen pth
                   else return [m]
    return (concat modules')

fileModules :: FilePath -> IO [String]
fileModules fname = do
    result <- parse <$> readFile fname
    case result of
        (ParseOk (NonGreedy{..})) -> do
            let (ModuleHeadAndImports _ _ mimports) = unNonGreedy
            forM mimports $ \imp ->
                let ModuleName iname = importModule imp
                in return iname
        (ParseFailed _ _) -> error $ "Failed to parse module in " ++ fname