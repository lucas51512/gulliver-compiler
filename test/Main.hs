module Main (main) where

import Control.Monad (forM, unless)
import Data.List (isInfixOf)
import qualified Data.Map as Map
import System.Exit (exitFailure)

import Data.Complex (Complex(..))

import Gulliver.AST
import Gulliver.Backend
import Gulliver.Interpreter
import Gulliver.IR
import Gulliver.Lexer
import Gulliver.Parser
import Gulliver.Simulator
import Gulliver.TypeChecker

------------------------------------------------------------------------------
-- Tiny test harness (no external dependencies)

type Test = (String, Bool)

check :: String -> Bool -> Test
check = (,)

------------------------------------------------------------------------------
-- Helpers

parseOk :: String -> Program
parseOk src = either (error . ("parse: " ++)) id (parseProgram src)

typeErr :: String -> Maybe TypeError
typeErr src = case parseProgram src of
  Left e -> error ("parse: " ++ e)
  Right p -> either Just (const Nothing) (checkProgram p)

typechecks :: String -> Bool
typechecks src = typeErr src == Nothing

runSeed :: Int -> String -> RunResult
runSeed seed src = either (error . ("run: " ++)) id (runProgram seed (parseOk src))

value :: String -> Value
value = rrValue . runSeed 1

wrap :: String -> String
wrap body = "quantum fn f() -> Result {\n" ++ body ++ "\n}\nf()"

near :: Double -> Double -> Bool
near a b = abs (a - b) < 1e-6

probOf :: String -> Value -> Double
probOf k (VProb d) = maybe 0 id (lookup k d)
probOf _ _ = -1

------------------------------------------------------------------------------

