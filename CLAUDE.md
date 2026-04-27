# Language Rules

Communication with the user must follow these rules:

- Responses to the user must be written in **Brazilian Portuguese (pt-BR)**.
- All **documentation and Markdown files must be written in English** unless explicitly defined as a translation.
- **Code comments must be written in English.**
- Do not mix Portuguese and English inside the same documentation file.

Examples:

User explanation → Portuguese  
README / docs → English  
Code comments → English  

---

# Git Rules

AI agents must **NOT execute or simulate Git operations**.

Do NOT:

- run git commands
- create commits
- generate commit messages
- suggest git workflows unless explicitly requested

Version control is handled **manually by the user**.

AI agents should only:

- create files
- modify files
- propose changes

---

# Scope of Changes

AI agents must:

- modify only files relevant to the task
- avoid unnecessary refactors
- avoid large rewrites unless explicitly requested
- preserve the existing architecture and project structure

Prefer **small and precise changes**.

---

# Dependency Rules

Before introducing new dependencies:

- verify if the functionality already exists
- prefer native language features
- avoid adding heavy libraries

If a dependency is necessary:

- explain why it is needed
- keep the dependency minimal

---

# Code Quality

Generated code must:

- follow existing project conventions
- prioritize readability
- avoid unnecessary abstractions
- use clear naming conventions

---

# Documentation Rules

Documentation must follow these standards:

- Documentation files must be written in **English**
- Keep documentation clear and concise
- Follow **GitHub README conventions**
- Use Markdown best practices

Documentation files must be placed **in the project root unless otherwise specified**.

---

# README.md Requirements

The project must contain a `README.md` file in the **root directory**.

The README must follow **standard GitHub structure**:

Recommended sections:

- Project title
- Description
- Badges relevant to the project
- Features
- Installation
- Usage
- Configuration
- Contributing
- License (if applicable)

Badges should be **relevant to the project**, for example:

- language version
- CI status
- license
- package version
- code coverage

Avoid adding irrelevant badges.

---

# README Translation

A Portuguese translation of the README must exist.

Files:

```

README.md
LEIAME.md

```

Rules:

- `README.md` → English version
- `LEIAME.md` → Brazilian Portuguese translation

Both files must contain **a link to the counterpart language**.

Example in `README.md`:

```

📄 Portuguese version: see LEIAME.md

```

Example in `LEIAME.md`:

```

📄 English version: see README.md

```

The translation should preserve:

- section structure
- headings
- code examples

---

# Contributing Documentation

The project must include contribution guidelines.

Files:

```

CONTRIBUTING.md
CONTRIBUINDO.md

```

Rules:

- `CONTRIBUTING.md` → English
- `CONTRIBUINDO.md` → Brazilian Portuguese

Both files must contain **a link to the other language version**.

Example:

In `CONTRIBUTING.md`:

```

📄 Portuguese version: see CONTRIBUINDO.md

```

In `CONTRIBUINDO.md`:

```

📄 English version: see CONTRIBUTING.md

```

---

# Markdown File Signature

All Markdown files (`*.md`) created in this repository must end with the following signature:

```

---

Made with ❤️ and AI by [Kadu Velasco](https://github.com/kaduvelasco)

```

This signature must appear **at the end of the file**.

"Ensure the signature is only added once at the very end, even if the file is edited multiple times."

Files affected include:

- README.md
- LEIAME.md
- CONTRIBUTING.md
- CONTRIBUINDO.md
- documentation files
- any other Markdown documentation

---

# Security Practices

AI agents must never:

- expose credentials
- generate secrets
- commit API keys
- introduce insecure patterns

---

# General Principles

AI agents working in this repository should:

