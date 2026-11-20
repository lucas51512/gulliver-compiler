module Main (main) where

import Control.Monad (forM_, unless, when)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

import Gulliver.AST (Program)
import Gulliver.Backend
import Gulliver.Interpreter
import Gulliver.Parser
import Gulliver.Simulator (describeState)
import Gulliver.TypeChecker

data Options = Options
  { optFile :: Maybe FilePath
  , optSeed :: Int
  , optShots :: Maybe Int
  , optEmit :: Maybe BackendType
  , optCheckOnly :: Bool
  , optHelp :: Bool
  , optVersion :: Bool
  }

version :: String
version = "Gulliver Quantum Compiler v0.2.0"

main :: IO ()
main = do
  args <- getArgs
  case parseArgs args (Options Nothing 42 Nothing Nothing False False False) of
    Left err -> die' err
    Right opts
      | optVersion opts -> putStrLn version
      | optHelp opts || optFile opts == Nothing -> putStr helpText
      | otherwise -> maybe (return ()) (\f -> readFile f >>= compile opts) (optFile opts)

die' :: String -> IO a
die' msg = hPutStrLn stderr msg >> exitFailure

parseArgs :: [String] -> Options -> Either String Options
parseArgs [] o = Right o
parseArgs ("run" : rest) o = parseArgs rest o
parseArgs ("--help" : rest) o = parseArgs rest o { optHelp = True }
parseArgs ("--version" : rest) o = parseArgs rest o { optVersion = True }
parseArgs ("--check" : rest) o = parseArgs rest o { optCheckOnly = True }
parseArgs ("--seed" : n : rest) o = case readMaybe n of
  Just s -> parseArgs rest o { optSeed = s }
  Nothing -> Left ("invalid seed: " ++ n)
parseArgs ("--shots" : n : rest) o = case readMaybe n of
  Just s | s > 0 -> parseArgs rest o { optShots = Just s }
  _ -> Left ("invalid shot count: " ++ n)
parseArgs ("--emit" : b : rest) o = case b of
  "qasm" -> parseArgs rest o { optEmit = Just QASM }
  "qiskit" -> parseArgs rest o { optEmit = Just Qiskit }
  "ir" -> parseArgs rest o { optEmit = Just IRDump }
  "circuit" -> parseArgs rest o { optEmit = Just Visualization }
  _ -> Left ("unknown backend: " ++ b ++ " (use qasm, qiskit, ir or circuit)")
parseArgs (flag@('-' : _) : _) _ = Left ("unknown option: " ++ flag)
parseArgs (f : rest) o = parseArgs rest o { optFile = Just f }

compile :: Options -> String -> IO ()
compile opts source = do
  prog <- either (\e -> die' ("Parse error: " ++ e)) return (parseProgram source)
  either (\e -> die' ("Type error: " ++ renderTypeError e)) return (checkProgram prog)
  unless (optCheckOnly opts) $ do
    result <- either (\e -> die' ("Runtime error: " ++ e)) return (runProgram (optSeed opts) prog)
    -- When emitting code, keep stdout clean so it can be piped to a file.
    case optEmit opts of
      Just backend -> putStr (generateBackend backend (rrIR result))
      Nothing -> report opts prog result
  when (optCheckOnly opts) $ putStrLn "OK: program parses and type checks"

report :: Options -> Program -> RunResult -> IO ()
report opts prog result = do
  putStrLn ("Result: " ++ renderValue (rrValue result))
  forM_ (rrWarnings result) $ \w -> putStrLn ("warning: " ++ w)
  putStrLn ""
  putStrLn "Quantum state (amplitudes, qubit 0 first):"
  if rrNumQubits result == 0
    then putStrLn "  (no qubits allocated)"
    else mapM_ (putStrLn . ("  " ++)) (describeState (rrNumQubits result) (rrState result))
  forM_ (optShots opts) $ \n -> do
    hist <- either (\e -> die' ("Runtime error: " ++ e)) return (runShots n (optSeed opts) prog)
    putStrLn ""
    putStrLn ("Results over " ++ show n ++ " shots:")
    forM_ hist $ \(label, count) ->
      putStrLn ("  " ++ label ++ ": " ++ show count)

helpText :: String
helpText = unlines
  [ version
  , ""
  , "Usage: gulliver-cli [run] FILE [OPTIONS]"
  , ""
  , "Options:"
  , "  --seed N        Seed for measurement outcomes (default 42)"
  , "  --shots N       Run the program N times and print a histogram of the results"
  , "  --emit BACKEND  Print generated code instead of running output:"
  , "                  qasm | qiskit | ir | circuit"
  , "  --check         Parse and type check only"
  , "  --version       Show version"
  , "  --help          Show this help"
  ]
