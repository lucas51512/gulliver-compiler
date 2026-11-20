-- | Type checker with affine resource tracking for quantum values.
--
-- Qubits and registers cannot be cloned. The checker enforces this with an
-- affine discipline:
--
--   * Gates and operands /borrow/ a resource and leave it usable.
--   * 'Measure', binding to another name, passing to a function and returning
--     /move/ (consume) it; using it afterwards is an error.
--   * A qubit cannot be pulled out of a register into a second name, since
--     that would create two handles to one qubit.
--   * Resources may be dropped (affine, not strictly linear).
--
-- The static check covers variables and literal register indices. Anything
-- it cannot decide (e.g. @r[i]@ with a computed @i@) is checked again at
-- run time by the interpreter.
module Gulliver.TypeChecker
  ( TypeError(..)
  , renderTypeError
  , checkProgram
  , inferExprType
  ) where

import Control.Monad (foldM, forM_, unless, when, zipWithM_)
import Control.Monad.State
import qualified Data.Map as Map
import qualified Data.Set as Set

import Gulliver.AST

data TypeError
  = UndefinedVariable String
  | UndefinedFunction String
  | DuplicateDefinition String
  | TypeMismatch String Type Type          -- ^ context, expected, actual
  | ExpectedQuantum String Type            -- ^ context, actual
  | ArityMismatch String Int Int
  | UseAfterConsume String                 -- ^ resource used after it was moved or measured
  | QubitAliasing String
  | SameOperand String
  | QuantumInClassical String
  | AssignImmutable String
  | InvalidScope Scope String Type
  | ConsumedInLoop String
  | NotAResource Type
  deriving (Show, Eq)

renderTypeError :: TypeError -> String
renderTypeError e = case e of
  UndefinedVariable v -> "undefined variable '" ++ v ++ "'"
  UndefinedFunction f -> "undefined function '" ++ f ++ "'"
  DuplicateDefinition f -> "function '" ++ f ++ "' is defined more than once"
  TypeMismatch ctx want got ->
    ctx ++ ": expected " ++ prettyType want ++ " but got " ++ prettyType got
  ExpectedQuantum ctx got ->
    ctx ++ ": expected Qubit or QuantumRegister but got " ++ prettyType got
  ArityMismatch f want got ->
    "function '" ++ f ++ "' expects " ++ show want ++ " argument(s) but got " ++ show got
  UseAfterConsume r ->
    "'" ++ r ++ "' was already measured or moved and cannot be used again (no-cloning)"
  QubitAliasing msg -> msg
  SameOperand op ->
    op ++ " needs two distinct qubits; using the same qubit twice would require cloning it"
  QuantumInClassical what ->
    "quantum operation (" ++ what ++ ") is not allowed in a classical fn; declare it 'quantum fn'"
  AssignImmutable v ->
    "'" ++ v ++ "' is not declared with 'var' and cannot be reassigned"
  InvalidScope s v t ->
    "'" ++ v ++ "': " ++ scopeName s ++ " cannot hold a " ++ prettyType t
      ++ "; quantum resources use 'local' and are governed by the resource checker"
  ConsumedInLoop v ->
    "'" ++ v ++ "' is moved or measured inside a loop, so it could be consumed more than once"
  NotAResource t ->
    "expected a Qubit or QuantumRegister but got " ++ prettyType t
  where
    scopeName s = case s of
      ScopeVar -> "'var'"
      ScopeFinal -> "'final'"
      ScopeLocal -> "'local'"

------------------------------------------------------------------------------

data Binding = Binding
  { bindType :: Type
  , bindMutable :: Bool
  }

data FnSig = FnSig FnKind [Type] Type

data Env = Env
  { envVars :: Map.Map String Binding
  , envFns :: Map.Map String FnSig
  , envClassical :: Bool
  }

-- | A consumed resource: a whole variable, or one literal element of a register.
data Key = Whole String | Elem String Int
  deriving (Show, Eq, Ord)

keyName :: Key -> String
keyName (Whole n) = n
keyName (Elem n _) = n

type TC = StateT (Set.Set Key) (Either TypeError)

throw :: TypeError -> TC a
throw = lift . Left

-- | Check a whole program.
checkProgram :: Program -> Either TypeError ()
checkProgram (Program defs mainE) = do
  sigs <- buildSigs defs
  let base = Env Map.empty sigs False
  forM_ defs (checkDefinition base)
  forM_ mainE $ \e -> evalStateT (infer base e) Set.empty

-- | Infer the type of a closed expression (no user functions); for tooling and tests.
inferExprType :: Expr -> Either TypeError Type
inferExprType e = evalStateT (infer (Env Map.empty Map.empty False) e) Set.empty