- respect the project structure
- keep changes minimal
- generate maintainable code
- avoid unnecessary complexity
- focus only on the requested task
```
# Guia de Desenvolvimento e Estilo Shell

Padrões de desenvolvimento adotados neste projeto. Todo script novo deve seguir estas convenções.

---

## Estrutura de um script

Todo script segue exatamente esta ordem de seções:

```bash
#!/usr/bin/env bash
# =============================================================================
# Nome do Script : nome-do-script.sh
# Descrição      : Uma linha descrevendo o propósito
# Versão         : 1.0.0
# =============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- carregamento de dependências ---
for _lib in utils.sh menu.sh system.sh docker.sh; do
    if [[ ! -f "$SCRIPT_DIR/lib/$_lib" ]]; then
        printf '\033[0;31m❌ Erro fatal: lib/%s não encontrado.\033[0m\n' "$_lib" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/lib/$_lib"
done
unset _lib

# --- funções de interface ---
show_header() { ... }

# --- funções auxiliares ---
helper_function() { ... }

# --- funções de negócio ---
install_x() { ... }

# --- ponto de entrada ---
main() {
    detect_pkg_manager
    show_header
    ...
}

main "$@"
```

Seções sem conteúdo são omitidas. A ordem nunca muda.

> **Nota**: Para scripts menores que usam apenas `utils.sh`, pode usar source direto em vez do loop:
> ```bash
> if [[ ! -f "$SCRIPT_DIR/lib/utils.sh" ]]; then
>     printf '\033[0;31m❌ Erro fatal: lib/utils.sh não encontrado.\033[0m\n' >&2
>     exit 1
> fi
> # shellcheck source=/dev/null
> source "$SCRIPT_DIR/lib/utils.sh"
> ```

---

## Opções do shell

```bash
set -euo pipefail
```

Obrigatório em todos os scripts, imediatamente após o shebang e cabeçalho.

| Flag | Efeito |
|------|--------|
| `-e` | Aborta ao primeiro erro não tratado |
| `-u` | Aborta ao usar variável não definida |
| `-o pipefail` | Propaga falha em pipelines |

---

## Variáveis

### Constantes de script

Sempre `readonly`. Sempre no topo, antes do `source`.

```bash
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="/opt/minha-app"
readonly APP_CMD="minha-app"
```

`SCRIPT_DIR` com o padrão `cd + pwd` é a forma canônica — resolve symlinks e garante caminho absoluto.

### Variáveis locais

Toda variável dentro de função é declarada com `local`. Nunca use variáveis globais implícitas.

```bash
minha_funcao() {
    local nome="$1"
    local versao="${2:-latest}"
    local resultado
    resultado=$(comando)
}
```

Declare e atribua separadamente quando o valor vem de substituição de comando — assim `-e` captura erros da substituição.

### Globals compartilhados

Globals que precisam ser visíveis a scripts filhos usam `export` seguido de `readonly`:

```bash
export PKG_MANAGER PKG_INSTALL PKG_UPDATE
readonly PKG_MANAGER PKG_INSTALL PKG_UPDATE
```

`readonly` após `export` impede reatribuição acidental sem perder a exportação.

---

## Paleta de cores

Definida inteiramente em `lib/utils.sh`. **Nunca redefina em scripts individuais.** As variáveis são exportadas e ficam disponíveis automaticamente após o `source`.

```
C1  vermelho    — erros, ações destrutivas
C2  verde       — sucesso, operações normais
C3  amarelo     — avisos, manutenção
C4  azul        — informativas, consulta
C5  magenta     — rótulos, bordas de menu
C6  ciano       — dicas, decorativos
H1  verde bold  — logo, linha principal
H2  verde       — logo, subtítulo
TS  (vazio)     — "Type Something", sem cor definida
RESET           — reset de cor
```

Uso:
```bash
printf '%b\n' "${C2}✅ Operação concluída.${RESET}"
printf '%b\n' "${C1}❌ Falhou.${RESET}"
```

---

## Saída padronizada

Use exclusivamente as funções de `lib/utils.sh`. Nunca use `echo` direto para mensagens de status.

```bash
die  "mensagem"        # stderr + exit 1. Aceita exit code opcional: die "msg" 2
warn "mensagem"        # stderr, sem sair
info "mensagem"        # stdout, informativo
success "mensagem"     # stdout, confirmação de sucesso
```

`die` e `warn` vão para `stderr` (`>&2`). `info` e `success` vão para `stdout`.

---

## Saída de texto

Prefira `printf` a `echo`. `echo -e` não é portável entre shells e implementações.

```bash
# Correto — interpreta escapes de cor via %b
printf '%b\n' "${C4}Mensagem informativa${RESET}"

