# Gulliver Compiler - Architecture Guide

## Pipeline

```
Gulliver source (.gll)
        |  Lexer      (src/Gulliver/Lexer.hs)
        v
      tokens
        |  Parser     (src/Gulliver/Parser.hs)
        v
       AST            (src/Gulliver/AST.hs)
        |  TypeChecker (src/Gulliver/TypeChecker.hs)  types + affine resources
        v
  Interpreter         (src/Gulliver/Interpreter.hs)   runs classical code,
        |                                             drives the simulator,
        |                                             traces quantum operations
        v
  Gulliver IR         (src/Gulliver/IR.hs)            hardware independent
        |
        +--> Simulator (src/Gulliver/Simulator.hs)    state vector, in Haskell
        +--> Backend   (src/Gulliver/Backend.hs)      OpenQASM 3, Qiskit, circuit, IR dump
```

The language never depends on a backend: every backend reads the IR, not the
AST. The IR is the contract between the language and its execution
environments.

Dependencies are only `base`, `containers` and `mtl`.

## Modules

| Module | Responsibility |
|---|---|
| `Lexer` | Tokens with line/column; skips `//` and `/* */` comments. |
| `Parser` | Hand-written LL(1/2) parser; errors carry `line:col`. |
| `AST` | Types (`Qubit`, `QuantumRegister`, `Result`, `Results`, `Probability`, ...), expressions, gates. |
| `TypeChecker` | Type checking and the affine resource discipline. |
| `Simulator` | Sparse amplitude map, gates, measurement, Born-rule distributions, purity, seeded RNG, `runIR`. |
| `IR` | `IGate`, `IControlled`, `IMeasure`, `IProbe`. |
| `Interpreter` | Evaluation, memory model, IR tracing, shots. |
| `Backend` | IR to OpenQASM 3, Qiskit (Aer), ASCII circuit, IR dump. |

## Semantics

### Quantum state versus results versus probability

* **Quantum state** (`mQuantum`): complex amplitudes over all allocated qubits. Qubit `k` is bit `k` of the basis index; strings print qubit 0 first. Phase is preserved, so interference works.
* **Outcome** (`VResult`, `VResults`): classical bits from `measure`. Measurement is probabilistic (Born rule) using a seeded SplitMix64 generator, and collapses the state.
* **Probability** (`VProb`): the exact outcome distribution of a measurement, computed from the amplitudes without sampling. `probability(measure(x))` does not collapse the state, but the qubits are consumed. Probabilities are derived data; they are never used as the source of truth for quantum state.

### Memory model

1. Quantum state (amplitudes).
2. Measurement distributions (`Probability`).
3. Classical memory (environment of values and qubit handles).

A `QuantumRegister` is an ordered collection of handles into the single global
quantum system. Allocation is free in the sparse representation: a new qubit
is |0>, which adds no basis states.

### `entangle` and `controlled`

`entangle(c, t)` lowers to the same IR instruction as `controlled(bitflip, c, t)`
(a CNOT). The difference is the contract: `entangle` declares intent, and the
interpreter verifies it. After the operation it computes the purity
`Tr(rho^2)` of the reduced state of each qubit; purity 1 means "not entangled
with the rest". If both are pure a warning is emitted. `controlled` makes no
such claim.

### Bindings

`var`, `local` and `final` are all lexically scoped (`... in body`). `var` is
reassignable (`:=`); `local` and `final` are immutable. Quantum resources can
only use `local`: immutability of a binding does not make quantum use safe.

### Measuring registers

`measure(reg)` measures qubits in index order and returns `Results`
(`[Bool]`, rendered with qubit 0 first). Measuring `reg[i]` returns a `Result`.

## Resource checking (no-cloning)

No-cloning cannot be guaranteed by an ordinary type checker. `TypeChecker`
threads a set of consumed resources (`Whole x` or `Elem r i`) through the
checking and enforces an **affine** discipline:

* Gates and operands borrow. `measure`, binding, passing to a function and returning move.
* Using a consumed resource is `UseAfterConsume`.
* `r[i]` cannot be moved out of its register (`QubitAliasing`), so two handles to one qubit never exist in a name.
* `if` merges the consumption of both branches; loops may not consume outer resources (`ConsumedInLoop`).
* `entangle`/`controlled` operands must differ (`SameOperand`).
* Classical `fn`s cannot contain quantum operations.

**Limits:** statically tracked are variables and literal register indices. A
computed index (`r[i]`) is only checked by the interpreter at run time
(`qubit k was already measured`). Dropping a resource is allowed (affine).

## The IR

```haskell
data IRInstr
  = IGate Gate1 Int
  | IControlled Gate1 Int Int      -- control, target
  | IMeasure Int Int               -- qubit, classical bit
  | IProbe [Int] [Int]             -- non-destructive distribution query
```

The IR is produced by *tracing the executed path*: loops are unrolled and
function calls inlined, so only quantum instructions remain.
**Known limitation:** classical control flow that depends on a measurement
result is resolved on the sampled path and is not preserved as a branch in the
IR. Representing it (dynamic circuits) is part of the IR roadmap.
`runIR` re-executes an IR program on the simulator; with the same seed it
reproduces the original run, which is covered by the tests.

OpenQASM and Qiskit turn `IProbe` into measurements: hardware estimates a
distribution by repeating the circuit.

## Adding things

**A gate.** Add a constructor to `Gate1`, its matrix in `Simulator.gateMatrix`,
names in `Backend` (`gateName`, `controlledName`, `visualizeCircuit`), and a
surface keyword in `Parser.gateKeywords` if it needs one.

**A backend.** Add a constructor to `BackendType` and a function
`IRProgram -> String` in `Backend`, then a flag value in `app/Main.hs`.

## Testing

`test/Main.hs` is a dependency-free executable test suite (`cabal test`). It
covers lexing, parsing, type and resource errors, interference and phase,
entanglement correlation, probabilities, the `entangle` warning, IR
consistency, backends, and runs every file in `examples/`.

## Roadmap

1. **Consolidate** the language: formalize operation semantics, keep docs and code in sync (this document), maintain the examples (Bell, GHZ, Deutsch, ...).
2. **Computational model:** state vs outcome vs probability (done), memory model (done); next, richer linear typing (e.g. quantum values in tuples and functions with borrowing), classical-quantum formalization.
3. **IR:** dynamic circuits (measurement-dependent control flow), optimizations (gate cancellation), a stable textual IR format.
4. **Ecosystem:** standard library, more algorithms (Grover with oracles, QFT), hardware integration, editor tooling.