buildSigs :: [Definition] -> Either TypeError (Map.Map String FnSig)
buildSigs = foldM add Map.empty
  where
    add m d
      | Map.member (defName d) m = Left (DuplicateDefinition (defName d))
      | otherwise = Right $
          Map.insert (defName d) (FnSig (defKind d) (map paramType (defParams d)) (defRet d)) m

checkDefinition :: Env -> Definition -> Either TypeError ()
checkDefinition base d = do
  let classical = defKind d == ClassicalFn
      what = "classical fn '" ++ defName d ++ "'"
  when classical $ do
    forM_ (defParams d) $ \p ->
      when (isLinear (paramType p)) $ Left (QuantumInClassical (what ++ " parameter '" ++ paramName p ++ "'"))
    when (isLinear (defRet d)) $ Left (QuantumInClassical (what ++ " return type"))
  let vars = Map.fromList [(paramName p, Binding (paramType p) False) | p <- defParams d]
      env = base { envVars = vars, envClassical = classical }
  t <- evalStateT (infer env (defBody d)) Set.empty
  unless (t == defRet d) $
    Left (TypeMismatch ("body of '" ++ defName d ++ "'") (defRet d) t)

------------------------------------------------------------------------------
-- Resource bookkeeping

checkUsableWhole :: String -> TC ()
checkUsableWhole x = do
  s <- get
  when (any ((== x) . keyName) (Set.toList s)) $ throw (UseAfterConsume x)

checkUsableElem :: String -> Int -> TC ()
checkUsableElem r i = do
  s <- get
  when (Set.member (Whole r) s || Set.member (Elem r i) s) $
    throw (UseAfterConsume (r ++ "[" ++ show i ++ "]"))

consume :: Key -> TC ()
consume k = modify (Set.insert k)

-- | Run a scoped body for a freshly bound name: consumption of an outer
-- binding with the same name must not leak into or out of the inner scope.
withScope :: String -> TC a -> TC a
withScope name body = do
  before <- get
  let (shadowed, others) = Set.partition ((== name) . keyName) before
  put others
  r <- body
  after <- get
  put (Set.union shadowed (Set.filter ((/= name) . keyName) after))
  return r

------------------------------------------------------------------------------

lookupVar :: Env -> String -> TC Binding
lookupVar env x = maybe (throw (UndefinedVariable x)) return (Map.lookup x (envVars env))

requireQuantum :: Env -> String -> TC ()
requireQuantum env what = when (envClassical env) $ throw (QuantumInClassical what)

expect :: String -> Type -> Type -> TC ()
expect ctx want got = unless (want == got) $ throw (TypeMismatch ctx want got)

-- | Check an expression used as a borrowed operand of a gate or measurement.
-- Returns its type without consuming it.
operand :: Env -> Expr -> TC Type
operand env e = case e of
  Var x -> do
    b <- lookupVar env x
    when (isLinear (bindType b)) $ checkUsableWhole x
    return (bindType b)
  Index (Var r) i -> do
    b <- lookupVar env r
    expect "register index" TQuantumReg (bindType b)
    it <- infer env i
    expect "register index" TInt it
    case i of
      IntLit k -> checkUsableElem r k
      _ -> checkUsableWhole r
    return TQubit
  _ -> infer env e

-- | A measurement target is consumed after the measurement.
consumeTarget :: Env -> Expr -> TC Type
consumeTarget env e = case e of
  Var _ -> infer env e                       -- moves the whole resource
  Index (Var r) (IntLit k) -> do
    t <- operand env e
    consume (Elem r k)
    return t
  Index _ _ -> operand env e
  _ -> infer env e

sameOperand :: Expr -> Expr -> Bool
sameOperand (Var a) (Var b) = a == b
sameOperand (Index (Var a) (IntLit i)) (Index (Var b) (IntLit j)) = a == b && i == j
sameOperand _ _ = False

isQuantumValue :: Type -> Bool
isQuantumValue t = t == TQubit || t == TQuantumReg

