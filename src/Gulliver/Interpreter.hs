-- | Interpreter and tracing front end for Gulliver.
--
-- Gulliver programs run against a three-part memory model:
--
--   1. /Quantum state/ ('mQuantum'): the amplitudes of every allocated qubit,
--      including phase. Only coherent operations (gates) act on it.
--   2. /Measurement distributions/ ('VProb'): the exact outcome probabilities
--      derived from the amplitudes by the Born rule. They are derived data;
--      probabilities alone cannot represent phase or interference.
--   3. /Classical memory/ ('mEnv'): ordinary values (Int, Bool, Result, ...)
--      and the handles ('VQubit', 'VReg') that name quantum resources.
--
-- A 'QuantumRegister' is an ordered collection of handles into the single
-- global quantum system, not a separate system: qubits of different
-- registers can be entangled with each other.
--
-- While executing, the interpreter records every quantum instruction in a
-- hardware-independent IR ('rrIR'), which is what the backends consume.
module Gulliver.Interpreter
  ( Value(..)
  , RunResult(..)
  , runProgram
  , runShots
  , resolveEntry
  , renderValue
  , renderDistribution
  ) where

import Control.Monad (forM, unless, when, replicateM)
import Control.Monad.State
import qualified Data.Map as Map
import qualified Data.Set as Set
import Numeric (showFFloat)

import Gulliver.AST
import Gulliver.IR
import Gulliver.Simulator

data Value
  = VInt Int
  | VBool Bool
  | VResult Bool
  | VResults [Bool]
  | VQubit Int
  | VReg [Int]
  | VProb Distribution
  | VTuple [Value]
  | VUnit
  deriving (Show, Eq)

data Machine = Machine
  { mEnv :: Map.Map String Value
  , mDefs :: Map.Map String Definition
  , mQuantum :: QState
  , mNextQubit :: Int
  , mNextBit :: Int
  , mConsumed :: Set.Set Int         -- qubits already measured
  , mRng :: Rng
  , mTrace :: [IRInstr]              -- reversed
  , mWarnings :: [String]            -- reversed
  , mDepth :: Int
  }

type Eval = StateT Machine (Either String)

data RunResult = RunResult
  { rrValue :: Value
  , rrState :: QState
  , rrNumQubits :: Int
  , rrIR :: IRProgram
  , rrWarnings :: [String]
  }

maxQubits, maxLoopIterations, maxCallDepth :: Int
maxQubits = 60
maxLoopIterations = 1000000
maxCallDepth = 10000

failEval :: String -> Eval a
failEval = lift . Left

-- | The expression a program runs: its top-level expression, else 'main',
-- else the last function that takes no arguments.
resolveEntry :: Program -> Either String Expr
resolveEntry prog = case programMain prog of
  Just e -> Right e
  Nothing ->
    let nullary = [d | d <- programDefs prog, null (defParams d)]
        pick = case [d | d <- nullary, defName d == "main"] of
          (d : _) -> Just d
          [] -> if null nullary then Nothing else Just (last nullary)
    in case pick of
         Just d -> Right (Call (defName d) [])
         Nothing -> Left "nothing to run: define a top-level expression or a function without parameters"

-- | Execute a program once with the given random seed.
runProgram :: Int -> Program -> Either String RunResult
runProgram seed prog = do
  entry <- resolveEntry prog
  let m0 = Machine
        { mEnv = Map.empty
        , mDefs = Map.fromList [(defName d, d) | d <- programDefs prog]
        , mQuantum = initialState
        , mNextQubit = 0
        , mNextBit = 0
        , mConsumed = Set.empty
        , mRng = mkRng seed
        , mTrace = []
        , mWarnings = []
        , mDepth = 0
        }
  (v, m) <- runStateT (eval entry) m0
  return RunResult
    { rrValue = v
    , rrState = mQuantum m
    , rrNumQubits = mNextQubit m
    , rrIR = mkIRProgram (mNextQubit m) (mNextBit m) (reverse (mTrace m))
    , rrWarnings = reverse (mWarnings m)
    }

-- | Run a program many times (shots) and histogram the rendered results.
-- A 'Probability' result is sampled from its exact distribution each shot.
runShots :: Int -> Int -> Program -> Either String [(String, Int)]
runShots n seed prog = do
  labels <- forM [0 .. n - 1] $ \i -> do
    r <- runProgram (seed + i) prog
    return $ case rrValue r of
      VProb d -> sampleDistribution (fst (nextDouble (mkRng (seed + i + 7919)))) d
      v -> renderValue v
  return (Map.toList (Map.fromListWith (+) [(l, 1 :: Int) | l <- labels]))

------------------------------------------------------------------------------
-- Machine helpers

emit :: IRInstr -> Eval ()
emit i = modify $ \m -> m { mTrace = i : mTrace m }

warn :: String -> Eval ()
warn w = modify $ \m -> m { mWarnings = w : mWarnings m }

