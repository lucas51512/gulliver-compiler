# VS Code - Quick Start 🎨

## ⚡ 30 segundos de setup

1. **Abra a pasta no VS Code:**
   ```bash
   code /home/lucas/Downloads/gulliver-compiler
   ```

2. **Abra um arquivo .gll**
   - Clique em `examples/superposition.gll`
   - As cores aparecem automaticamente ✨

3. **Teste as tarefas**
   - Pressione `Ctrl+Shift+B`
   - Escolha "Build Gulliver"
   - Ou escolha "Run Example: Superposition"

## 🎯 Atalhos Principais

| Atalho | Ação |
|--------|------|
| `Ctrl+Shift+B` | Menu de Tarefas |
| `F5` | Debug (Build/Run) |
| `Ctrl+/` | Comentar/Descomentar |
| `Ctrl+K Ctrl+F` | Formatar documento |
| `Ctrl+P` | Ir para arquivo |

## 🎨 Cores Configuradas

Seus arquivos `.gll` terão cores para:
- ✨ **Keywords** (quantum, fn, var, local, final, in) → Azul
- 🌟 **Gates** (superposite, bitflip, phaseflip, entangle) → Amarelo
- 🔵 **Types** (Qubit, Result, QuantumRegister) → Verde
- 🔴 **Strings** ("texto", 'texto') → Vermelho
- 🟣 **Números** (42, 3.14) → Roxo
- ⚫ **Comentários** (//, /* */) → Cinza

## 📋 Arquivos Configurados

```
.vscode/
├── language-configuration.json   ← Comportamento da linguagem
├── gulliver.tmLanguage.json      ← Cores e syntax highlighting
├── settings.json                 ← Configurações do editor
├── launch.json                   ← Debug (F5)
├── tasks.json                    ← Tarefas (Ctrl+Shift+B)
├── extensions.json               ← Recomendações
├── VSCODE_SETUP.md              ← Documentação completa
├── QUICK_START.md               ← Este arquivo
└── setup-info.sh                ← Script de info
```

## 🎯 Próximas Ações

1. ✅ Fechar e reabrir VS Code (force refresh)
2. ✅ Abrir `examples/superposition.gll`
3. ✅ Verificar se as cores aparecem
4. ✅ Pressionar `Ctrl+Shift+B` e rodar um exemplo

## 🐛 Se as cores não aparecerem

1. **Recarregar VS Code:**
   - Pressione `Ctrl+Shift+P`
   - Digite "reload"
   - Escolha "Developer: Reload Window"

2. **Mudar tema:**
   - Pressione `Ctrl+Shift+P`
   - Digite "color theme"
   - Escolha "Dracula" ou outro tema

3. **Verificar linguagem:**
   - Canto inferior direito do VS Code
   - Deve dizer "Gulliver" (não "Plain Text")
   - Se disser outro, clique e selecione "Gulliver"

## 📚 Documentação

- **Linguagem**: Leia `LANGUAGE_USER_GUIDE.md` na raiz
- **Compilador**: Leia `COMPILER_ARCHITECTURE_GUIDE.md` na raiz
- **VS Code Setup**: Leia `.vscode/VSCODE_SETUP.md` completo

---

**Dúvida?** Veja `.vscode/VSCODE_SETUP.md` para troubleshooting completo.

**Pronto para começar!** 🚀