infer :: Env -> Expr -> TC Type
infer env expr = case expr of
  IntLit _ -> return TInt
  BoolLit _ -> return TBool
  UnitLit -> return TUnit

  Var x -> do
    b <- lookupVar env x
    when (isLinear (bindType b)) $ do
      checkUsableWhole x
      consume (Whole x)
    return (bindType b)

  NewQubit -> requireQuantum env "new Qubit()" >> return TQubit
  NewQReg n -> do
    requireQuantum env "new QuantumRegister(...)"
    t <- infer env n
    expect "register size" TInt t
    return TQuantumReg

  Gate _ e -> do
    requireQuantum env "gate"
    t <- operand env e
    unless (isQuantumValue t) $ throw (ExpectedQuantum "gate operand" t)
    return TUnit

  Controlled _ c t -> twoQubits "controlled" c t
  Entangle c t -> twoQubits "entangle" c t

  Measure e -> do
    requireQuantum env "measure"
    t <- consumeTarget env e
    case t of
      TQubit -> return TResult
      TQuantumReg -> return TResults
      _ -> throw (NotAResource t)

  ProbabilityOf e -> do
    requireQuantum env "probability"
    t <- consumeTarget env e
    unless (isQuantumValue t) $ throw (NotAResource t)
    return TProbability

  BinOp op a b -> do
    ta <- infer env a
    tb <- infer env b
    binOp op ta tb

  Not e -> infer env e >>= \t -> expect "'!'" TBool t >> return TBool
  Neg e -> infer env e >>= \t -> expect "unary '-'" TInt t >> return TInt

  If c t e -> do
    tc <- infer env c
    expect "if condition" TBool tc
    start <- get
    tt <- infer env t
    afterThen <- get
    put start
    te <- infer env e
    afterElse <- get
    put (Set.union afterThen afterElse)
    unless (tt == te) $ throw (TypeMismatch "else branch" tt te)
    return tt

  For v lo hi body -> do
    tlo <- infer env lo
    thi <- infer env hi
    expect "loop start" TInt tlo
    expect "loop end" TInt thi
    loopBody (env { envVars = Map.insert v (Binding TInt False) (envVars env) }) body
    return TUnit

  While c body -> do
    tc <- infer env c
    expect "while condition" TBool tc
    loopBody env body
    return TUnit

  Decl scope name ann val body -> do
    tv <- infer env val
    forM_ ann $ \a -> expect ("declaration of '" ++ name ++ "'") a tv
    when (scope /= ScopeLocal && isLinear tv) $ throw (InvalidScope scope name tv)
    let env' = env { envVars = Map.insert name (Binding tv (scope == ScopeVar)) (envVars env) }
    withScope name (infer env' body)

  Assign x e -> do
    b <- lookupVar env x
    unless (bindMutable b) $ throw (AssignImmutable x)
    t <- infer env e
    expect ("assignment to '" ++ x ++ "'") (bindType b) t
    return TUnit

  Call f args -> do
    FnSig kind params ret <- maybe (throw (UndefinedFunction f)) return (Map.lookup f (envFns env))
    when (kind == QuantumFn) $ requireQuantum env ("call to quantum fn '" ++ f ++ "'")
    when (length params /= length args) $ throw (ArityMismatch f (length params) (length args))
    ts <- mapM (infer env) args
    zipWithM_ (expect ("argument of '" ++ f ++ "'")) params ts
    return ret

  Return e -> infer env e

  Index _ _ -> throw (QubitAliasing
    "a qubit cannot be moved out of a register; use r[i] directly as an operand of a gate or measure(...)")

  Tuple es -> TTuple <$> mapM (infer env) es

  TupleIndex e i -> do
    t <- infer env e
    case t of
      TTuple ts | i >= 0 && i < length ts -> return (ts !! i)
      _ -> throw (TypeMismatch "tuple index" (TTuple []) t)

  Seq [] -> return TUnit
  Seq es -> last <$> mapM (infer env) es

  where
    twoQubits what c t = do
      requireQuantum env what
      tc <- operand env c
      tt <- operand env t
      expect (what ++ " control") TQubit tc
      expect (what ++ " target") TQubit tt
      when (sameOperand c t) $ throw (SameOperand what)
      return TUnit

-- | A loop body may not consume resources declared outside of it.
loopBody :: Env -> Expr -> TC ()
loopBody env body = do
  before <- get
  _ <- infer env body
  after <- get
  case Set.toList (Set.difference after before) of
    [] -> return ()
    (k : _) -> throw (ConsumedInLoop (keyName k))

binOp :: BinOp -> Type -> Type -> TC Type
binOp op ta tb
  | op `elem` [Add, Sub, Mul, Div, Mod] = both TInt >> return TInt
  | op `elem` [Lt, Le, Gt, Ge] = both TInt >> return TBool
  | op `elem` [And, Or] = both TBool >> return TBool
  | otherwise = do
      expect "comparison" ta tb
      when (isLinear ta) $ throw (TypeMismatch "comparison of quantum resources" TInt ta)
      return TBool
  where
    both t = expect "operator" t ta >> expect "operator" t tb