# Correto — sem escape, sem newline (prompt de input)
printf '%s' "Digite o caminho: "

# Correto — escrever linha literal num arquivo
printf '%s\n' "$linha" >> "$arquivo"

# Correto — formatar variável de forma segura para shell
printf 'export VARIAVEL=%q\n' "$valor" >> "$arquivo"
```

`%q` é especialmente importante ao escrever variáveis fornecidas pelo usuário em arquivos de configuração — escapa automaticamente caracteres especiais.

---

## Verificação de comandos

```bash
# Correto — ignora aliases e funções do shell
is_installed_cmd "git"

# Evitar — detecta aliases, pode dar falso positivo
command -v git
```

`type -P` (usado internamente por `is_installed_cmd`) busca apenas binários no PATH.

---

## Gerenciador de pacotes

Nunca use `apt-get`, `dnf` ou `pacman` diretamente nos scripts de módulo. Use as abstrações de `lib/utils.sh`:

```bash
detect_pkg_manager          # detecta e exporta PKG_MANAGER (idempotente)
ensure_pkg "nome-do-pacote" # instala se não instalado (auto-detecta PKG_MANAGER)
is_installed_pkg "pacote" # verifica se pacote está instalado no sistema
```

`detect_pkg_manager` é idempotente — pode ser chamada várias vezes sem efeito colateral. Sempre chame no início de `main()`.

> **Dica**: Quando usar `apt-get`/`dnf`/`pacman` diretamente é inevitável (ex: adicionar repositório), use sempre `--` antes do nome do pacote para evitar injeção de flags:

```bash
sudo apt-get install -y -- "$pkg"
```

---

## Menus interativos

Menus usam `while true` com `break` ou `return 0` para sair. **Nunca use recursão** — funções recursivas acumulam stack e podem estourar em sessões longas.

```bash
show_menu() {
    while true; do
        show_header
  
        printf '%b\n' "O que você deseja <instrução>"
        printf '%b\n' ""
        printf '%b\n' "${C5}${RESET}  ${C2}1.${RESET} Opção um"
        printf '%b\n' "${C5}${RESET}  ${C1}0.${RESET} Voltar"
        printf '%b\n' ""
        printf '%s' "Selecione uma opção: "
        read -r choice

        case "$choice" in
            1) fazer_algo ;;
            0) return 0 ;;
            *) printf '%b\n' "${C1}❌ Opção inválida.${RESET}" ;;
        esac
    done
}
```

Opção inválida: exibe mensagem e continua o loop. Não use `sleep 1` — é desnecessário.

---

## Confirmações do usuário

Padrão uniforme em todo o projeto: `s` confirma, qualquer outra coisa (incluindo Enter) cancela.

```bash
echo -ne "   Deseja continuar? (${C3}s${RESET}/N): "
read -r confirm
[[ ! "$confirm" =~ ^[sS]$ ]] && return 0
```

Para ações destrutivas, o padrão é inverso — `s` confirma destrutivo:

```bash
echo -ne "   Tem certeza? (${C1}s${RESET}/N): "
read -r confirm
[[ "$confirm" =~ ^[sS]$ ]] || return 0
```

---

## Arquivos temporários

```bash
local temp_dir
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT      # garante limpeza mesmo com erro

local installer
installer=$(mktemp)
trap 'rm -f "$installer"' EXIT
```

`trap ... EXIT` é obrigatório para todo `mktemp`. Nunca confie em limpeza manual após comandos que podem falhar.

---

## Arquivos sensíveis (credenciais)

```bash
local bashrc_local="$HOME/.bashrc.local"

