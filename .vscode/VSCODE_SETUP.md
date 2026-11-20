# VS Code Setup for Gulliver

Este diretório contém configurações do VS Code para suporte completo à linguagem Gulliver.

## Arquivos de Configuração

### `.vscode/language-configuration.json`
- **Propósito**: Define comportamentos básicos da linguagem
- **Contém**:
  - Comentários (`//` e `/* */`)
  - Auto-indentação
  - Pares de brackets automáticos `{}`, `[]`, `()`
  - Regras de folding

### `.vscode/gulliver.tmLanguage.json`
- **Propósito**: Define syntax highlighting (coloração de código)
- **Contém**:
  - Padrões para keywords: `quantum`, `fn`, `var`, `local`, `final`, `in`
  - Padrões para gates: `superposite`, `bitflip`, `phaseflip`, `entangle`
  - Padrões para tipos: `Qubit`, `QuantumRegister`, `Result`
  - Coloração para strings, números, comentários, operadores

### `.vscode/settings.json`
- **Propósito**: Configurações do espaço de trabalho
- **Contém**:
  - Associação de extensão `.gll` com linguagem `gulliver`
  - Preferências de edição (indentação 2 espaços, word wrap)
  - Configurações de formatação

### `.vscode/launch.json`
- **Propósito**: Configurações de debugging
- **Contém**:
  - Executar arquivo Gulliver atual
  - Build com `cabal build`
  - Tests com `cabal test`

### `.vscode/tasks.json`
- **Propósito**: Tarefas de build e execução
- **Contém**:
  - Build: `cabal build`
  - Tests: `cabal test`
  - Executar exemplos individuais
  - Clean: `cabal clean`

### `.vscode/extensions.json`
- **Propósito**: Recomendações de extensões
- **Recomenda**: Material Icon Theme e temas populares

## Cores Definidas

| Elemento | Cor | Escopo |
|----------|-----|--------|
| Keywords | Azul | `keyword.control.gulliver`, `keyword.declaration.gulliver` |
| Types | Verde | `support.type.gulliver` |
| Gates | Função amarela | `support.function.gate.gulliver` |
| Strings | Vermelho | `string.quoted.double.gulliver` |
| Números | Roxo | `constant.numeric.gulliver` |
| Comentários | Cinza | `comment.line.double-slash.gulliver` |

## Como Usar

### 1. Abrir o projeto no VS Code
```bash
code /path/to/gulliver-compiler
```

### 2. Ver syntax highlighting
- Abra qualquer arquivo `.gll` (ex: `examples/superposition.gll`)
- O código será automaticamente colorido conforme a grammar definida

### 3. Executar tarefas (Ctrl+Shift+B)
- **Build Gulliver**: Compila o projeto com Cabal
- **Run Tests**: Executa testes unitários
- **Run Example: [Nome]**: Executa um dos exemplos

### 4. Debugging
- Pressione F5 ou vá em **Run → Run and Debug**
- Selecione a configuração desejada

## Personalizações Recomendadas

Se quiser customizar as cores ainda mais, edite `gulliver.tmLanguage.json`:

### Adicionar nova cor para nova keyword:
```json
{
  "name": "keyword.custom.gulliver",
  "match": "\\b(minhapalavra)\\b"
}
```

### Mudar cores para um tema específico:
Edite `.vscode/settings.json`:
```json
"[gulliver]": {
  "editor.tokenColorCustomizations": {
    "textMateRules": [
      {
        "scope": "keyword.control.gulliver",
        "settings": {"foreground": "#FF0000"}
      }
    ]
  }
}
```

## Temas Recomendados

Para melhor experiência com syntax highlighting:

1. **Dracula Official** (`dracula-theme.theme-dracula`)
   - Cores vibrantes e bem contrastadas
   - Excelente para trabalhar por longas horas

2. **Material Icon Theme** (`pkief.material-icon-theme`)
   - Ícones melhorados para arquivos `.gll`

3. **Tomorrow Night Eighties** (incluído no VS Code)
   - Paleta minimalista e confortável

## Troubleshooting

### Código não está colorido
- Verifique se o arquivo tem extensão `.gll`
- Reinicie o VS Code (Command Palette → Developer: Reload Window)
- Verifique se `gulliver.tmLanguage.json` está no diretório `.vscode`

### Syntax highlighting está fraco
- Mude para um tema diferente (File → Preferences → Color Theme)
- Instale um dos temas recomendados

### Tarefas não aparecem
- Pressione `Ctrl+Shift+B` para abrir task runner
- Se não aparecer, verifique se `tasks.json` está no diretório `.vscode`

## Próximos Passos

Para melhor integração com VS Code (futuro):

1. **Criar extensão VS Code oficial**
   - Publicar no VS Code Marketplace
   - Incluir snippets de código
   - Adicionar language server para intellisense

2. **Adicionar snippets** (`.vscode/gulliver.code-snippets`)
   - Templates para funções quantum
   - Exemplos de gates
   - Padrões comuns

3. **Adicionar problema matcher personalizado**
   - Capturar erros de compilação
   - Exibir problemas inline

---

**Última atualização**: Novembro 2024
**Linguagem**: Gulliver 1.0
**VS Code**: v1.95+
