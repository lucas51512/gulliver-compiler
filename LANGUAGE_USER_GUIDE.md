# Gulliver Quantum Programming Language - User Guide

Gulliver is a small, high-level quantum language. Programs live in `.gll` files.

```bash
gulliver-cli examples/bell_state.gll              # run
gulliver-cli examples/bell_state.gll --shots 100  # run 100 times, histogram of results
gulliver-cli examples/bell_state.gll --emit qasm  # print OpenQASM 3 (also: qiskit, ir, circuit)
gulliver-cli examples/bell_state.gll --check      # parse and type check only
```

`--seed N` fixes the random source (default 42), so runs are reproducible.

## 1. A first program

```gulliver
quantum fn coin_flip() -> Probability {
    local q: Qubit = new Qubit() in

    superposite(q);

    probability(measure(q))
}

coin_flip()
```

A file holds function definitions followed by an optional top-level expression.
What runs: the top-level expression; otherwise `main()`; otherwise the last
function that takes no parameters.

Syntax notes: `//` and `/* */` comments; statements are separated by `;`
(optional after a closing `}`); a declaration `... in` scopes over the rest of
its block; the last expression of a block is its value, and a trailing `;`
makes the block evaluate to `Unit`.

## 2. The model: state, measurement, probability

| Concept | Type | What it is |
|---|---|---|
| Quantum state | `Qubit`, `QuantumRegister` | Handles to quantum information *before* measurement. Internally complex amplitudes, so **phase and interference** are real. |
| Outcome | `Result` (one bit), `Results` (bit string) | A classical value obtained *after* measurement. |
| Probability | `Probability` | The exact distribution of the possible outcomes of a measurement. |

A qubit is **not** "a variable holding 50% of 0 and 50% of 1". Probabilities are
derived from amplitudes (Born rule); they cannot replace amplitudes, because
they lose phase. `examples/interference.gll` shows this: `H` then `Z` then `H`
always yields `1`, while `H` then `H` always yields `0`.

```gulliver
measure(q)               // Result: one random bit; q is consumed (collapsed)
probability(measure(q))  // Probability: the distribution of that measurement,
                         // computed exactly from the amplitudes; q is consumed
```

`probability(...)` only accepts `measure(...)` as its argument. On hardware the
distribution is estimated from repeated runs (shots); in the simulator it is
exact. `--shots N` samples a `Probability` result N times.

### Memory model

1. **Quantum state** - the amplitudes of all qubits together (entanglement lives here). Changed only by gates and measurement.
2. **Measurement distributions** - `Probability` values: derived, read-only summaries of (1).
3. **Classical memory** - `Int`, `Bool`, `Result`, `Results`, `Probability`, tuples, and the *handles* that name qubits. Ordinary program state.

A `QuantumRegister` is an ordered list of handles into the one global quantum
system. It is not a separate system: qubits from different registers can be
entangled with each other, and `r[i]` names the i-th qubit.

## 3. Types

`Qubit`, `QuantumRegister`, `Result`, `Results`, `Probability`, `Int`, `Bool`,
`Unit`, and tuples such as `(Result, Result)`.

```gulliver
new Qubit()
new QuantumRegister(n)     // n is an Int expression
r[i]                       // the i-th qubit of a register (0-based)
t.0                        // tuple element
```

## 4. Operations

| Operation | Meaning |
|---|---|
| `superposite(q)` | Hadamard. Spelling is deliberate; `superpose` is not accepted. |
| `bitflip(q)` | Pauli-X. |
| `phaseflip(q)` | Pauli-Z. Changes phase only, not probabilities directly. |
| `controlled(gate, c, t)` | Applies `gate` to `t` when `c` is 1. Gates: `superposite`, `bitflip`, `phaseflip`, `H`, `X`, `Y`, `Z`. |
| `entangle(c, t)` | Intent: *create entanglement between c and t*. See below. |
| `measure(x)` | Qubit -> `Result`. Register -> `Results`. |
| `probability(measure(x))` | Exact outcome distribution. |

Gates accept a `Qubit` or a whole `QuantumRegister` (applied to each qubit).
`H`, `X`, `Y`, `Z` and `CNOT(c, t)` are accepted as low-level aliases.

