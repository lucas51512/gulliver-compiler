-- | Code generators. Every backend consumes the hardware-independent IR,
-- never the AST, so adding a target does not touch the language front end.
module Gulliver.Backend
  ( BackendType(..)
  , generateBackend
  , generateOpenQASM
  , generateQiskit
  , generateIRDump
  , visualizeCircuit
  , exportCircuit
  ) where

import Data.List (intercalate)

import Gulliver.AST (Gate1(..))
import Gulliver.IR

data BackendType = QASM | Qiskit | IRDump | Visualization
  deriving (Show, Eq)

generateBackend :: BackendType -> IRProgram -> String
generateBackend b = case b of
  QASM -> generateOpenQASM
  Qiskit -> generateQiskit
  IRDump -> generateIRDump
  Visualization -> visualizeCircuit

-- | Standard-gate mnemonic shared by OpenQASM and Qiskit.
gateName :: Gate1 -> String
gateName g = case g of
  Hadamard -> "h"
  PauliX -> "x"
  PauliY -> "y"
  PauliZ -> "z"

controlledName :: Gate1 -> String
controlledName g = case g of
  Hadamard -> "ch"
  PauliX -> "cx"
  PauliY -> "cy"
  PauliZ -> "cz"

-- | OpenQASM 3. A probability query becomes measurements: real hardware
-- estimates the distribution by repeating the circuit.
generateOpenQASM :: IRProgram -> String
generateOpenQASM prog = unlines $
  [ "OPENQASM 3.0;"
  , "include \"stdgates.inc\";"
  ]
  ++ [ "qubit[" ++ show (irNumQubits prog) ++ "] q;" | irNumQubits prog > 0 ]
  ++ [ "bit[" ++ show (irNumBits prog) ++ "] c;" | irNumBits prog > 0 ]
  ++ concatMap line (irInstrs prog)
  where
    q i = "q[" ++ show i ++ "]"
    line i = case i of
      IGate g k -> [gateName g ++ " " ++ q k ++ ";"]
      IControlled g c t -> [controlledName g ++ " " ++ q c ++ ", " ++ q t ++ ";"]
      IMeasure k b -> ["c[" ++ show b ++ "] = measure " ++ q k ++ ";"]
      IProbe ks bs ->
        ["// probability query"]
        ++ ["c[" ++ show b ++ "] = measure " ++ q k ++ ";" | (k, b) <- zip ks bs]

-- | Python using Qiskit and the local Aer simulator.
generateQiskit :: IRProgram -> String
generateQiskit prog = unlines $
  [ "from qiskit import QuantumCircuit, transpile"
  , "from qiskit_aer import AerSimulator"
  , ""
  , "circuit = QuantumCircuit(" ++ show (irNumQubits prog) ++ ", " ++ show (irNumBits prog) ++ ")"
  , ""
  ]
  ++ concatMap line (irInstrs prog)
  ++
  [ ""
  , "backend = AerSimulator()"
  , "counts = backend.run(transpile(circuit, backend), shots=1024).result().get_counts()"
  , "print(counts)"
  ]
  where
    line i = case i of
      IGate g k -> ["circuit." ++ gateName g ++ "(" ++ show k ++ ")"]
      IControlled g c t -> ["circuit." ++ controlledName g ++ "(" ++ show c ++ ", " ++ show t ++ ")"]
      IMeasure k b -> ["circuit.measure(" ++ show k ++ ", " ++ show b ++ ")"]
      IProbe ks bs ->
        ["# probability query"]
        ++ ["circuit.measure(" ++ show k ++ ", " ++ show b ++ ")" | (k, b) <- zip ks bs]

-- | Plain textual dump of the IR.
generateIRDump :: IRProgram -> String
generateIRDump prog = unlines $
  [ "ir qubits=" ++ show (irNumQubits prog) ++ " bits=" ++ show (irNumBits prog) ]
  ++ map line (irInstrs prog)
  where
    line i = case i of
      IGate g k -> "  gate " ++ show g ++ " q" ++ show k
      IControlled g c t -> "  controlled " ++ show g ++ " control=q" ++ show c ++ " target=q" ++ show t
      IMeasure k b -> "  measure q" ++ show k ++ " -> c" ++ show b
      IProbe ks bs -> "  probe " ++ intercalate "," (map (("q" ++) . show) ks)
        ++ " -> " ++ intercalate "," (map (("c" ++) . show) bs)

-- | ASCII circuit diagram: one wire per qubit, one column per instruction.
visualizeCircuit :: IRProgram -> String
visualizeCircuit prog = unlines
  [ "q" ++ show k ++ pad k ++ " " ++ concatMap (cell k) (irInstrs prog)
  | k <- [0 .. irNumQubits prog - 1]
  ]
  where
    width = length (show (irNumQubits prog - 1))
    pad k = replicate (width - length (show k)) ' ' ++ ":"
    letter g = case g of
      Hadamard -> "H"
      PauliX -> "X"
      PauliY -> "Y"
      PauliZ -> "Z"
    cell k i = "-" ++ case i of
      IGate g t | t == k -> "[" ++ letter g ++ "]"
      IControlled _ c _ | c == k -> "-*-"
      IControlled g _ t | t == k -> "[" ++ letter g ++ "]"
      IMeasure t _ | t == k -> "[M]"
      IProbe ts _ | k `elem` ts -> "[P]"
      _ -> "---"

exportCircuit :: FilePath -> BackendType -> IRProgram -> IO ()
exportCircuit path backend prog = do
  writeFile path (generateBackend backend prog)
  putStrLn ("Exported to: " ++ path)
