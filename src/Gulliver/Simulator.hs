-- | State-vector simulator.
--
-- Quantum memory is a sparse map from basis-state index to complex amplitude.
-- Qubit k corresponds to bit k of the index; bit strings are displayed with
-- qubit 0 first. Amplitudes (including phase) are kept, so interference works.
module Gulliver.Simulator
  ( QState(..)
  , Amp
  , Distribution
  , Rng
  , initialState
  , mkRng
  , nextDouble
  , applyGate
  , applyControlled
  , probOne
  , measureQubit
  , distribution
  , purity
  , sampleDistribution
  , basisLabel
  , describeState
  , SimResult(..)
  , runIR
  ) where

import Data.Bits (shiftL, shiftR, setBit, clearBit, testBit, xor)
import Data.Complex
import Data.List (foldl')
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Word (Word64)
import Numeric (showFFloat)

import Gulliver.AST (Gate1(..))
import Gulliver.IR

type Amp = Complex Double

newtype QState = QState { qsAmps :: Map.Map Int Amp }
  deriving (Show, Eq)

-- | Outcome distribution: bit string (first qubit first) with its probability.
type Distribution = [(String, Double)]

-- | The state of every allocated qubit is |0>, i.e. only basis state 0 exists.
initialState :: QState
initialState = QState (Map.singleton 0 1)

------------------------------------------------------------------------------
-- Deterministic pseudo-random numbers (SplitMix64)

newtype Rng = Rng Word64
  deriving (Show, Eq)

mkRng :: Int -> Rng
mkRng = Rng . fromIntegral

nextWord :: Rng -> (Word64, Rng)
nextWord (Rng s) =
  let s' = s + 0x9E3779B97F4A7C15
      z1 = (s' `xor` (s' `shiftR` 30)) * 0xBF58476D1CE4E5B9
      z2 = (z1 `xor` (z1 `shiftR` 27)) * 0x94D049BB133111EB
  in (z2 `xor` (z2 `shiftR` 31), Rng s')

-- | Uniform double in [0, 1).
nextDouble :: Rng -> (Double, Rng)
nextDouble g =
  let (w, g') = nextWord g
  in (fromIntegral (w `shiftR` 11) / fromIntegral ((1 :: Word64) `shiftL` 53), g')

------------------------------------------------------------------------------
-- Gates

type Matrix = (Amp, Amp, Amp, Amp)

gateMatrix :: Gate1 -> Matrix
gateMatrix g = case g of
  Hadamard -> (h, h, h, -h) where h = (1 / sqrt 2) :+ 0
  PauliX -> (0, 1, 1, 0)
  PauliY -> (0, 0 :+ (-1), 0 :+ 1, 0)
  PauliZ -> (1, 0, 0, -1)

epsilon :: Double
epsilon = 1e-12

-- | Apply a 2x2 matrix to qubit k on every basis pair whose cleared index
-- satisfies the predicate (used to implement controls).
applyMatrix :: (Int -> Bool) -> Matrix -> Int -> QState -> QState
applyMatrix cond (m00, m01, m10, m11) k (QState m) =
  QState (foldl' store m updates)
  where
    bases = Set.toList . Set.fromList $
      [clearBit i k | i <- Map.keys m, cond (clearBit i k)]
    amp i = Map.findWithDefault 0 i m
    updates = concat
      [ [(i, m00 * a + m01 * b), (j, m10 * a + m11 * b)]
      | i <- bases
      , let j = setBit i k
      , let a = amp i
      , let b = amp j
      ]
    store acc (i, a)
      | magnitude a < epsilon = Map.delete i acc
      | otherwise = Map.insert i a acc

applyGate :: Gate1 -> Int -> QState -> QState
applyGate g = applyMatrix (const True) (gateMatrix g)

applyControlled :: Gate1 -> Int -> Int -> QState -> QState
applyControlled g c = applyMatrix (`testBit` c) (gateMatrix g)

------------------------------------------------------------------------------
-- Measurement and probabilities

probOne :: Int -> QState -> Double
probOne k (QState m) =
  sum [magnitude a ^ (2 :: Int) | (i, a) <- Map.toList m, testBit i k]

-- | Projective measurement of one qubit using a uniform random number in [0,1).
measureQubit :: Double -> Int -> QState -> (Bool, QState)
measureQubit r k st@(QState m) =
  let p1 = probOne k st
      outcome = r < p1
      kept = Map.filterWithKey (\i _ -> testBit i k == outcome) m
      norm = sqrt (sum [magnitude a ^ (2 :: Int) | a <- Map.elems kept])
      scaled = Map.map (/ (norm :+ 0)) kept
  in (outcome, QState scaled)

-- | Exact outcome distribution of measuring the given qubits (Born rule).
-- The state is not modified.
distribution :: [Int] -> QState -> Distribution
distribution qs (QState m) =
  let key i = [if testBit i q then '1' else '0' | q <- qs]
      acc = Map.fromListWith (+)
        [(key i, magnitude a ^ (2 :: Int)) | (i, a) <- Map.toList m]
  in filter ((> epsilon) . snd) (Map.toList acc)

-- | Purity Tr(rho^2) of the reduced state of qubit k. It equals 1 exactly
-- when the qubit is not entangled with the rest of the system. A purity below
-- 1 only says the qubit is entangled with /something/, not with a given qubit.
purity :: Int -> QState -> Double
purity k (QState m) =
  let rests = Set.toList . Set.fromList $ map (`clearBit` k) (Map.keys m)
      amp i = Map.findWithDefault 0 i m
      terms = [(amp r, amp (setBit r k)) | r <- rests]
      r00 = sum [magnitude a0 ^ (2 :: Int) | (a0, _) <- terms]
      r11 = sum [magnitude a1 ^ (2 :: Int) | (_, a1) <- terms]
      r01 = sum [a0 * conjugate a1 | (a0, a1) <- terms]
  in r00 * r00 + r11 * r11 + 2 * magnitude r01 ^ (2 :: Int)

-- | Draw an outcome from a distribution with a uniform number in [0,1).
sampleDistribution :: Double -> Distribution -> String
sampleDistribution _ [] = ""
sampleDistribution r dist = go r dist
  where
    go _ [(s, _)] = s
    go x ((s, p) : rest)
      | x < p = s
      | otherwise = go (x - p) rest
    go _ [] = ""

------------------------------------------------------------------------------
-- Presentation

basisLabel :: Int -> Int -> String
basisLabel n i = [if testBit i k then '1' else '0' | k <- [0 .. n - 1]]

-- | Human-readable amplitudes (phase included) for the first qubits.
describeState :: Int -> QState -> [String]
describeState n (QState m) =
  [ "|" ++ basisLabel n i ++ ">  amplitude " ++ fmt (realPart a) ++ sign (imagPart a)
      ++ fmt (abs (imagPart a)) ++ "i  probability "
      ++ showFFloat (Just 2) (100 * magnitude a ^ (2 :: Int)) "" ++ "%"
  | (i, a) <- Map.toList m
  ]
  where
    fmt x = showFFloat (Just 4) x ""
    sign x = if x < 0 then " - " else " + "

------------------------------------------------------------------------------
-- Executing an IR program

data SimResult = SimResult
  { srState :: QState
  , srBits :: Map.Map Int Bool
  , srProbes :: [Distribution]
  } deriving (Show, Eq)

-- | Execute an IR program on the simulator with a seeded random source.
runIR :: Int -> IRProgram -> SimResult
runIR seed prog =
  let (st, _, bits, probes) = foldl' step (initialState, mkRng seed, Map.empty, []) (irInstrs prog)
  in SimResult st bits (reverse probes)
  where
    step (st, g, bits, probes) instr = case instr of
      IGate gate q -> (applyGate gate q st, g, bits, probes)
      IControlled gate c t -> (applyControlled gate c t st, g, bits, probes)
      IMeasure q b ->
        let (r, g') = nextDouble g
            (outcome, st') = measureQubit r q st
        in (st', g', Map.insert b outcome bits, probes)
      IProbe qs _ -> (st, g, bits, distribution qs st : probes)
