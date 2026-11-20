# .vscode/ Directory - Gulliver VS Code Support

This directory contains all VS Code configuration files for the Gulliver quantum programming language compiler.

## 📋 Files Overview

### Core Configuration Files

**`gulliver.tmLanguage.json`** (3.1 KB)
- TextMate grammar for syntax highlighting
- Defines colors for:
  - Keywords: `quantum`, `fn`, `var`, `local`, `final`, `in`
  - Gates: `superposite`, `bitflip`, `phaseflip`, `entangle`
  - Types: `Qubit`, `QuantumRegister`, `Result`, etc.
  - Strings, numbers, comments, operators

**`language-configuration.json`** (742 bytes)
- Language behavior configuration
- Auto-indentation rules
- Bracket pairs and auto-closing
- Code folding markers
- Comment syntax

**`settings.json`** (363 bytes)
- Workspace settings
- File association: `.gll` → `gulliver`
- Editor preferences (2-space indentation, word wrap)

**`launch.json`** (1.1 KB)
- Debug configurations (press F5)
- Run current file
- Build with `cabal build`
- Run tests with `cabal test`

**`tasks.json`** (1.9 KB)
- Build tasks (press Ctrl+Shift+B)
- Build, test, and run examples
- Clean build
- Multiple examples available

**`extensions.json`** (133 bytes)
- Recommended VS Code extensions
- Material Icon Theme
- Dracula Theme
- Tomorrow Kit

### Documentation Files

**`QUICK_START.md`** (2.6 KB)
- 30-second quick start guide
- Main keyboard shortcuts
- Color scheme overview
- Troubleshooting for missing colors

**`VSCODE_SETUP.md`** (4.6 KB)
- Complete setup documentation
- File descriptions
- Usage instructions
- Personalization options
- Troubleshooting section

**`SETUP_SUMMARY.md`** (7.0 KB)
- Executive summary of VS Code setup
- Files created and their purposes
- Syntax highlighting examples
- Usage instructions
- Next steps checklist

**`setup-info.sh`** (7.6 KB)
- Bash script displaying setup information
- Shows all configured colors
- Displays file structure
- Quick reference

**`README.md`** (this file)
- Overview of .vscode directory

---

## 🚀 Quick Start

1. **Open in VS Code:**
   ```bash
   code /home/lucas/Downloads/gulliver-compiler
   ```

2. **Open a .gll file:**
   - Examples are in `examples/` folder
   - Colors will appear automatically ✨

3. **Run tasks:**
   - Press `Ctrl+Shift+B` to open task menu
   - Build, test, or run examples

4. **Debug:**
   - Press `F5` to open debug menu
   - Configure build/run/test

---

## 🎨 Syntax Highlighting

The grammar defines syntax highlighting for:

```gulliver
quantum fn superposition_example() -> QuantumRegister {
  var q: QuantumRegister = new QuantumRegister(1) in {
    superposite(q);           // High-level gate
    local result: Result = measure(q) in {
      return q;
    }
  }
}
```

**Colors applied:**
- Keywords (quantum, fn, var, etc.) → Blue
- Gates (superposite, bitflip, etc.) → Yellow
- Types (QuantumRegister, Result) → Green
- Strings → Red
- Numbers → Purple
- Comments → Gray

---

## ⌨️ Available Tasks

| Task | Command | Trigger |
|------|---------|---------|
| Build | `cabal build` | Ctrl+Shift+B |
| Test | `cabal test` | Ctrl+Shift+B |
| Run Examples | Various | Ctrl+Shift+B |
| Debug | Manual | F5 |

---

## 🎯 Available Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+B` | Open task menu |
| `F5` | Open debug menu |
| `Ctrl+/` | Toggle comment |
| `Ctrl+K Ctrl+F` | Format document |
| `Ctrl+P` | Go to file |

---

## 📚 Reading Order

1. **First time**: `.vscode/QUICK_START.md` (30 seconds)
2. **Learn setup**: `.vscode/VSCODE_SETUP.md` (10 minutes)
3. **Full overview**: `.vscode/SETUP_SUMMARY.md` (5 minutes)
4. **Language guide**: `../LANGUAGE_USER_GUIDE.md` (1+ hours)
5. **Compiler guide**: `../COMPILER_ARCHITECTURE_GUIDE.md` (1+ hours)

---

## 🐛 Troubleshooting

**Colors not appearing?**
1. Reload: `Ctrl+Shift+P` → "reload" → "Developer: Reload Window"
2. Check language: Bottom-right should say "Gulliver"
3. Try different theme: `Ctrl+Shift+P` → "color theme"

**Tasks not showing?**
1. Press `Ctrl+Shift+B` again
2. Verify `tasks.json` exists in this directory
3. Restart VS Code

**Debug not working?**
1. Verify `launch.json` exists in this directory
2. Press F5 to open debug menu
3. Select desired configuration

---

## ✨ What's Included

✅ Syntax highlighting with 40+ tokens  
✅ Auto-indentation and bracket matching  
✅ Code folding support  
✅ 7 build/run tasks  
✅ 3 debug configurations  
✅ Extension recommendations  
✅ Complete documentation  
✅ Quick start guides  

---

## 📊 Statistics

- **Total files**: 10
- **Configuration size**: ~21.5 KB
- **Documentation**: 4 guides (~19 KB)
- **Tokens defined**: 40+
- **Tasks configured**: 7
- **Debug configs**: 3

---

## 🔧 Customization

To add your own colors:

1. Edit `gulliver.tmLanguage.json`
2. Add new pattern in `repository` section
3. Use TextMate scope naming convention
4. Reload VS Code to see changes

To add new tasks:

1. Edit `tasks.json`
2. Add new task object
3. Use `type: "shell"` and `command` for shell tasks
4. Reload VS Code

---

## 📞 Support

- **Setup help**: Read `.vscode/QUICK_START.md`
- **Language help**: Read `../LANGUAGE_USER_GUIDE.md`
- **Compiler help**: Read `../COMPILER_ARCHITECTURE_GUIDE.md`
- **Troubleshooting**: Read `.vscode/VSCODE_SETUP.md`

---

**Last updated:** November 20, 2024  
**Setup version:** 1.0  
**VS Code:** 1.95+  
**Gulliver:** 1.0  
