module Gulliver.AST where

-- | A program: function definitions plus an optional top-level expression.
data Program = Program
  { programDefs :: [Definition]
  , programMain :: Maybe Expr
  } deriving (Show, Eq)

data FnKind = QuantumFn | ClassicalFn
  deriving (Show, Eq)

data Definition = Definition
  { defKind :: FnKind
  , defName :: String
  , defParams :: [Parameter]
  , defRet :: Type
  , defBody :: Expr
  } deriving (Show, Eq)

data Parameter = Parameter
  { paramName :: String
  , paramType :: Type
  } deriving (Show, Eq)

-- | Binding forms. All of them are lexically scoped ("... in body").
--
--   * 'ScopeVar'   : mutable classical binding (can be reassigned with ':=')
--   * 'ScopeLocal' : immutable binding; the default
--   * 'ScopeFinal' : immutable classical constant
--
-- Quantum resources can only be bound with 'ScopeLocal': reassigning or
-- freezing a qubit says nothing about its safety, which is governed by the
-- affine resource checker instead.
data Scope = ScopeVar | ScopeLocal | ScopeFinal
  deriving (Show, Eq, Ord)

-- | The Gulliver type universe.
--
--   * 'TQubit', 'TQuantumReg' : quantum resources (affine: moved at most once,
--     borrowed by gates)
--   * 'TResult'              : classical bit obtained by measuring a qubit
--   * 'TResults'             : classical bit string obtained by measuring a register
--   * 'TProbability'         : exact distribution of the outcomes of a measurement
data Type
  = TQubit
  | TQuantumReg
  | TResult
  | TResults
  | TProbability
  | TInt
  | TBool
  | TUnit
  | TTuple [Type]
  deriving (Show, Eq, Ord)

-- | Quantum resources cannot be copied (no-cloning).
isLinear :: Type -> Bool
isLinear TQubit = True
isLinear TQuantumReg = True
isLinear (TTuple ts) = any isLinear ts
isLinear _ = False

prettyType :: Type -> String
prettyType t = case t of
  TQubit -> "Qubit"
  TQuantumReg -> "QuantumRegister"
  TResult -> "Result"
  TResults -> "Results"
  TProbability -> "Probability"
  TInt -> "Int"
  TBool -> "Bool"
  TUnit -> "Unit"
  TTuple ts -> "(" ++ commaSep (map prettyType ts) ++ ")"
  where
    commaSep [] = ""
    commaSep [x] = x
    commaSep (x:xs) = x ++ ", " ++ commaSep xs

-- | Single-qubit gates, named after what they do to the state.
data Gate1 = Hadamard | PauliX | PauliY | PauliZ
  deriving (Show, Eq, Ord, Enum, Bounded)

data BinOp
  = Add | Sub | Mul | Div | Mod
  | Eq | Neq | Lt | Le | Gt | Ge
  | And | Or
  deriving (Show, Eq)

data Expr
  = IntLit Int
  | BoolLit Bool
  | UnitLit
  | Var String

  -- Quantum resources
  | NewQubit                          -- new Qubit()
  | NewQReg Expr                      -- new QuantumRegister(n)

  -- Quantum operations
  | Gate Gate1 Expr                   -- superposite / bitflip / phaseflip (and H, X, Y, Z)
  | Controlled Gate1 Expr Expr        -- controlled(gate, control, target)
  | Entangle Expr Expr                -- entangle(control, target): CNOT with entanglement intent
  | Measure Expr                      -- measure(qubit | register)
  | ProbabilityOf Expr                -- probability(measure(qubit | register))

  -- Classical operations
  | BinOp BinOp Expr Expr
  | Not Expr
  | Neg Expr

  -- Control flow
  | If Expr Expr Expr
  | For String Expr Expr Expr         -- for i in lo..hi { body }   (hi inclusive)
  | While Expr Expr

  -- Bindings and calls
  | Decl Scope String (Maybe Type) Expr Expr
  | Assign String Expr
  | Call String [Expr]
  | Return Expr

  -- Structured values
  | Index Expr Expr
  | Tuple [Expr]
  | TupleIndex Expr Int
  | Seq [Expr]
  deriving (Show, Eq)
