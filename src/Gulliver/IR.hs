-- | Gulliver IR: a hardware-independent description of a quantum execution.
--
-- The IR is the contract between the language front end and every execution
-- environment (the Haskell simulator, OpenQASM, Qiskit, ...). It is produced
-- by tracing the executed path of a program, so classical control flow is
-- already resolved and only quantum instructions remain.
module Gulliver.IR
  ( IRInstr(..)
  , IRProgram(..)
  , mkIRProgram
  , instrQubits
  ) where

import Gulliver.AST (Gate1)

data IRInstr
  = IGate Gate1 Int                -- ^ single-qubit gate on a qubit
  | IControlled Gate1 Int Int      -- ^ gate on target, controlled by a qubit (control, target)
  | IMeasure Int Int               -- ^ destructive measurement: qubit, classical bit
  | IProbe [Int] [Int]             -- ^ non-destructive distribution query: qubits, classical bits
  deriving (Show, Eq)

data IRProgram = IRProgram
  { irNumQubits :: Int
  , irNumBits :: Int
  , irInstrs :: [IRInstr]
  } deriving (Show, Eq)

mkIRProgram :: Int -> Int -> [IRInstr] -> IRProgram
mkIRProgram = IRProgram

instrQubits :: IRInstr -> [Int]
instrQubits i = case i of
  IGate _ q -> [q]
  IControlled _ c t -> [c, t]
  IMeasure q _ -> [q]
  IProbe qs _ -> qs
