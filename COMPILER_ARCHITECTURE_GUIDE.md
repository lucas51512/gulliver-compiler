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
* **Probability** (`VProb`): the exact outcome distribution of a measurement, computed from the amplitudes without sampling. `probability(measure(x))` does not collapse the state, but the qubits are consumed (see below). Probabilities are derived data; they are never used as the source of truth for quantum state.

### `measure` versus `probability(measure(...))`

| | `measure(q)` | `probability(measure(q))` |
|---|---|---|
| Result | one sampled `Result`/`Results` | exact `Probability` (Born rule) |
| State | collapses | **unchanged** |
| Resource | consumed | consumed (language rule) |
| IR | `IMeasure` | `IProbe` |

Consuming `q` after `probability` is a *language* decision, not a consequence
of quantum mechanics: it keeps the expression from being mistaken for a
measurement whose state can still be reused. Open design question: a
dedicated non-destructive `distribution(q)` / `inspect(q)` that borrows instead
of consuming would avoid the misleading `measure` inside `probability`. Not
implemented; the simulator-only meaning is also unobservable on hardware.

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
with the rest". If both are pure, neither qubit is entangled with anything, so
in particular not with each other, and a warning is emitted.

The check is a **heuristic with one-sided evidence**. Purity 1 on both operands
proves there is no entanglement between them. Purity below 1 proves nothing
about the pair: a qubit may be entangled with a third qubit. So the absence of
a warning is *not* a guarantee that `c` and `t` are entangled, and the warning
reads "no evidence of entanglement between the operands". A stronger check
would analyse the joint two-qubit state (and whether the global state is pure);
that is future work. `controlled` makes no such claim.

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

* Gates and operands **borrow** (temporary use, ownership stays). Binding, passing to a function and returning **move** (ownership transfers). `measure` and `probability(measure(...))` **consume** (no use afterwards, and the state is not handed to anyone). In the checker all three end with the name in the consumed set, but they stay distinct concepts for tuples, functions that take registers and libraries.
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

**Observed circuit, not compilable program.** The IR records what happened in
one execution. For

```
local r: Result = measure(q) in
if r then { bitflip(t); } else { phaseflip(t); }
```

only the branch taken is recorded; a backend cannot recover the other one.
A program IR would add `IBranch ClassicalExpr IRBlock IRBlock` and
`ILoop ClassicalExpr IRBlock` (roadmap, deliberately not implemented yet).

What the IR **guarantees**: the exact sequence of quantum instructions of that
execution, hardware independence (no QASM/Qiskit names), and that `runIR` with
the same seed reproduces the run. What it does **not** guarantee: the logic of
unexecuted paths, loop structure, or classical computation. Backends must read
only the IR, so Qiskit/OpenQASM quirks (bit order, `measure` syntax) stay in
`Backend` and never leak into the language semantics.
`runIR` re-executes an IR program on the simulator; with the same seed it
reproduces the original run, which is covered by the tests.

OpenQASM and Qiskit turn `IProbe` into measurements: hardware estimates a
distribution by repeating the circuit.

## Identity: circuits or computations?

Gulliver aims to be a language for *quantum computations*, not only circuit
descriptions. Each feature is judged by which side it serves:

| Feature | Adds |
|---|---|
| `superposite`, `bitflip`, `controlled` | primitive quantum operations (circuit side) |
| `entangle` | intent abstraction |
| `quantum fn` | composition and abstraction of programs |
| `Probability` | interface between quantum state and classical information |
| program IR (branches/loops) | result-dependent control flow |
| oracles, amplification (removed stubs; may return) | higher-level algorithmic abstractions |

## Adding things

**A gate.** Add a constructor to `Gate1`, its matrix in `Simulator.gateMatrix`,
names in `Backend` (`gateName`, `controlledName`, `visualizeCircuit`), and a
surface keyword in `Parser.gateKeywords` if it needs one.

**A backend.** Add a constructor to `BackendType` and a function
`IRProgram -> String` in `Backend`, then a flag value in `app/Main.hs`.

## Testing

`test/Main.hs` is a dependency-free executable test suite (`cabal test`). It
covers numeric checks (amplitudes, exact distributions), statistical checks over many shots (Bell, GHZ, interference, Deutsch), lexing, parsing, type and resource errors, interference and phase,
entanglement correlation, probabilities, the `entangle` warning, IR
consistency, backends, and runs every file in `examples/`.

## Roadmap

1. **Consolidate** the language: formalize operation semantics, keep docs and code in sync (this document), maintain the examples (Bell, GHZ, Deutsch, ...).
2. **Computational model:** state vs outcome vs probability (done), memory model (done); next, richer linear typing (e.g. quantum values in tuples and functions with borrowing), classical-quantum formalization.
3. **IR:** dynamic circuits (measurement-dependent control flow), optimizations (gate cancellation), a stable textual IR format.
4. **Ecosystem:** standard library, more algorithms (Grover with oracles, QFT), hardware integration, editor tooling.
