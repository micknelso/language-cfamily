-----------------------------------------------------------------------------
-- |
-- Module      :  Language.C
-- Copyright   :  (c) 2008 Benedikt Huber
--                [1995..2007]
--                   Manuel M. T. Chakravarty
--                   Duncan Coutts
--                   Betram Felgenhauer
-- License     :  BSD-style
-- Maintainer  : benedikt.huber@gmail.com
-- Stability   : experimental
-- Portability : ghc
--
-- Library for analysing and generating C code.
--
-- See <http://www.sivity.net/projects/language.c>
-----------------------------------------------------------------------------
module Language.CFamily.C (
    parseCFile, parseCFilePre, -- maybe change ?
    module Language.CFamily.Data,
    module Language.CFamily.C.Syntax,
    module Language.CFamily.C.Pretty,
    module Language.CFamily.C.Parser,
)
where

import Language.CFamily.Data
import Language.CFamily.C.Syntax
import Language.CFamily.C.Pretty
import Language.CFamily.C.Parser
import Language.CFamily.C.Parser.Lexer
import Language.CFamily.System.Preprocess

-- | preprocess (if necessary) and parse a C source file
--
--   > Synopsis: parseCFile preprocesssor tmp-dir? cpp-opts file
--   > Example:  parseCFile (newGCC "gcc") Nothing ["-I/usr/include/gtk-2.0"] my-gtk-exts.c
parseCFile 
   :: (Preprocessor cpp) 
   => cpp 
   -> (Maybe FilePath) 
   -> [String] 
   -> FilePath 
   -> IO (Either ParseError CTranslUnit)
parseCFile cpp tmp_dir_opt args input_file = do
    input_stream <- if not (isPreprocessed input_file)
                        then  let cpp_args = (rawCppArgs args input_file) { cppTmpDir = tmp_dir_opt }
                              in  runPreprocessor cpp cpp_args >>= handleCppError
                        else  readInputStream input_file
    return$ parseC input_stream (initPos input_file)
    where
    handleCppError (Left exitCode) = fail $ "Preprocessor failed with " ++ show exitCode
    handleCppError (Right ok)      = return ok

-- | parse an already preprocessed C file
--
--   > Synopsis: parseCFilePre file.i
parseCFilePre :: FilePath -> IO (Either ParseError CTranslUnit)
parseCFilePre file = do
    input_stream <- readInputStream file
    return $ parseC input_stream (initPos file)
