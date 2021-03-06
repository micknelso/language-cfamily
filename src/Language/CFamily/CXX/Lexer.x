-- ----------------------------------------------------------------------------
-- Module      :  Lexer.x
-- Copyright   :  (c) 2016 Mick Nelso
--                (c) 2008 Benedikt Huber
--                (c) 2005 Duncan Coutts
--                (c) [1999..2004] Manuel M T Chakravarty               
-- License     :  BSD3
-- Maintainer  :  micknelso@gmail.com
-- Portability :  portable
--
-- Lexer for C++ files, after being processed by the C++ preprocessor.
--
-- ----------------------------------------------------------------------------

{
module Language.CFamily.CXX.Lexer where

import Language.CFamily.Constants
import Language.CFamily.ParserMonad
import Language.CFamily.Token

import Language.CFamily.Data.Ident
import Language.CFamily.Data.InputStream
import Language.CFamily.Data.Position

import Control.Monad

import Data.Char hiding (readLitChar)
import Data.Word
}

-- 2.2 Phases of Translation [ISO-C++2014]
--
--   1a. Phsyical source characters are mapped to the Basic Source Character Set.
--   1b. Trigraph sequences are replaced.
--   1c. Any physical source file character not in the Basic Source Character Set
--       is replaced by the universal-character-name (ucn) that designates the 
--       character.
--
--   2.  Instances of backslash (\) immediately followed by new-line are deleted,
--       splicing lines together.
-- 
--   3a. The source file is decomposed into preprocessing tokens.
--   3b. Comments are replaced by a single space.
--
--   4a. Preprocessing directives are executed, macro invocations are expanded, and
--       _Pragma unary operator expressions are executed.
--   4b. All preprocessing directives are deleted.
--
--   5.  Each source character set member (and escape sequences and ucn's) in 
--       literals are converted to a member of the execution character set.
--
--   6.  Adjacent string literal tokens are concatenated.
--
--   THIS LEXER BEGINS HERE:
--
--   7.  The preprocessed source is converted into tokens.

$eol                             = \n

$whiteSpace                      = [\ \t \n \v \f]

$hexadecimalDigit                = [0-9 a-f A-F]
$nonDigit                        = [A-Z a-z _]
$digit                           = 0-9
$nonzeroDigit                    = 1-9
$octalDigit                      = 0-7
$binaryDigit                     = 0-1

$identifierImplDef               = \$                          -- GNU extension

$unsignedSuffix                  = [u U]
$longSuffix                      = [l L]

$simpleEscapeSequence            = [\' \" \? \\ a b f n r t v]
$cChar                           = . # [\' \\ \n]

$sign                            = [\+ \-]
$floatingSuffix                  = [f l F L]

$sChar                           = . # [\" \\ \n]
$rChar                           = [. \n] # [\)]                    -- MCNFIXME: bogus because we can nest parens
$dChar                           = . # [\ \( \) \\ \t \v \f \n]

$inFileName                      = . # [\\ \"]

-- Section 2.5 "Preprocessing tokens", Clause 2 [ISO-C++2014]

@whiteSpace                      = $whiteSpace+

-- Section 2.3 "Character sets", Clause 2 [ISO-C++2014]

@hexQuad                         = $hexadecimalDigit{4}
@universalCharacterName          = (\\u@hexQuad)|(\\U@hexQuad{2})

-- Section 2.11 "Identifiers" [ISO-C++2014]

@identifierNondigit              = $nonDigit|@universalCharacterName|$identifierImplDef
@identifier                      = @identifierNondigit(@identifierNondigit|$digit)*

-- Section 2.14.2 "Integer literals" [ISO-C++2014]

@longLongSuffix                  = (ll)|(LL)
@integerSuffix                   = ($unsignedSuffix($longSuffix|@longLongSuffix)?)|(($longSuffix|@longLongSuffix)$unsignedSuffix?)
@binaryLiteral                   = ((0b)|(0B))$binaryDigit((\'$binaryDigit)|$binaryDigit)*@integerSuffix?
@hexadecimalLiteral              = ((0x)|(0X))$hexadecimalDigit((\'$hexadecimalDigit)|$hexadecimalDigit)*@integerSuffix?
@octalLiteral                    = 0((\'$octalDigit)|$octalDigit)*@integerSuffix?
@decimalLiteral                  = $nonzeroDigit((\'$digit)|$digit)*@integerSuffix?
@integerLiteral                  = (@decimalLiteral|@octalLiteral|@hexadecimalLiteral|@binaryLiteral)

-- Section 2.14.3 "Character literals" [ISO-C++2014]

@simpleEscapeSequence            = \\$simpleEscapeSequence
@octalEscapeSequence             = \\$octalDigit{1,3}
@hexadecimalEscapeSequence       = \\x$hexadecimalDigit+
@escapeSequence                  = @simpleEscapeSequence|@octalEscapeSequence|@hexadecimalEscapeSequence
@cChar                           = $cChar|@escapeSequence|@universalCharacterName
@cCharSequence                   = @cChar{2,}
@ordinary1CharLiteral            = \'@cChar\'
@ordinary2CharLiteral            = \'@cCharSequence\'
@type16CharLiteral               = u\'@cChar\'
@type32CharLiteral               = U\'@cChar\'
@type1632CharLiteral_FAIL        = (u|U)\'@cCharSequence\'
@wide1CharLiteral                = L\'@cChar\'
@wide2CharLiteral                = L\'@cCharSequence\'
@characterLiteral                = @ordinary1CharLiteral|@ordinary2CharLiteral|@type16CharLiteral|@type32CharLiteral|@wide1CharLiteral|@wide2CharLiteral

-- Section 2.14.4 "Floating literals" [ISO-C++2014]

@digitSequence                   = $digit((\'$digit)|$digit)*
@exponentPart                    = (e|E)$sign?@digitSequence
@fractionalConstant              = (@digitSequence?\.@digitSequence)|(@digitSequence\.)
@floatingLiteral                 = (@fractionalConstant@exponentPart?$floatingSuffix?)|(@digitSequence@exponentPart$floatingSuffix?)

-- Section 2.14.5 "String literals" [ISO-C++2014]

@sChar                           = $sChar|@escapeSequence|@universalCharacterName
@sCharSequence                   = @sChar+
@rCharSequence                   = $rChar+
@dCharSequence                   = $dChar{1,9}
@encodingPrefix                  = (u8)|u|U|L
@rawStringLiteral                = @encodingPrefix?R\"@dCharSequence?\(@rCharSequence?\)@dCharSequence?\"
@cookedStringLiteral             = @encodingPrefix?\"@sCharSequence?\"
@stringLiteral                   = @rawStringLiteral|@cookedStringLiteral

-- Section 2.14.7 "Pointer literals" [ISO-C++2014]

@pointerLiteral                  = nullptr

-- Section 2.14.8 "User-defined literals" [ISO-C++2014]

@udSuffix                        = @identifier
@userDefinedBinaryLiteral        = @binaryLiteral@udSuffix
@userDefinedHexadecimalLiteral   = @hexadecimalLiteral@udSuffix
@userDefinedOctalLiteral         = @octalLiteral@udSuffix
@userDefinedDecimalLiteral       = @decimalLiteral@udSuffix
@userDefinedIntegerLiteral       = (@decimalLiteral)|(@octalLiteral)|(@hexadecimalLiteral)|(@binaryLiteral)@udSuffix
@userDefinedOrdinary1CharLiteral = @ordinary1CharLiteral@udSuffix
@userDefinedOrdinary2CharLiteral = @ordinary2CharLiteral@udSuffix
@userDefinedType16CharLiteral    = @type16CharLiteral@udSuffix
@userDefinedType32CharLiteral    = @type32CharLiteral@udSuffix
@userDefinedWide1CharLiteral     = @wide1CharLiteral@udSuffix
@userDefinedWide2CharLiteral     = @wide2CharLiteral@udSuffix
@userDefinedCharacterLiteral     = @characterLiteral@udSuffix
@userDefinedFloatingLiteral      = ((@fractionalConstant@exponentPart?)|(@digitSequence@exponentPart@))@udSuffix
@userDefinedRawStringLiteral     = @rawStringLiteral@udSuffix
@userDefinedCookedStringLiteral  = @cookedStringLiteral@udSuffix
@userDefinedStringLiteral        = @stringLiteral@udSuffix
@userDefinedLiteral              = @userDefinedIntegerLiteral|@userDefinedFloatingLiteral|@userDefinedStringLiteral|@userDefinedCharacterLiteral

-- preprocessor directives

@fileName                        = \"$inFileName*\"
@lineDirective                   = \#@whiteSpace@decimalLiteral@whiteSpace@fileName?(@decimalLiteral@whiteSpace)*
@pragmaDirective                 = \#@whiteSpace"pragma".*$eol
@identDirective                  = \#@whiteSpace"ident".*$eol

-- ----------------------------------------------------------------------------

tokens :-

@whiteSpace                      ;

@identDirective                  ;
@pragmaDirective                 ;
@lineDirective                   { doLineDirective }

@identifier                      { doIdentifier }

@binaryLiteral                   { doIntegerLiteral False  2 }
@octalLiteral                    { doIntegerLiteral False  8 }
@decimalLiteral                  { doIntegerLiteral False 10 }
@hexadecimalLiteral              { doIntegerLiteral False 16 }

@ordinary1CharLiteral            { doCharLiteral False False LitCharOrdinary }
@ordinary2CharLiteral            { doCharLiteral False True  LitCharOrdinary }
@type16CharLiteral               { doCharLiteral False False LitChar16T      }
@type32CharLiteral               { doCharLiteral False False LitChar32T      }
@type1632CharLiteral_FAIL        { token_fail "char16_t/char32_t character literals cannot be multicharacter" }
@wide1CharLiteral                { doCharLiteral False False LitCharWide     }
@wide2CharLiteral                { doCharLiteral False True  LitCharWide     }

@floatingLiteral                 { doFloatLiteral False }

@rawStringLiteral                { doStringLiteral False True  }
@cookedStringLiteral             { doStringLiteral False False }

@pointerLiteral                  { token_ 7 TokLitPtr }

@userDefinedBinaryLiteral        { doIntegerLiteral True  2 }
@userDefinedOctalLiteral         { doIntegerLiteral True  8 }
@userDefinedDecimalLiteral       { doIntegerLiteral True 10 }
@userDefinedHexadecimalLiteral   { doIntegerLiteral True 16 }

@userDefinedOrdinary1CharLiteral { doCharLiteral True False LitCharOrdinary }
@userDefinedOrdinary2CharLiteral { doCharLiteral True True  LitCharOrdinary }
@userDefinedType16CharLiteral    { doCharLiteral True False LitChar16T      }
@userDefinedType32CharLiteral    { doCharLiteral True False LitChar32T      }
@userDefinedWide1CharLiteral     { doCharLiteral True False LitCharWide     }
@userDefinedWide2CharLiteral     { doCharLiteral True True  LitCharWide     }

@userDefinedFloatingLiteral      { doFloatLiteral True }

@userDefinedRawStringLiteral     { doStringLiteral True True  }
@userDefinedCookedStringLiteral  { doStringLiteral True False }

-- Section 2.13 "Operators and punctuators" [ISO-C++-2014]
--
"{"      { token_ 1 TokBraceL              }
"}"      { token_ 1 TokBraceR              }
"["      { token_ 1 TokBracketL            }
"]"      { token_ 1 TokBracketR            }
"("      { token_ 1 TokParenL              }
")"      { token_ 1 TokParenR              }
"<:"     { token_ 2 TokBracketL            }
":>"     { token_ 2 TokBracketR            }
"<%"     { token_ 2 TokBraceL              }
"%>"     { token_ 2 TokBraceR              }
";"      { token_ 1 TokSemicolon           }
":"      { token_ 1 TokColon               }
"..."    { token_ 3 TokEllipsis            }
"?"      { token_ 1 TokQuestion            }
"::"     { token_ 2 TokColonColon          }
"."      { token_ 1 TokDot                 }
".*"     { token_ 2 TokDotStar             }
"+"      { token_ 1 TokPlus                }
"-"      { token_ 1 TokMinus               }
"*"      { token_ 1 TokStar                }
"/"      { token_ 1 TokSlash               }
"%"      { token_ 1 TokPercent             }
"^"      { token_ 1 TokHat                 }
"&"      { token_ 1 TokAmpersand           }
"|"      { token_ 1 TokBar                 }
"~"      { token_ 1 TokTilde               }
"="      { token_ 1 TokEqual               }
"!"      { token_ 1 TokExclamation         }
"<"      { token_ 1 TokLess                }
">"      { token_ 1 TokGreater             }
"+="     { token_ 2 TokPlusEqual           }
"-="     { token_ 2 TokMinusEqual          }
"*="     { token_ 2 TokStarEqual           }
"/="     { token_ 2 TokSlashEqual          }
"%="     { token_ 2 TokPercentEqual        }
"^="     { token_ 2 TokHatEqual            }
"&="     { token_ 2 TokAmpersandEqual      }
"|="     { token_ 2 TokBarEqual            }
"<<"     { token_ 2 TokLessLess            }
">>"     { token_ 2 TokGreaterGreater      }
">>="    { token_ 3 TokGreaterGreaterEqual }
"<<="    { token_ 3 TokLessLessEqual       }
"=="     { token_ 2 TokEqualEqual          }
"!="     { token_ 2 TokExclamationEqual    }
"<="     { token_ 2 TokLessEqual           }
">="     { token_ 2 TokGreaterEqual        }
"&&"     { token_ 2 TokAmpersandAmpersand  }
"||"     { token_ 2 TokBarBar              }
"++"     { token_ 2 TokPlusPlus            }
"--"     { token_ 2 TokMinusMinus          }
","      { token_ 1 TokComma               }
"->*"    { token_ 3 TokHyphenGreaterStar   }
"->"     { token_ 2 TokHyphenGreater       }
"and"    { token_ 3 TokAmpersandAmpersand  }
"and_eq" { token_ 6 TokAmpersandEqual      }
"bitand" { token_ 6 TokAmpersand           }
"bitor"  { token_ 5 TokBar                 }
"compl"  { token_ 5 TokTilde               }
"not"    { token_ 3 TokExclamation         }
"not_eq" { token_ 6 TokExclamationEqual    }
"or"     { token_ 2 TokBarBar              }
"or_eq"  { token_ 5 TokBarEqual            }
"xor"    { token_ 3 TokHat                 } 
"xor_eq" { token_ 6 TokHatEqual            }


{
-- We use the odd looking list of string patterns here rather than normal
-- string literals since GHC converts the latter into a sequence of string
-- comparisons (ie a linear search) but it translates the former using its
-- effecient pattern matching which gives us the expected radix-style search.
-- This change makes a significant performance difference [chak]
--
idkwtok ('a' : 'l' : 'i' : 'g' : 'n' : 'a' : 's' : []) = tok 7 TokAlignas
idkwtok ('a' : 'l' : 'i' : 'g' : 'n' : 'o' : 'f' : []) = tok 7 TokAlignof
idkwtok ('a' : 's' : 'm' : []) = tok 3 TokAsm
idkwtok ('a' : 'u' : 't' : 'o' : []) = tok 4 TokAuto
idkwtok ('b' : 'o' : 'o' : 'l' : []) = tok 4 TokBool
idkwtok ('b' : 'r' : 'e' : 'a' : 'k' : []) = tok 5 TokBreak
idkwtok ('c' : 'a' : 's' : 'e' : []) = tok 4 TokCase
idkwtok ('c' : 'a' : 't' : 'c' : 'h' : []) = tok 5 TokCatch
idkwtok ('c' : 'h' : 'a' : 'r' : []) = tok 4 TokChar
idkwtok ('c' : 'h' : 'a' : 'r' : '1' : '6' : '_' : 't' : []) = tok 8 TokChar16
idkwtok ('c' : 'h' : 'a' : 'r' : '3' : '2' : '_' : 't' : []) = tok 8 TokChar32
idkwtok ('c' : 'l' : 'a' : 's' : 's' : []) = tok 5 TokClass
idkwtok ('c' : 'o' : 'n' : 's' : 't' : []) = tok 5 TokConst
idkwtok ('c' : 'o' : 'n' : 's' : 't' : 'e' : 'x' : 'p' : 'r' : []) = tok 9 TokConstExpr
idkwtok ('c' : 'o' : 'n' : 's' : 't' : '_' : 'c' : 'a' : 's' : 't' : []) = tok 10 TokConstCast
idkwtok ('c' : 'o' : 'n' : 't' : 'i' : 'n' : 'u' : 'e' : []) = tok 8 TokContinue
idkwtok ('d' : 'e' : 'c' : 'l' : 't' : 'y' : 'p' : 'e' : []) = tok 8 TokDeclType
idkwtok ('d' : 'e' : 'f' : 'a' : 'u' : 'l' : 't' : []) = tok 7 TokDefault
idkwtok ('d' : 'e' : 'l' : 'e' : 't' : 'e' : []) = tok 6 TokDelete
idkwtok ('d' : 'o' : []) = tok 2 TokDo
idkwtok ('d' : 'o' : 'u' : 'b' : 'l' : 'e' : []) = tok 6 TokDouble
idkwtok ('d' : 'y' : 'n' : 'a' : 'm' : 'i' : 'c' : '_' : 'c' : 'a' : 's' : 't' : []) = tok 12 TokDynCast
idkwtok ('e' : 'l' : 's' : 'e' : []) = tok 4 TokElse
idkwtok ('e' : 'n' : 'u' : 'm' : []) = tok 4 TokEnum
idkwtok ('e' : 'x' : 'p' : 'l' : 'i' : 'c' : 'i' : 't' : []) = tok 8 TokExplicit
idkwtok ('e' : 'x' : 'p' : 'o' : 'r' : 't' : []) = tok 6 TokExport
idkwtok ('e' : 'x' : 't' : 'e' : 'r' : 'n' : []) = tok 6 TokExtern
idkwtok ('f' : 'a' : 'l' : 's' : 'e' : []) = tok 5 TokFalse
idkwtok ('f' : 'l' : 'o' : 'a' : 't' : []) = tok 5 TokFloat
idkwtok ('f' : 'o' : 'r' : []) = tok 3 TokFor
idkwtok ('f' : 'r' : 'i' : 'e' : 'n' : 'd' : []) = tok 6 TokFriend
idkwtok ('g' : 'o' : 't' : 'o' : []) = tok 4 TokGoto
idkwtok ('i' : 'f' : []) = tok 2 TokIf
idkwtok ('i' : 'n' : 'l' : 'i' : 'n' : 'e' : []) = tok 6 TokInline
idkwtok ('i' : 'n' : 't' : []) = tok 3 TokInt
idkwtok ('l' : 'o' : 'n' : 'g' : []) = tok 4 TokLong
idkwtok ('m' : 'u' : 't' : 'a' : 'b' : 'l' : 'e' : []) = tok 7 TokMutable
idkwtok ('n' : 'a' : 'm' : 'e' : 's' : 'p' : 'a' : 'c' : 'e' : []) = tok 9 TokNamespace
idkwtok ('n' : 'e' : 'w' : []) = tok 3 TokNew
idkwtok ('n' : 'o' : 'e' : 'x' : 'c' : 'e' : 'p' : 't' : []) = tok 8 TokNoExcept
idkwtok ('o' : 'p' : 'e' : 'r' : 'a' : 't' : 'o' : 'r' : []) = tok 8 TokOperator
idkwtok ('p' : 'r' : 'i' : 'v' : 'a' : 't' : 'e' : []) = tok 7 TokPrivate
idkwtok ('p' : 'r' : 'o' : 't' : 'e' : 'c' : 't' : 'e' : 'd' : []) = tok 9 TokProtected
idkwtok ('p' : 'u' : 'b' : 'l' : 'i' : 'c' : []) = tok 6 TokPublic
idkwtok ('r' : 'e' : 'g' : 'i' : 's' : 't' : 'e' : 'r' : []) = tok 8 TokRegister
idkwtok ('r' : 'e' : 'i' : 'n' : 't' : 'e' : 'r' : 'p' : 'r' : 'e' : 't' : '_' : 'c' : 'a' : 's' : 't' : []) = tok 16 TokReinterpretCast
idkwtok ('r' : 'e' : 's' : 't' : 'r' : 'i' : 'c' : 't' : []) = tok 8 TokRestrict
idkwtok ('r' : 'e' : 't' : 'u' : 'r' : 'n' : []) = tok 6 TokReturn
idkwtok ('s' : 'h' : 'o' : 'r' : 't' : []) = tok 5 TokShort
idkwtok ('s' : 'i' : 'g' : 'n' : 'e' : 'd' : []) = tok 6 TokSigned
idkwtok ('s' : 'i' : 'z' : 'e' : 'o' : 'f' : []) = tok 6 TokSizeof
idkwtok ('s' : 't' : 'a' : 't' : 'i' : 'c' : []) = tok 6 TokStatic
idkwtok ('s' : 't' : 'a' : 't' : 'i' : 'c' : '_' : 'a' : 's' : 's' : 'e' : 'r' : 't' : []) = tok 13 TokStaticAssert
idkwtok ('s' : 't' : 'a' : 't' : 'i' : 'c' : '_' : 'c' : 'a' : 's' : 't' : []) = tok 11 TokStaticCast
idkwtok ('s' : 't' : 'r' : 'u' : 'c' : 't' : []) = tok 6 TokStruct
idkwtok ('s' : 'w' : 'i' : 't' : 'c' : 'h' : []) = tok 6 TokSwitch
idkwtok ('t' : 'e' : 'm' : 'p' : 'l' : 'a' : 't' : 'e' : []) = tok 8 TokTemplate
idkwtok ('t' : 'h' : 'i' : 's' : []) = tok 4 TokThis
idkwtok ('t' : 'h' : 'r' : 'e' : 'a' : 'd' : '_' : 'l' : 'o' : 'c' : 'a' : 'l' : []) = tok 12 TokThreadLocal
idkwtok ('t' : 'h' : 'r' : 'o' : 'w' : []) = tok 5 TokThrow
idkwtok ('t' : 'r' : 'u' : 'e' : []) = tok 4 TokTrue
idkwtok ('t' : 'y' : 'p' : 'e' : 'd' : 'e' : 'f' : []) = tok 7 TokTypedef
idkwtok ('t' : 'y' : 'p' : 'e' : 'i' : 'd' : []) = tok 6 TokTypeid
idkwtok ('t' : 'y' : 'p' : 'e' : 'n' : 'a' : 'm' : 'e' : []) = tok 8 TokTypename
idkwtok ('u' : 'n' : 'i' : 'o' : 'n' : []) = tok 5 TokUnion
idkwtok ('u' : 'n' : 's' : 'i' : 'g' : 'n' : 'e' : 'd' : []) = tok 8 TokUnsigned
idkwtok ('u' : 's' : 'i' : 'n' : 'g' : []) = tok 5 TokUsing
idkwtok ('v' : 'i' : 'r' : 't' : 'u' : 'a' : 'l' : []) = tok 7 TokVirtual
idkwtok ('v' : 'o' : 'i' : 'd' : []) = tok 4 TokVoid
idkwtok ('v' : 'o' : 'l' : 'a' : 't' : 'i' : 'l' : 'e' : []) = tok 8 TokVolatile
idkwtok ('w' : 'c' : 'h' : 'a' : 'r' : '_' : 't' : []) = tok 7 TokWChar
idkwtok ('w' : 'h' : 'i' : 'l' : 'e' : []) = tok 5 TokWhile
idkwtok cs = \pos -> do
   name <- getNewName
   let len = case length cs of l -> l
   let ident = mkIdent pos cs name
   tyident <- isTypeIdent ident
   if tyident
      then
         return (TokTyIdent (pos,len) ident)
      else
         return (TokIdent   (pos,len) ident)

ignoreAttribute
   :: P ()
ignoreAttribute = skipTokens (0 :: Int)
   where
      skipTokens
         :: Int
         -> P ()
      skipTokens n = do
         tok' <- lexToken' False
         case tok' of
            TokParenR _ | n == 1    -> return ()
                         | otherwise -> skipTokens (n-1)
            TokParenL _             -> skipTokens (n+1)
            _                        -> skipTokens n

-- there is a problem with ignored tokens here (that aren't skipped)
-- consider
-- 1 > int x;
-- 2 > LINE "ex.c" 4
-- 4 > int y;
-- when we get to LINE, we have [int (1,1),x (1,4)] in the token cache.
-- Now we run
-- > action  (pos 2,0) 14 "LINE \"ex.c\" 3\n"
-- which in turn adjusts the position and then calls lexToken again
-- we get `int (pos 4,0)', and have [x (1,4), int (4,1) ] in the token cache (fine)
-- but then, we again call setLastToken when returning and get [int (4,1),int (4,1)] in the token cache (bad)
-- to resolve this, recursive calls invoke lexToken' False.
lexToken
   :: P Token
lexToken = lexToken' True

lexToken'
   :: Bool
   -> P Token
lexToken' modifyCache =
   do
      pos <- getPos
      inp <- getInput
      case alexScan (pos, inp) 0 of
         AlexEOF -> do
            handleEofToken
            return TokEof
         AlexError _ -> lexicalError
         AlexSkip  (pos', inp') _ -> do
            setPos pos'
            setInput inp'
            lexToken' modifyCache
         AlexToken (pos', inp') len action -> do
            setPos pos'
            setInput inp'
            tok' <- action pos len inp
            when modifyCache $ setLastToken tok'
            return tok'

doLineDirective
   :: Position
   -> Int
   -> InputStream
   -> P Token
doLineDirective pos len str = do
   setPos (adjustLineDirective len (takeChars len str) pos)
   lexToken' False

doIdentifier
   :: Position
   -> Int
   -> InputStream
   -> P Token
doIdentifier pos len str = idkwtok (takeChars len str) pos

lexC
   :: (Token -> P a)
   -> P a
lexC cont = do
   tok' <- lexToken
   cont tok'

doIntegerLiteral
   :: Bool
   -> Int
   -> Position
   -> Int
   -> InputStream
   -> P Token
doIntegerLiteral u@False r p = token_plus TokLitInteger (f . readLitInteger u r p) p
   where
      f (Right (Left li)) = Right li
      f (Left str)        = Left  str
      f _                 = error "Lexer.doIntegerLiteral False"
doIntegerLiteral u@True  r p = token_plus TokLitUserDef (f . readLitInteger u r p) p
   where
      f (Right (Right lud)) = Right lud
      f (Left str)          = Left  str
      f _                   = error "Lexer.doIntegerLiteral True"

doCharLiteral
   :: Bool
   -> Bool
   -> LitCharType
   -> Position
   -> Int
   -> InputStream
   -> P Token
doCharLiteral u@False m t p = token TokLitChar    (f . readLitChar u m t p) p
   where
      f (Left x) = x
      f _        = error "Lexer.doCharLiteral False"

doCharLiteral u@True  m t p = token TokLitUserDef (f . readLitChar u m t p) p
   where
      f (Right x) = x
      f _         = error "Lexer.doCharLiteral True"

doFloatLiteral
   :: Bool
   -> Position
   -> Int
   -> InputStream
   -> P Token
doFloatLiteral u@False p = token TokLitFloat   (f . readLitFloat u p) p
   where
      f (Left x) = x
      f _        = error "Lexer.doFloatLiteral False"
doFloatLiteral u@True  p = token TokLitUserDef (f . readLitFloat u p) p
   where
      f (Right x) = x
      f _         = error "Lexer.doFloatLiteral True"

doStringLiteral
   :: Bool
   -> Bool
   -> Position
   -> Int
   -> InputStream
   -> P Token
doStringLiteral u@False r pos = token TokLitString  (f . readLitString u r pos) pos
   where
      f (Left x) = x
      f _        = error "Lexer.doStringLiteral False"
doStringLiteral u@True  r pos = token TokLitUserDef (f . readLitString u r pos) pos
   where
      f (Right x) = x
      f _         = error "Lexer.doStringLiteral True"

tok
   :: Int
   -> (PosLength -> Token)
   -> Position
   -> P Token
tok len tc pos = return (tc (pos,len))

adjustLineDirective
   :: Int
   -> String
   -> Position
   -> Position
adjustLineDirective pragmaLen str pos =
   offs' `seq` fname' `seq` row' `seq` (position offs' fname' row' 1)
   where
      offs'           = (posOffset pos) + pragmaLen
      str'            = dropWhite . drop 1 $ str
      (rowStr, str'') = span isDigit str'
      row'            = read rowStr
      str'''          = dropWhite str''
      fnameStr        = takeWhile (/= '"') . drop 1 $ str'''
      fname           = posFile pos
      dropWhite       = dropWhile (\c -> c == ' ' || c == '\t')
      fname'
         | null str''' || head str''' /= '"' = fname
         -- try and get more sharing of file name strings
         | fnameStr == fname                 = fname
         | otherwise                         = fnameStr

{-# INLINE token_ #-}
-- token that ignores the string
token_
   :: Int
   -> (PosLength -> Token)
   -> Position
   -> Int
   -> InputStream
   -> P Token
token_ len tok' pos _ _ = return (tok' (pos,len))

{-# INLINE token_fail #-}
-- error token
token_fail
   :: String
   -> Position
   -> Int
   -> InputStream
   -> P Token
token_fail errmsg pos _ _ = failP pos [ "Lexical Error !", errmsg ]


{-# INLINE token #-}
-- token that uses the string
token
   :: (PosLength -> a -> Token)
   -> (String -> a)
   -> Position
   -> Int
   -> InputStream
   -> P Token
token tok' read' pos len str = return (tok' (pos,len) (read' $ takeChars len str))

{-# INLINE token_plus #-}
-- token that may fail
token_plus
   :: (PosLength -> a -> Token)
   -> (String -> Either String a)
   -> Position
   -> Int
   -> InputStream
   -> P Token
token_plus tok' read' pos len str =
   case read' (takeChars len str) of
      Left err -> failP pos [ "Lexical error ! ", err ]
      Right ok -> return $! tok' (pos,len) ok

-- -----------------------------------------------------------------------------
-- The input type

type AlexInput = (Position,         -- current position,
                  InputStream)      -- current input string

alexInputPrevChar
   :: AlexInput
   -> Char
alexInputPrevChar _ = error "alexInputPrevChar not used"

-- for alex-3.0
alexGetByte
   :: AlexInput
   -> Maybe (Word8, AlexInput)
alexGetByte (p,is)
   | inputStreamEmpty is = Nothing
   | otherwise           =
      let (b,s) = takeByte is in
         -- this is safe for latin-1, but ugly
         let p' = alexMove p (chr (fromIntegral b)) in
            p' `seq` Just (b, (p', s))

alexGetChar
   :: AlexInput
   -> Maybe (Char,AlexInput)
alexGetChar (p,is)
   | inputStreamEmpty is = Nothing
   | otherwise           =
      let (c,s) = takeChar is in
         let p' = alexMove p c in
            p' `seq` Just (c, (p', s))

alexMove
   :: Position
   -> Char
   -> Position
alexMove pos ' '  = incPos    pos 1
alexMove pos '\n' = retPos    pos
alexMove pos '\r' = incOffset pos 1
alexMove pos _    = incPos    pos 1

lexicalError
   :: P a
lexicalError = do
   pos <- getPos
   (c,_) <- liftM takeChar getInput
   failP pos
         ["Lexical error !"
            , "The character " ++ show c ++ " does not fit here."]

parseError
   :: P a
parseError = do
   tok' <- getLastToken
   failP (posOf tok')
         ["Syntax error !"
            , "The symbol `" ++ show tok' ++ "' does not fit here."]


}