# 1. Criar com permissão restrita antes de escrever qualquer dado
if [[ ! -f "$bashrc_local" ]]; then
    (umask 077; touch "$bashrc_local")
fi

# 2. Remover linha existente de forma segura (sem sed com input do usuário)
grep -vF "MINHA_VARIAVEL" "$bashrc_local" 2>/dev/null > "${bashrc_local}.tmp" || true
mv -- "${bashrc_local}.tmp" "$bashrc_local"
chmod 600 "$bashrc_local"

# 3. Escrever novo valor escapado
printf 'export MINHA_VARIAVEL=%q\n' "$valor" >> "$bashrc_local"
```

Nunca use `sed -i "s|...|${variavel_usuario}|"` — o valor pode conter o delimitador `|` ou metacaracteres.

---

## Heredocs

Use `<<'EOF'` (aspas simples) quando o conteúdo é literal — evita expansão acidental de `$variavel`:

```bash
cat <<'EOF' > "$CONFIG_FILE"
{
  "chave": "valor_literal",
  "outra": "$HOME_nao_expande"
}
EOF
```

Use `<<EOF` (sem aspas) apenas quando a expansão de variáveis é necessária e intencional:

```bash
cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Exec=${INSTALL_DIR}/bin/app
Icon=${ICON_PATH}
EOF
```

---

## Detecção de arquitetura

Use `case` em vez de múltiplos `[[ ]] &&`:

```bash
local arch
arch=$(uname -m)

local pkg_file
case "$arch" in
    x86_64)        pkg_file="app-linux-amd64.deb" ;;
    aarch64|arm64) pkg_file="app-linux-arm64.deb" ;;
    *)             die "Arquitetura '${arch}' não suportada." ;;
esac
```

---

## Manipulação de strings

Prefira expansão de parâmetros bash a pipes com `sed`/`awk`/`xargs` para operações simples.

```bash
# Remover aspas simples e duplas
valor="${valor//\'/}"
valor="${valor//\"/}"