allocQubit :: Eval Int
allocQubit = do
  k <- gets mNextQubit
  when (k >= maxQubits) $ failEval ("cannot allocate more than " ++ show maxQubits ++ " qubits")
  modify $ \m -> m { mNextQubit = k + 1 }
  return k

allocBit :: Eval Int
allocBit = do
  b <- gets mNextBit
  modify $ \m -> m { mNextBit = b + 1 }
  return b

nextRand :: Eval Double
nextRand = do
  g <- gets mRng
  let (r, g') = nextDouble g
  modify $ \m -> m { mRng = g' }
  return r

qubitsOf :: Value -> Eval [Int]
qubitsOf v = case v of
  VQubit k -> return [k]
  VReg ks -> return ks
  _ -> failEval "internal error: expected a quantum resource"

ensureLive :: [Int] -> Eval ()
ensureLive qs = do
  used <- gets mConsumed
  case filter (`Set.member` used) qs of
    [] -> return ()
    (k : _) -> failEval ("qubit " ++ show k ++ " was already measured and cannot be used again")

modifyQuantum :: (QState -> QState) -> Eval ()
modifyQuantum f = modify $ \m -> m { mQuantum = f (mQuantum m) }

evalInt :: Expr -> Eval Int
evalInt e = eval e >>= \v -> case v of
  VInt n -> return n
  _ -> failEval "internal error: expected an Int"

evalBool :: Expr -> Eval Bool
evalBool e = eval e >>= \v -> case v of
  VBool b -> return b
  _ -> failEval "internal error: expected a Bool"

bindVar :: String -> Value -> Eval ()
bindVar x v = modify $ \m -> m { mEnv = Map.insert x v (mEnv m) }

-- | Run an action with a name bound, then restore the previous binding.
scoped :: String -> Value -> Eval a -> Eval a
scoped x v body = do
  old <- gets (Map.lookup x . mEnv)
  bindVar x v
  r <- body
  modify $ \m -> m { mEnv = maybe (Map.delete x) (Map.insert x) old (mEnv m) }
  return r

applyOne :: Gate1 -> Int -> Eval ()
applyOne g k = do
  modifyQuantum (applyGate g k)
  emit (IGate g k)

applyCtrl :: Gate1 -> Int -> Int -> Eval ()
applyCtrl g c t = do
  modifyQuantum (applyControlled g c t)
  emit (IControlled g c t)

twoDistinct :: String -> Value -> Value -> Eval (Int, Int)
twoDistinct what cv tv = do
  cs <- qubitsOf cv
  ts <- qubitsOf tv
  case (cs, ts) of
    ([c], [t]) -> do
      ensureLive [c, t]
      when (c == t) $ failEval (what ++ " needs two distinct qubits")
      return (c, t)
    _ -> failEval ("internal error: " ++ what ++ " expects two qubits")

measureOne :: Int -> Eval Bool
measureOne k = do
  r <- nextRand
  st <- gets mQuantum
  let (outcome, st') = measureQubit r k st
  modify $ \m -> m { mQuantum = st', mConsumed = Set.insert k (mConsumed m) }
  bit <- allocBit
  emit (IMeasure k bit)
  return outcome

------------------------------------------------------------------------------
-- Evaluation

eval :: Expr -> Eval Value
eval expr = case expr of
  IntLit n -> return (VInt n)
  BoolLit b -> return (VBool b)
  UnitLit -> return VUnit

  Var x -> gets (Map.lookup x . mEnv) >>= maybe (failEval ("undefined variable '" ++ x ++ "'")) return

  NewQubit -> VQubit <$> allocQubit
  NewQReg ne -> do
    n <- evalInt ne
    when (n < 0) $ failEval "register size must not be negative"
    VReg <$> replicateM n allocQubit

  Gate g t -> do
    qs <- eval t >>= qubitsOf
    ensureLive qs
    mapM_ (applyOne g) qs
    return VUnit

  Controlled g c t -> do
    cv <- eval c
    tv <- eval t
    (cq, tq) <- twoDistinct "controlled" cv tv
    applyCtrl g cq tq
    return VUnit

  Entangle c t -> do
    cv <- eval c
    tv <- eval t
    (cq, tq) <- twoDistinct "entangle" cv tv
    applyCtrl PauliX cq tq
    st <- gets mQuantum
    when (purity cq st > 1 - 1e-9 && purity tq st > 1 - 1e-9) $
      warn $ "entangle(qubit " ++ show cq ++ ", qubit " ++ show tq
        ++ "): no evidence of entanglement between the operands (both qubits are"
        ++ " still in pure states); CNOT only entangles when the control is in"
        ++ " superposition and the target is changed by X"
    return VUnit

  Measure t -> do
    v <- eval t
    qs <- qubitsOf v
    ensureLive qs
    bits <- mapM measureOne qs
    return $ case v of
      VQubit _ -> VResult (head bits)
      _ -> VResults bits

  ProbabilityOf t -> do
    qs <- eval t >>= qubitsOf
    ensureLive qs
    st <- gets mQuantum
    let dist = distribution qs st
    bits <- replicateM (length qs) allocBit
    emit (IProbe qs bits)
    modify $ \m -> m { mConsumed = foldr Set.insert (mConsumed m) qs }
    return (VProb dist)

  BinOp And a b -> do
    x <- evalBool a
    if x then VBool <$> evalBool b else return (VBool False)
  BinOp Or a b -> do
    x <- evalBool a
    if x then return (VBool True) else VBool <$> evalBool b
  BinOp op a b -> do
    va <- eval a
    vb <- eval b
    binOp op va vb

  Not e -> VBool . not <$> evalBool e
  Neg e -> VInt . negate <$> evalInt e

  If c t e -> do
    b <- evalBool c
    eval (if b then t else e)

  For v lo hi body -> do
    l <- evalInt lo
    h <- evalInt hi
    when (h - l + 1 > maxLoopIterations) $ failEval "loop iteration limit exceeded"
    mapM_ (\i -> scoped v (VInt i) (eval body)) [l .. h]
    return VUnit

  While c body -> loop (0 :: Int)
    where
      loop n = do
        b <- evalBool c
        if not b then return VUnit else do
          when (n >= maxLoopIterations) $ failEval "loop iteration limit exceeded"
          _ <- eval body
          loop (n + 1)

  Decl _ name _ val body -> do
    v <- eval val
    scoped name v (eval body)

  Assign x e -> do
    v <- eval e
    bound <- gets (Map.member x . mEnv)
    unless bound $ failEval ("undefined variable '" ++ x ++ "'")
    bindVar x v
    return VUnit

  Call f args -> do
    vals <- mapM eval args
    defs <- gets mDefs
    d <- maybe (failEval ("undefined function '" ++ f ++ "'")) return (Map.lookup f defs)
    depth <- gets mDepth
    when (depth >= maxCallDepth) $ failEval "call depth limit exceeded"
    saved <- gets mEnv
    modify $ \m -> m
      { mEnv = Map.fromList (zip (map paramName (defParams d)) vals)
      , mDepth = depth + 1
      }
    r <- eval (defBody d)
    modify $ \m -> m { mEnv = saved, mDepth = depth }
    return r

  Return e -> eval e

  Index e i -> do
    v <- eval e
    n <- evalInt i
    case v of
      VReg ks
        | n >= 0 && n < length ks -> return (VQubit (ks !! n))
        | otherwise -> failEval ("register index " ++ show n ++ " out of bounds (size " ++ show (length ks) ++ ")")
      _ -> failEval "internal error: indexing a non-register"

  Tuple es -> VTuple <$> mapM eval es

  TupleIndex e i -> do
    v <- eval e
    case v of
      VTuple vs | i >= 0 && i < length vs -> return (vs !! i)
      _ -> failEval "tuple index out of bounds"

  Seq es -> do
    vs <- mapM eval es
    return (if null vs then VUnit else last vs)

binOp :: BinOp -> Value -> Value -> Eval Value
binOp op va vb = case (op, va, vb) of
  (Add, VInt x, VInt y) -> ok (VInt (x + y))
  (Sub, VInt x, VInt y) -> ok (VInt (x - y))
  (Mul, VInt x, VInt y) -> ok (VInt (x * y))
  (Div, VInt x, VInt y) -> if y == 0 then failEval "division by zero" else ok (VInt (x `div` y))
  (Mod, VInt x, VInt y) -> if y == 0 then failEval "division by zero" else ok (VInt (x `mod` y))
  (Lt, VInt x, VInt y) -> ok (VBool (x < y))
  (Le, VInt x, VInt y) -> ok (VBool (x <= y))
  (Gt, VInt x, VInt y) -> ok (VBool (x > y))
  (Ge, VInt x, VInt y) -> ok (VBool (x >= y))
  (Eq, _, _) -> ok (VBool (va == vb))
  (Neq, _, _) -> ok (VBool (va /= vb))
  _ -> failEval "internal error: ill-typed operands"
  where ok = return

------------------------------------------------------------------------------
-- Rendering

renderValue :: Value -> String
renderValue v = case v of
  VInt n -> show n
  VBool b -> if b then "true" else "false"
  VResult b -> bitChar b : []
  VResults bs -> map bitChar bs
  VQubit k -> "Qubit(" ++ show k ++ ")"
  VReg ks -> "QuantumRegister(" ++ show (length ks) ++ " qubits)"
  VProb d -> renderDistribution d
  VTuple vs -> "(" ++ commaSep (map renderValue vs) ++ ")"
  VUnit -> "()"
  where
    bitChar b = if b then '1' else '0'
    commaSep [] = ""
    commaSep [x] = x
    commaSep (x : xs) = x ++ ", " ++ commaSep xs

renderDistribution :: Distribution -> String
renderDistribution d =
  "{" ++ go d ++ "}"
  where
    go [] = ""
    go [x] = entry x
    go (x : xs) = entry x ++ ", " ++ go xs
    entry (s, p) = s ++ ": " ++ showFFloat (Just 2) (100 * p) "" ++ "%"
