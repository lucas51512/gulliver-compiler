module Gulliver.Parser
  ( parseProgram
  , parseExpr
  ) where

import Gulliver.AST
import Gulliver.Lexer

type ParseResult a = Either String a

data PState = PState
  { psToks :: [Located]
  , psPrev :: Token
  }

newtype Parser a = Parser { runParser :: PState -> Either String (a, PState) }

instance Functor Parser where
  fmap f (Parser p) = Parser $ \s -> do
    (a, s') <- p s
    return (f a, s')

instance Applicative Parser where
  pure a = Parser $ \s -> Right (a, s)
  Parser pf <*> Parser pa = Parser $ \s -> do
    (f, s') <- pf s
    (a, s'') <- pa s'
    return (f a, s'')

instance Monad Parser where
  Parser p >>= f = Parser $ \s -> do
    (a, s') <- p s
    runParser (f a) s'

-- | Parse a complete Gulliver program.
parseProgram :: String -> ParseResult Program
parseProgram src = do
  toks <- tokenize src
  (prog, _) <- runParser program (PState toks TkEOF)
  return prog

-- | Parse a single expression sequence (useful for tests and tooling).
parseExpr :: String -> ParseResult Expr
parseExpr src = do
  toks <- tokenize src
  (e, _) <- runParser (seqExpr <* expectEOF) (PState toks TkEOF)
  return e

------------------------------------------------------------------------------
-- Primitives

current :: Parser Located
current = Parser $ \s -> case psToks s of
  [] -> Left "unexpected end of input"
  (t:_) -> Right (t, s)

peek :: Parser Token
peek = locTok <$> current

peek2 :: Parser Token
peek2 = Parser $ \s -> case psToks s of
  (_:t:_) -> Right (locTok t, s)
  _ -> Right (TkEOF, s)

advance :: Parser Token
advance = Parser $ \s -> case psToks s of
  [] -> Left "unexpected end of input"
  [t] -> Right (locTok t, s { psPrev = locTok t })  -- never consume EOF
  (t:ts) -> Right (locTok t, s { psToks = ts, psPrev = locTok t })

previous :: Parser Token
previous = Parser $ \s -> Right (psPrev s, s)

failHere :: String -> Parser a
failHere msg = Parser $ \s -> case psToks s of
  (Located t l c : _) ->
    Left $ show l ++ ":" ++ show c ++ ": " ++ msg ++ " (found " ++ describe t ++ ")"
  [] -> Left msg

describe :: Token -> String
describe t = case t of
  TkIdent n -> "identifier '" ++ n ++ "'"
  TkKeyword k -> "'" ++ k ++ "'"
  TkInt n -> "number " ++ show n
  TkSym s -> "'" ++ s ++ "'"
  TkEOF -> "end of input"

sym :: String -> Parser ()
sym s = do
  t <- peek
  if t == TkSym s then () <$ advance else failHere ("expected '" ++ s ++ "'")

kw :: String -> Parser ()
kw k = do
  t <- peek
  if t == TkKeyword k then () <$ advance else failHere ("expected '" ++ k ++ "'")

isSym :: String -> Parser Bool
isSym s = (== TkSym s) <$> peek

isKw :: String -> Parser Bool
isKw k = (== TkKeyword k) <$> peek

optionalSym :: String -> Parser Bool
optionalSym s = do
  b <- isSym s
  if b then True <$ advance else return False

ident :: Parser String
ident = do
  t <- peek
  case t of
    TkIdent n -> n <$ advance
    _ -> failHere "expected an identifier"

int :: Parser Int
int = do
  t <- peek
  case t of
    TkInt n -> n <$ advance
    _ -> failHere "expected an integer"

expectEOF :: Parser ()
expectEOF = do
  t <- peek
  if t == TkEOF then return () else failHere "unexpected token"

sepByComma :: Parser a -> String -> Parser [a]
sepByComma p close = do
  done <- isSym close
  if done then return [] else go
  where
    go = do
      x <- p
      more <- optionalSym ","
      if more then (x :) <$> go else return [x]

------------------------------------------------------------------------------
-- Program structure

program :: Parser Program
program = do
  defs <- definitions
  t <- peek
  mainExpr <- if t == TkEOF then return Nothing else Just <$> seqExpr
  expectEOF
  return (Program defs mainExpr)

definitions :: Parser [Definition]
definitions = do
  isFn <- isKw "fn"
  isQ <- isKw "quantum"
  if isFn || isQ then (:) <$> definition <*> definitions else return []

definition :: Parser Definition
definition = do
  isQ <- isKw "quantum"
  if isQ then kw "quantum" else return ()
  kw "fn"
  name <- ident
  sym "("
  params <- sepByComma parameter ")"
  sym ")"
  sym "->"
  ret <- parseType
  sym "{"
  body <- seqExpr
  sym "}"
  return $ Definition (if isQ then QuantumFn else ClassicalFn) name params ret body

parameter :: Parser Parameter
parameter = do
  n <- ident
  sym ":"
  Parameter n <$> parseType

parseType :: Parser Type
parseType = do
  t <- peek
  case t of
    TkSym "(" -> do
      _ <- advance
      ts <- sepByComma parseType ")"
      sym ")"
      return $ case ts of
        [] -> TUnit
        [x] -> x
        _ -> TTuple ts
    TkIdent n -> case lookup n typeNames of
      Just ty -> ty <$ advance
      Nothing -> failHere ("unknown type '" ++ n ++ "'")
    _ -> failHere "expected a type"

typeNames :: [(String, Type)]
typeNames =
  [ ("Qubit", TQubit), ("QuantumRegister", TQuantumReg)
  , ("Result", TResult), ("Results", TResults)
  , ("Probability", TProbability)
  , ("Int", TInt), ("Bool", TBool), ("Unit", TUnit)
  ]

------------------------------------------------------------------------------
-- Statement sequences
--
-- Items are separated by ';'. The separator is optional after a closing '}'.
-- A trailing ';' makes the sequence evaluate to Unit, except after 'return'.

seqExpr :: Parser Expr
seqExpr = do
  t <- peek
  if isTerminator t then return UnitLit else do
    items <- go
    return $ case items of
      [e] -> e
      _ -> Seq items
  where
    go = do
      e <- expr
      semi <- optionalSym ";"
      prev <- previous
      t <- peek
      if isTerminator t
        then return (if semi && not (isReturn e) then [e, UnitLit] else [e])
        else if semi || prev == TkSym "}"
          then (e :) <$> go
          else failHere "expected ';'"
    isReturn (Return _) = True
    isReturn _ = False

isTerminator :: Token -> Bool
isTerminator t = t == TkSym "}" || t == TkEOF

------------------------------------------------------------------------------
-- Expressions

expr :: Parser Expr
expr = do
  t <- peek
  t2 <- peek2
  case (t, t2) of
    (TkKeyword k, _) | k `elem` ["var", "local", "final", "let"] -> declExpr
    (TkKeyword "if", _) -> ifExpr
    (TkKeyword "for", _) -> forExpr
    (TkKeyword "while", _) -> whileExpr
    (TkKeyword "return", _) -> returnExpr
    (TkIdent _, TkSym ":=") -> assignExpr
    _ -> orExpr

declExpr :: Parser Expr
declExpr = do
  k <- advance
  let scope = case k of
        TkKeyword "var" -> ScopeVar
        TkKeyword "final" -> ScopeFinal
        _ -> ScopeLocal
  name <- ident
  hasType <- optionalSym ":"
  ty <- if hasType then Just <$> parseType else return Nothing
  sym "="
  val <- expr
  kw "in"
  Decl scope name ty val <$> seqExpr

ifExpr :: Parser Expr
ifExpr = do
  kw "if"
  c <- expr
  kw "then"
  t <- expr
  hasElse <- isKw "else"
  e <- if hasElse then kw "else" >> expr else return UnitLit
  return (If c t e)

forExpr :: Parser Expr
forExpr = do
  kw "for"
  v <- ident
  kw "in"
  lo <- orExpr
  sym ".."
  hi <- orExpr
  body <- block
  return (For v lo hi body)

whileExpr :: Parser Expr
whileExpr = do
  kw "while"
  c <- orExpr
  While c <$> block

block :: Parser Expr
block = do
  sym "{"
  e <- seqExpr
  sym "}"
  return e

returnExpr :: Parser Expr
returnExpr = do
  kw "return"
  t <- peek
  if t == TkSym ";" || isTerminator t then return (Return UnitLit) else Return <$> expr

assignExpr :: Parser Expr
assignExpr = do
  name <- ident
  sym ":="
  Assign name <$> expr

chainl1 :: Parser a -> Parser (Maybe (a -> a -> a)) -> Parser a
chainl1 p op = p >>= rest
  where
    rest x = do
      mo <- op
      case mo of
        Nothing -> return x
        Just f -> p >>= \y -> rest (f x y)

binary :: [(String, BinOp)] -> Parser (Maybe (Expr -> Expr -> Expr))
binary table = do
  t <- peek
  case t of
    TkSym s | Just o <- lookup s table -> Just (BinOp o) <$ advance
    _ -> return Nothing

orExpr :: Parser Expr
orExpr = chainl1 andExpr (binary [("||", Or)])

andExpr :: Parser Expr
andExpr = chainl1 cmpExpr (binary [("&&", And)])

cmpExpr :: Parser Expr
cmpExpr = chainl1 addExpr (binary
  [("==", Eq), ("!=", Neq), ("<=", Le), (">=", Ge), ("<", Lt), (">", Gt)])

addExpr :: Parser Expr
addExpr = chainl1 mulExpr (binary [("+", Add), ("-", Sub)])

mulExpr :: Parser Expr
mulExpr = chainl1 unaryExpr (binary [("*", Mul), ("/", Div), ("%", Mod)])

unaryExpr :: Parser Expr
unaryExpr = do
  t <- peek
  case t of
    TkSym "!" -> advance >> Not <$> unaryExpr
    TkSym "-" -> advance >> Neg <$> unaryExpr
    _ -> postfixExpr

postfixExpr :: Parser Expr
postfixExpr = primary >>= loop
  where
    loop e = do
      t <- peek
      case t of
        TkSym "[" -> do
          _ <- advance
          i <- expr
          sym "]"
          loop (Index e i)
        TkSym "." -> do
          _ <- advance
          n <- int
          loop (TupleIndex e n)
        _ -> return e

legacyGates :: [(String, Gate1)]
legacyGates = [("H", Hadamard), ("X", PauliX), ("Y", PauliY), ("Z", PauliZ)]

gateKeywords :: [(String, Gate1)]
gateKeywords =
  [("superposite", Hadamard), ("bitflip", PauliX), ("phaseflip", PauliZ)]

parens :: Parser a -> Parser a
parens p = sym "(" *> p <* sym ")"

primary :: Parser Expr
primary = do
  t <- peek
  case t of
    TkInt n -> IntLit n <$ advance
    TkKeyword "true" -> BoolLit True <$ advance
    TkKeyword "false" -> BoolLit False <$ advance
    TkSym "(" -> do
      _ <- advance
      done <- isSym ")"
      if done then UnitLit <$ advance else do
        e <- expr
        more <- isSym ","
        if more
          then do
            _ <- advance
            rest <- sepByComma expr ")"
            sym ")"
            return (Tuple (e : rest))
          else e <$ sym ")"
    TkSym "{" -> block
    TkKeyword "new" -> newExpr
    TkKeyword "measure" -> advance >> Measure <$> parens expr
    TkKeyword "probability" -> do
      _ <- advance
      sym "("
      isMeasure <- isKw "measure"
      if isMeasure
        then do
          _ <- advance
          target <- parens expr
          sym ")"
          return (ProbabilityOf target)
        else failHere "probability expects a measurement: probability(measure(...))"
    TkKeyword k | Just g <- lookup k gateKeywords ->
      advance >> Gate g <$> parens expr
    TkKeyword "entangle" -> do
      _ <- advance
      sym "("
      c <- expr
      sym ","
      tg <- expr
      sym ")"
      return (Entangle c tg)
    TkKeyword "controlled" -> do
      _ <- advance
      sym "("
      g <- gateName
      sym ","
      c <- expr
      sym ","
      tg <- expr
      sym ")"
      return (Controlled g c tg)
    TkIdent name -> do
      _ <- advance
      isCall <- isSym "("
      if isCall then call name else return (Var name)
    _ -> failHere "expected an expression"

gateName :: Parser Gate1
gateName = do
  t <- peek
  case t of
    TkKeyword k | Just g <- lookup k gateKeywords -> g <$ advance
    TkIdent n | Just g <- lookup n legacyGates -> g <$ advance
    _ -> failHere "expected a gate (superposite, bitflip, phaseflip, H, X, Y or Z)"

newExpr :: Parser Expr
newExpr = do
  kw "new"
  ty <- ident
  case ty of
    "Qubit" -> sym "(" >> sym ")" >> return NewQubit
    "QuantumRegister" -> NewQReg <$> parens expr
    _ -> failHere ("cannot allocate '" ++ ty ++ "'; use Qubit or QuantumRegister")

call :: String -> Parser Expr
call name = do
  sym "("
  args <- sepByComma expr ")"
  sym ")"
  return $ case (lookup name legacyGates, name, args) of
    (Just g, _, [a]) -> Gate g a
    (_, "CNOT", [c, t]) -> Controlled PauliX c t
    _ -> Call name args