### `measure` on registers

`measure(r)` measures every qubit in index order and returns `Results`, a bit
string whose first character is qubit 0 (`"011"` means r[0]=0, r[1]=1, r[2]=1).
Measuring a single `r[i]` gives a `Result`.

### `entangle` vs `controlled`

`entangle(c, t)` is a CNOT. A CNOT is a *physical operation*; it creates
entanglement only if the control is in superposition and the target is changed
by X. Applied to `|00>` it entangles nothing. So Gulliver defines `entangle` as
an *intent* and checks it: if after the operation neither qubit is entangled
with the rest of the system, the run prints a warning
(`examples/entangle_intent.gll`). When you want the plain operation (for
example phase kickback in Deutsch, `examples/deutsch.gll`), write
`controlled(bitflip, c, t)`, which never warns.

## 5. Bindings

```gulliver
var   n: Int = 0 in  n := n + 1; n    // mutable classical binding
local q: Qubit = new Qubit() in ...   // immutable; the only form for qubits
final MAX: Int = 10 in ...            // immutable classical constant
```

All three are **lexically scoped** by `... in`. There are no global variables.
The type annotation is optional (`local r = measure(q) in ...`).

`final` means *classical immutability only*. It says nothing about whether a
qubit is used safely, so `var` and `final` are rejected for `Qubit` and
`QuantumRegister`; use `local` and the resource rules below.

## 6. Resource rules (no-cloning)

Qubits and registers are *affine resources*: they cannot be copied.

* Gates **borrow**: `superposite(q); bitflip(q);` is fine.
* `measure(q)` / `probability(measure(q))` **consume** `q`. Using it afterwards is a compile error.
* Binding to another name, passing to a function, and returning **move** the resource. After `local b = a`, `a` is gone.
* A qubit cannot be pulled out of a register into a name (`local a: Qubit = r[0]` is rejected); use `r[0]` directly as an operand.
* `entangle(q, q)` / `controlled(g, q, q)` are rejected.
* A resource declared outside a loop cannot be consumed inside it.
* Resources may be dropped unmeasured (affine, not strictly linear).

Checked at compile time for variables and literal indices (`r[0]`). With a
computed index (`r[i]`) the interpreter checks at run time that a qubit was not
already measured.

## 7. Functions

```gulliver
quantum fn ghz_state(n: Int) -> QuantumRegister { ... }   // may use quantum operations
fn add(a: Int, b: Int) -> Int { a + b }                   // classical: no quantum operations
```

The body must produce the declared return type. Classical functions cannot
allocate, operate on, or measure qubits, and cannot call quantum functions.
Function calls take only their arguments (no captured variables).

## 8. Control flow and operators

```gulliver
if c then a else b                  // else optional when the value is Unit
for i in 0..n-1 { ... }             // the upper bound is inclusive
while cond { ... }
return e                            // must be the last statement of the block
```

Operators: `+ - * / %`, `== != < <= > >=`, `&& || !`, unary `-`.

## 9. Examples

| File | Shows |
|---|---|
| `bell_state.gll` | Entanglement, correlated results |
| `ghz_state.gll` | Chains, register results (`Results`) |
| `superposition.gll` | Amplitudes of a returned register |
| `coin_flip.gll` | `Result` vs `Probability` |
| `interference.gll` | Phase and interference |
| `deutsch.gll` | An algorithm with an oracle |
| `variable_scopes.gll` | `var`, `local`, `final` |
| `entangle_intent.gll` | The `entangle` warning |

## 10. Common errors

| Message | Meaning |
|---|---|
| `'q' was already measured or moved and cannot be used again` | Use after `measure`, or after moving the resource. |
| `a qubit cannot be moved out of a register` | `local a = r[0]`; use `r[0]` as an operand. |
| `... needs two distinct qubits` | Same qubit used as control and target. |
| `'x' is not declared with 'var'` | Assignment to a `local`/`final`. |
| `quantum operation ... is not allowed in a classical fn` | Add `quantum` to the `fn`. |
| `warning: entangle(...) no entanglement was produced` | The control was not in superposition. |