# Trim de espaços (leading e trailing)
valor="${valor#"${valor%%[![:space:]]*}"}"
valor="${valor%"${valor##*[![:space:]]}"}"

# Extrair extensão
ext="${arquivo##*.}"

# Remover extensão
base="${arquivo%.*}"
```

Evite `xargs` para processar input do usuário — interpreta metacaracteres do shell.

---

## `find` seguro

```bash
# Correto — limita profundidade, filtra por tipo, usa -- antes do destino
find "$dir" -maxdepth 3 -type f -name "*.ttf" -exec cp -- {} "$FONT_DIR/" \;

# Correto — usa -exec ... + para batchear (mais eficiente que \;)
find "$dir" -name "*.sh" -exec chmod +x {} +
```

Sempre adicione `-type f` para evitar operar em diretórios acidentalmente. Use `--` antes de caminhos que podem começar com `-`.

---

## `grep` seguro

```bash
grep -qF "string_literal" "$arquivo"    # -F: literal, não regex. -q: silencioso
grep -vF "string_literal" "$arquivo"    # -v: inverte (exclui linhas que contêm)
grep -qxF "$linha_exata" "$arquivo"     # -x: linha inteira deve casar
```

Use `-F` sempre que o padrão for uma string literal, não uma regex. Evita que caracteres como `.`, `*`, `[` sejam interpretados como metacaracteres.

---

## Proteção contra carregamento duplo (bibliotecas)

Arquivos em `lib/` que são `source`d por múltiplos scripts usam guarda de proteção:

```bash
[[ -n "${LUMINA_UTILS_LOADED:-}" ]] && return 0
readonly LUMINA_UTILS_LOADED=1
```

Coloque logo após o `set -euo pipefail` e o cabeçalho. Garante idempotência mesmo se o arquivo for carregado mais de uma vez na mesma sessão.

---

## Verificação de pré-condições

Agrupe as verificações no início de `main()`:

```bash
main() {
    detect_pkg_manager
    show_header
    require_not_root
    require_sudo
    require_internet   # apenas se necessário
    ...
}
```

Para verificar requisitos específicos, declare funções em `lib/system.sh`:

```bash
require_not_root() {
    [[ $EUID -eq 0 ]] && die "Este script não deve ser executado como root."
}

require_sudo() {
    sudo -v || die "Este script requer privilégios de sudo."
}

require_internet() {
    curl -fsSL https://checkip.amazonaws.com >/dev/null 2>&1 ||
        die "Este script requer conexão com a internet."
}
```

---

## CI — ShellCheck

O projeto usa ShellCheck com `--severity=warning --shell=bash --exclude=SC1091`.

- `SC1091` é ignorado globalmente pois o `source lib/xxx.sh` é resolvido em runtime.
- Outros `disable` inline são permitidos apenas com justificativa em comentário.
- Todo arquivo novo deve passar sem avisos antes do merge.

Para testar localmente:
```bash
shellcheck --severity=warning --shell=bash --exclude=SC1091 install.sh
shellcheck --severity=warning --shell=bash --exclude=SC1091 lib/utils.sh
```

---

## Cabeçalho padrão

```bash
# =============================================================================
# Exibe o cabeçalho ASCII padrão Lumina. $1 = subtítulo (opcional).
# =============================================================================
show_lumina_header() {
    local subtitle="${1:-LUMINA CLI ENGINE}"
    clear
    printf '%b\n' ""
    printf '%b\n' "░██                            ░██                      "
    printf '%b\n' "░██                                                     "
    printf '%b\n' "░██ ░██    ░██ ░█████████████  ░██░████████   ░██████   "
    printf '%b\n' "░██ ░██    ░██ ░██   ░██   ░██ ░██░██    ░██       ░██  "
    printf '%b\n' "░██ ░██    ░██ ░██   ░██   ░██ ░██░██    ░██  ░███████  "
    printf '%b\n' "░██ ░██   ░███ ░██   ░██   ░██ ░██░██    ░██ ░██   ░██  "
    printf '%b\n' "░██  ░█████░██ ░██   ░██   ░██ ░██░██    ░██  ░█████░██ "
    printf '%b\n' ""
    printf '%b\n' "${H2}${subtitle}${RESET} "
    printf '%b\n' ""
}
```

```bash
show_header() {
    show_lumina_header "LuminaDev — Workstation Setup"
}
```

## Estilo padrão para menus
```bash
show_main_menu() {
    show_header
    echo -e "O que você deseja fazer?"
    echo -e ""
    echo -e "  ${C2}1.${RESET} Instalar Fontes JetBrains Mono"
    echo -e "  ${C2}2.${RESET} Instalar Git e libsecret"
    echo -e "  ${C2}3.${RESET} Instalar LLMs (IA)"
    echo -e "  ${C2}4.${RESET} Instalar IDEs"
    echo -e "  ${C2}5.${RESET} Instalar Servidores MCP"
    echo -e "  ${C2}6.${RESET} Instalar Kitty Terminal"
    echo -e "  ${C4}7.${RESET} Desinstalador"
    echo -e "  ${C1}0.${RESET} Sair"
    echo -e ""
    echo -ne "Selecione uma opção: "
}
```



## Checklist — novo script

- [ ] Shebang `#!/usr/bin/env bash`
- [ ] Cabeçalho com Nome, Descrição, Versão
- [ ] `set -euo pipefail`
- [ ] `readonly SCRIPT_DIR=...`
- [ ] Guard de existência antes do `source lib/xxx.sh`
- [ ] `detect_pkg_manager` no início de `main()`
- [ ] Todas as variáveis de função declaradas com `local`
- [ ] Nenhuma paleta de cores local (vem do `utils.sh`)
- [ ] Nenhuma chamada direta a `echo -e` para mensagens de status (usar `die/warn/info/success`)
- [ ] Menus usam `while true`, não recursão
- [ ] `mktemp` sempre acompanhado de `trap ... EXIT`
- [ ] Arquivos sensíveis criados com `umask 077`
- [ ] Passa `shellcheck` sem avisos
