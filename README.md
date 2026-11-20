# Gulliver Quantum Programming Language Compiler

A high-level quantum language and compiler in Haskell.

```gulliver
quantum fn coin_flip() -> Probability {
    local q: Qubit = new Qubit() in

    superposite(q);

    probability(measure(q))
}

coin_flip()
```

* **State, outcome and probability are different things.** `Qubit` and `QuantumRegister` hold complex amplitudes (phase and interference included); `Result`/`Results` are classical bits after measurement; `Probability` is the exact distribution of a measurement.
* **No-cloning is enforced** by an affine resource checker: using a qubit after `measure`, or copying it, is a compile error.
* **A hardware-independent IR** sits between the language and its targets: the built-in simulator, OpenQASM 3 and Qiskit.

## Documentation

* [LANGUAGE_USER_GUIDE.md](LANGUAGE_USER_GUIDE.md) - writing Gulliver programs.
* [COMPILER_ARCHITECTURE_GUIDE.md](COMPILER_ARCHITECTURE_GUIDE.md) - semantics, memory model, IR, resource checking, roadmap.

## Build and run

```bash
cabal build
cabal test
cabal run gulliver-cli -- examples/bell_state.gll
cabal run gulliver-cli -- examples/bell_state.gll --shots 100
cabal run gulliver-cli -- examples/bell_state.gll --emit qasm     # qasm | qiskit | ir | circuit
```

Options: `--seed N`, `--shots N`, `--emit BACKEND`, `--check`, `--help`.

Without cabal, the repository builds with plain GHC (only `base`, `containers`
and `mtl` are needed): `ghc -isrc -iapp app/Main.hs` (add `-dynamic` on
distributions that ship only dynamic GHC libraries, such as Arch Linux).

## Layout

```
src/Gulliver/   Lexer, Parser, AST, TypeChecker, Interpreter, Simulator, IR, Backend
app/Main.hs     command line interface
test/Main.hs    test suite
examples/       Bell, GHZ, superposition, coin flip, interference, Deutsch, scopes, entangle
gulliver-vscode/  VS Code extension (syntax highlighting)
```

## Language at a glance

| Feature | Syntax |
|---|---|
| Resources | `new Qubit()`, `new QuantumRegister(n)`, `r[i]` |
| Gates | `superposite(q)`, `bitflip(q)`, `phaseflip(q)`, `controlled(bitflip, c, t)` |
| Entanglement intent | `entangle(c, t)` (warns when it entangles nothing) |
| Measurement | `measure(q)` -> `Result`, `measure(r)` -> `Results` |
| Distribution | `probability(measure(x))` -> `Probability` |
| Bindings | `var` (mutable), `local`, `final`; all lexically scoped with `in` |
| Functions | `quantum fn`, `fn` (classical, no quantum operations) |
| Control | `if/then/else`, `for i in a..b` (inclusive), `while` |

## VS Code

Syntax highlighting lives in [gulliver-vscode/](gulliver-vscode). Symlink it into `~/.vscode/extensions/` and reload the window.
