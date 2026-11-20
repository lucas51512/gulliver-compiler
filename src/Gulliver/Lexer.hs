module Gulliver.Lexer
  ( Token(..)
  , Located(..)
  , tokenize
  , keywords
  ) where

import Data.Char (isAlpha, isAlphaNum, isDigit, isSpace)

data Token
  = TkIdent String
  | TkKeyword String
  | TkInt Int
  | TkSym String
  | TkEOF
  deriving (Show, Eq)

data Located = Located
  { locTok :: Token
  , locLine :: Int
  , locCol :: Int
  } deriving (Show, Eq)

keywords :: [String]
keywords =
  [ "quantum", "fn", "let", "in", "if", "then", "else", "for", "while"
  , "return", "new", "var", "local", "final", "true", "false"
  , "measure", "probability", "superposite", "bitflip", "phaseflip"
  , "entangle", "controlled"
  ]

twoCharSyms :: [String]
twoCharSyms = ["->", "==", "!=", "<=", ">=", "&&", "||", "..", ":="]

oneCharSyms :: String
oneCharSyms = "(){}[],;:+-*/%<>=!."

-- | Convert source text into located tokens. Comments (// and /* */) are skipped.
tokenize :: String -> Either String [Located]
tokenize = go 1 1
  where
    go l c [] = Right [Located TkEOF l c]
    go l c s@(ch:rest)
      | ch == '\n' = go (l + 1) 1 rest
      | isSpace ch = go l (c + 1) rest
      | take 2 s == "//" = go l c (dropWhile (/= '\n') s)
      | take 2 s == "/*" = blockComment l c l (c + 2) (drop 2 s)
      | isDigit ch =
          let (num, after) = span isDigit s
          in (Located (TkInt (read num)) l c :) <$> go l (c + length num) after
      | isAlpha ch || ch == '_' =
          let (word, after) = span (\x -> isAlphaNum x || x == '_') s
              tok = if word `elem` keywords then TkKeyword word else TkIdent word
          in (Located tok l c :) <$> go l (c + length word) after
      | take 2 s `elem` twoCharSyms =
          (Located (TkSym (take 2 s)) l c :) <$> go l (c + 2) (drop 2 s)
      | ch `elem` oneCharSyms =
          (Located (TkSym [ch]) l c :) <$> go l (c + 1) rest
      | otherwise =
          Left $ show l ++ ":" ++ show c ++ ": unexpected character " ++ show ch

    -- (sl, sc) is where the comment opened; (l, col) is the current position.
    blockComment sl sc _ _ [] =
      Left $ show sl ++ ":" ++ show sc ++ ": unterminated block comment"
    blockComment sl sc l col s@(ch:rest)
      | take 2 s == "*/" = go l (col + 2) (drop 2 s)
      | ch == '\n' = blockComment sl sc (l + 1) 1 rest
      | otherwise = blockComment sl sc l (col + 1) rest
