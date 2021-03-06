-- Simple example demonstrating the API: parse a file, and print its definition table
module Main where
import System.Environment
import System.FilePath
import System.Exit
import System.IO
import Control.Arrow      hiding ((<+>))
import Control.Monad
import Debug.Trace
import Text.PrettyPrint.HughesPJ
import Data.List
import Data.Maybe

import Language.CFamily.C hiding (empty)             -- simple API
import Language.CFamily.Data hiding (empty)
import Language.CFamily.C.Analysis     -- analysis API
import Language.CFamily.C.Analysis.Debug -- debugging printer for analysis
import Language.CFamily.System.GCC   -- preprocessor used


usageMsg :: String -> String
usageMsg prg = render $
  text "Usage:" <+> text prg <+> hsep (map text ["CPP_OPTIONS","input_file.c","[file-pattern]"]) $+$ 
  (nest 4 $
    text "Environment Variables" $+$
      (nest 4 $ 
         hsep [text "TRACE_EVENTS", text "trace definition events as they occur"]
      )
  )

main :: IO ()
main = do
    let usageErr = (hPutStrLn stderr (usageMsg "./ScanFile") >> exitWith (ExitFailure 1))
    args <- getArgs
    when (length args < 1) usageErr
    doTraceDecls <- liftM (("TRACE_EVENTS" `elem`). map fst) getEnvironment

    -- get cpp options and input file
    let (pat,opts,input_file) = case hasExtension (last args) of
                              True -> (Nothing,init args,last args)
                              False -> let (pat,args') = (last args, init args)
                                       in (Just pat,init args',last args')

    -- parse
    ast <- errorOnLeftM "Parse Error" $
      parseCFile (newGCC "gcc") Nothing opts input_file

    -- analyze
    (globals,warnings) <- errorOnLeft "Semantic Error" $ runTrav_ $ traversal doTraceDecls ast

    -- print
    mapM_ (hPutStrLn stderr . show) warnings
--    print $ pretty $ filterGlobalDecls (maybe False (fileOfInterest pat input_file) . fileOfNode) globals


    where
    traversal False ast = analyseAST ast
    traversal True  ast = withExtDeclHandler (analyseAST ast) $ \ext_decl ->
         case declTrace ext_decl of
            "" -> return ()
            s  -> trace s (return ())

    checkResult :: (Show a) => String -> (Either a b) -> IO b
    checkResult label = either (error . (label++) . show) return
    fileOfInterest (Just pat) _ file_name = pat `isInfixOf` file_name
    fileOfInterest Nothing input_file file_name = fileOfInterest' (splitExtensions input_file) (splitExtension file_name)
    fileOfInterest' (c_base,c_ext) (f_base,f_ext) | takeBaseName c_base /= takeBaseName f_base = False
                                                  | f_ext == ".h" && c_ext == ".c"  = False
                                                  | otherwise = True

errorOnLeft :: (Show a) => String -> (Either a b) -> IO b
errorOnLeft msg = either (error . ((msg ++ ": ")++).show) return
errorOnLeftM msg action = action >>= errorOnLeft msg

declTrace :: DeclEvent -> String
declTrace event = render $ case event of
                                CallEvent name (Left i) n -> pretty i <+> (text $ show $ fromJust $ fileOfNode n)
                                CallEvent name (Right i) n -> pretty i <+> (text $ show $ fromJust $ fileOfNode n)
                                DeclEvent i@(FunctionDef _) -> (text "Decl:" <+> (pretty i) <+> file i)
                                _                           -> empty
{-
                                TagEvent tag_def     -> (text "Tag:" <+> (pretty tag_def) <+> file tag_def)
                                DeclEvent ident_decl -> (text "Decl:" <+> (pretty ident_decl) <+> file ident_decl)
                                ParamEvent pd        -> (text "Param:" <+> (pretty pd)  <+> file pd)
                                LocalEvent ident_decl -> (text "Local:" <+> (pretty ident_decl)  <+> file ident_decl)
                                TypeDefEvent tydef   -> (text "Typedef:" <+> (pretty tydef) <+> file tydef)
                                AsmEvent block       -> (text $ "Assembler block")
-}
    where
    file :: (CNode a) => a -> Doc
    file = text . show . posOfNode . nodeInfo