tests :: [Test]
tests =
  -- Lexer
  [ check "lexer skips line and block comments" $
      fmap (map locTok) (tokenize "a // x\n/* y\n z */ b")
        == Right [TkIdent "a", TkIdent "b", TkEOF]
  , check "lexer reports unterminated block comment" $
      either ("unterminated" `isInfixOf`) (const False) (tokenize "/* oops")

  -- Parser
  , check "precedence: * binds tighter than +" $
      parseExpr "1 + 2 * 3" == Right (BinOp Add (IntLit 1) (BinOp Mul (IntLit 2) (IntLit 3)))
  , check "declaration body extends over the rest of the block" $
      case parseExpr "local q: Qubit = new Qubit() in superposite(q); measure(q)" of
        Right (Decl ScopeLocal "q" (Just TQubit) NewQubit (Seq [Gate Hadamard (Var "q"), Measure (Var "q")])) -> True
        _ -> False
  , check "trailing return keeps its type; other trailing ';' gives Unit" $
      parseExpr "return 1;" == Right (Return (IntLit 1))
        && parseExpr "superposite(q);" == Right (Seq [Gate Hadamard (Var "q"), UnitLit])
  , check "probability requires measure(...)" $
      either (const True) (const False) (parseExpr "probability(q)")
  , check "legacy H and CNOT parse to the gate AST" $
      parseExpr "CNOT(a, b)" == Right (Controlled PauliX (Var "a") (Var "b"))
        && parseExpr "H(a)" == Right (Gate Hadamard (Var "a"))
  , check "parse errors carry a position" $
      either ("1:" `isInfixOf`) (const False) (parseExpr "1 + ")

  -- Types: three distinct concepts
  , check "measure(qubit) is a Result, measure(register) is Results" $
      typechecks (wrap "local q: Qubit = new Qubit() in measure(q)")
        && typeErr "quantum fn f() -> Results { local q: Qubit = new Qubit() in measure(q) }" /= Nothing
        && typechecks "quantum fn f() -> Results { local r: QuantumRegister = new QuantumRegister(2) in measure(r) }"
  , check "probability(measure(q)) is a Probability" $
      typechecks "quantum fn f() -> Probability { local q: Qubit = new Qubit() in superposite(q); probability(measure(q)) }"
  , check "function body must match the declared return type" $
      case typeErr "quantum fn f() -> Probability { local q: Qubit = new Qubit() in measure(q) }" of
        Just (TypeMismatch _ TProbability TResult) -> True
        _ -> False

  -- Types: no-cloning / affine resources
  , check "use after measure is rejected" $
      case typeErr (wrap "local q: Qubit = new Qubit() in measure(q); measure(q)") of
        Just (UseAfterConsume "q") -> True
        _ -> False
  , check "gate after measure is rejected" $
      case typeErr (wrap "local q: Qubit = new Qubit() in local r: Result = measure(q) in superposite(q); r") of
        Just (UseAfterConsume "q") -> True
        _ -> False
  , check "copying a qubit into a second name is rejected" $
      case typeErr (wrap "local a: Qubit = new Qubit() in local b: Qubit = a in measure(a)") of
        Just (UseAfterConsume "a") -> True
        _ -> False
  , check "moving a qubit out of a register is rejected" $
      case typeErr (wrap "local r: QuantumRegister = new QuantumRegister(2) in local a: Qubit = r[0] in measure(a)") of
        Just (QubitAliasing _) -> True
        _ -> False
  , check "entangle with the same qubit twice is rejected" $
      case typeErr (wrap "local q: Qubit = new Qubit() in entangle(q, q); measure(q)") of
        Just (SameOperand _) -> True
        _ -> False
  , check "measured register element cannot be reused (literal index)" $
      case typeErr (wrap "local r: QuantumRegister = new QuantumRegister(2) in measure(r[0]); superposite(r[0]); measure(r[1])") of
        Just (UseAfterConsume _) -> True
        _ -> False
  , check "measuring different register elements is fine" $
      typechecks "quantum fn f() -> (Result, Result) { local r: QuantumRegister = new QuantumRegister(2) in local a: Result = measure(r[0]) in local b: Result = measure(r[1]) in (a, b) }"
  , check "consuming an outer qubit inside a loop is rejected" $
      case typeErr (wrap "local q: Qubit = new Qubit() in for i in 0..2 { measure(q); } local r: Result = measure(q) in r") of
        Just (ConsumedInLoop "q") -> True
        _ -> False
  , check "a branch that measures marks the qubit consumed afterwards" $
      case typeErr (wrap "local q: Qubit = new Qubit() in local c: Bool = true in if c then measure(q) else measure(q); measure(q)") of
        Just (UseAfterConsume "q") -> True
        _ -> False
  , check "final and var cannot hold qubits" $
      case typeErr (wrap "final q: Qubit = new Qubit() in measure(q)") of
        Just (InvalidScope ScopeFinal "q" TQubit) -> True
        _ -> False
  , check "var is reassignable, local and final are not" $
      typechecks "fn f() -> Int { var x: Int = 1 in x := 2; x }"
        && (case typeErr "fn f() -> Int { local x: Int = 1 in x := 2; x }" of
              Just (AssignImmutable "x") -> True
              _ -> False)
  , check "classical fn cannot use quantum operations" $
      case typeErr "fn f() -> Result { local q: Qubit = new Qubit() in measure(q) }" of
        Just (QuantumInClassical _) -> True
        _ -> False

  -- Simulator: amplitudes, phase and interference
  , check "H then H returns to |0> (interference)" $
      value (wrap "local q: Qubit = new Qubit() in superposite(q); superposite(q); measure(q)") == VResult False
  , check "H Z H acts like X: phase changes the outcome" $
      all (\s -> rrValue (runSeed s (wrap "local q: Qubit = new Qubit() in superposite(q); phaseflip(q); superposite(q); measure(q)")) == VResult True) [1 .. 20]
  , check "keeps complex phase: Y on |0> gives amplitude i on |1>" $
      Map.toList (qsAmps (applyGate PauliY 0 initialState)) == [(1, 0 :+ 1)]
  , check "measurement collapses and agrees across entangled qubits" $
      and [ case value' s of
              VTuple [VResult a, VResult b] -> a == b
              _ -> False
          | s <- [1 .. 40] ]
  , check "both outcomes occur over many seeds" $
      let outs = [value' s | s <- [1 .. 40]]
      in VTuple [VResult True, VResult True] `elem` outs
           && VTuple [VResult False, VResult False] `elem` outs

  -- Probability
  , check "probability of a coin flip is 50/50 and not collapsed" $
      let v = value "quantum fn f() -> Probability { local q: Qubit = new Qubit() in superposite(q); probability(measure(q)) }\nf()"
      in near (probOf "0" v) 0.5 && near (probOf "1" v) 0.5
  , check "probability reads the Born rule from amplitudes (3 qubits GHZ)" $
      let v = value "quantum fn f() -> Probability { local r: QuantumRegister = new QuantumRegister(3) in superposite(r[0]); entangle(r[0], r[1]); entangle(r[1], r[2]); probability(measure(r)) }\nf()"
      in near (probOf "000" v) 0.5 && near (probOf "111" v) 0.5 && probOf "010" v == 0
  , check "shots sample a Probability result" $
      case runShots 200 3 (parseOk "quantum fn f() -> Probability { local q: Qubit = new Qubit() in superposite(q); probability(measure(q)) }\nf()") of
        Right hist -> length hist == 2 && sum (map snd hist) == 200
        Left _ -> False

  -- statistical checks over many shots
  , check "Bell shots: only 00/11, roughly balanced" $
      case shotsOf 400 7 "quantum fn f() -> Results { local r: QuantumRegister = new QuantumRegister(2) in superposite(r[0]); entangle(r[0], r[1]); measure(r) }\nf()" of
        Just h -> all ((`elem` ["00", "11"]) . fst) h && all (\(_, n) -> n > 140 && n < 260) h
        Nothing -> False
  , check "interference shots: H Z H is always 1, H H always 0" $
      shotsOf 50 1 (wrap "local q: Qubit = new Qubit() in superposite(q); phaseflip(q); superposite(q); measure(q)") == Just [("1", 50)]
        && shotsOf 50 1 (wrap "local q: Qubit = new Qubit() in superposite(q); superposite(q); measure(q)") == Just [("0", 50)]
  , check "probability does not collapse: IR holds IProbe, no IMeasure" $
      let is = irInstrs (rrIR (runSeed 1 "quantum fn f() -> Probability { local q: Qubit = new Qubit() in superposite(q); probability(measure(q)) }\nf()"))
      in any isProbe is && not (any isMeasure is)

  -- entangle semantics
  , check "entangle on a |0> control warns that nothing was entangled" $
      not . null . rrWarnings $ runSeed 1 "quantum fn f() -> Results { local r: QuantumRegister = new QuantumRegister(2) in entangle(r[0], r[1]); measure(r) }\nf()"
  , check "entangle on a superposed control does not warn" $
      null . rrWarnings $ runSeed 1 bell
  , check "controlled(...) never warns and matches CNOT" $
      null . rrWarnings $ runSeed 1 "quantum fn f() -> Results { local r: QuantumRegister = new QuantumRegister(2) in controlled(bitflip, r[0], r[1]); measure(r) }\nf()"

  -- Runtime
  , check "measured qubits are rejected at run time when the index is computed" $
      either ("already measured" `isInfixOf`) (const False)
        (runProgram 1 (parseOk "quantum fn f() -> Results { local r: QuantumRegister = new QuantumRegister(2) in for i in 0..1 { measure(r[0]); } measure(r) }\nf()"))
  , check "functions receive their arguments" $
      value "fn add(a: Int, b: Int) -> Int { a + b }\nadd(2, 3) * 2" == VInt 10
  , check "for range is inclusive and var assignments persist" $
      value "fn f() -> Int { var s: Int = 0 in for i in 1..4 { s := s + i; } s }\nf()" == VInt 10
  , check "while loop" $
      value "fn f() -> Int { var n: Int = 0 in while n < 5 { n := n + 1; } n }\nf()" == VInt 5
  , check "register index out of bounds is an error" $
      either (const True) (const False)
        (runProgram 1 (parseOk "quantum fn f() -> Result { local r: QuantumRegister = new QuantumRegister(1) in measure(r[3]) }\nf()"))

  -- IR and backends
  , check "IR records the executed quantum instructions" $
      irInstrs (rrIR (runSeed 1 bell))
        == [IGate Hadamard 0, IControlled PauliX 0 1, IMeasure 0 0, IMeasure 1 1]
  , check "re-simulating the IR reproduces the run (same seed)" $
      let r = runSeed 5 bell
          sim = runIR 5 (rrIR r)
      in srState sim == rrState r
  , check "OpenQASM output" $
      let q = generateOpenQASM (rrIR (runSeed 1 bell))
      in all (`isInfixOf` q) ["OPENQASM 3.0;", "qubit[2] q;", "h q[0];", "cx q[0], q[1];", "c[0] = measure q[0];"]
  , check "Qiskit output" $
      let q = generateQiskit (rrIR (runSeed 1 bell))
      in all (`isInfixOf` q) ["circuit.h(0)", "circuit.cx(0, 1)", "circuit.measure(1, 1)"]
  ]
  where
    value' s = rrValue (runSeed s bell)

shotsOf :: Int -> Int -> String -> Maybe [(String, Int)]
shotsOf n seed src = either (const Nothing) Just (runShots n seed (parseOk src))

isProbe, isMeasure :: IRInstr -> Bool
isProbe i = case i of { IProbe _ _ -> True; _ -> False }
isMeasure i = case i of { IMeasure _ _ -> True; _ -> False }

bell :: String
bell = "quantum fn f() -> (Result, Result) { local q: QuantumRegister = new QuantumRegister(2) in superposite(q[0]); entangle(q[0], q[1]); local a: Result = measure(q[0]) in local b: Result = measure(q[1]) in (a, b) }\nf()"

------------------------------------------------------------------------------
-- Every shipped example must parse, type check and run.

exampleFiles :: [FilePath]
exampleFiles =
  [ "bell_state", "ghz_state", "superposition", "coin_flip"
  , "interference", "deutsch", "variable_scopes", "entangle_intent" ]

exampleTests :: IO [Test]
exampleTests = forM exampleFiles $ \name -> do
  src <- readFile ("examples/" ++ name ++ ".gll")
  let ok = case parseProgram src of
        Left _ -> False
        Right p -> checkProgram p == Right () && either (const False) (const True) (runProgram 1 p)
  return (check ("example " ++ name ++ ".gll runs") ok)

main :: IO ()
main = do
  ex <- exampleTests
  let all' = tests ++ ex
      failed = [name | (name, ok) <- all', not ok]
  mapM_ (\(name, ok) -> putStrLn ((if ok then "PASS  " else "FAIL  ") ++ name)) all'
  putStrLn (show (length all' - length failed) ++ "/" ++ show (length all') ++ " passed")
  unless (null failed) exitFailure
