#!/bin/bash
# =============================================================================
# lib.sh — Biblioteca compartilhada de funções utilitárias
#
# Utilizada por todos os scripts do conjunto. Deve ser "sourced", não executada.
# Fonte: source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# Fornece:
#   · Funções de mensagem colorida padronizadas
#   · Sistema de log com arquivo por sessão (sem cores)
#   · Wrapper log_cmd() para executar e logar comandos
#   · Trap de erro com contexto (linha, script, exit code)
#   · Funções de verificação (root, versão, serviço, pacote)
# =============================================================================

# --- Cores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Funções de mensagem (terminal + log) ---
msg_info()    { local m="  ➜  $*"; echo -e "${CYAN}${m}${RESET}";              _log "INFO " "$*"; }
msg_ok()      { local m="  ✔  $*"; echo -e "${GREEN}${m}${RESET}";             _log "OK   " "$*"; }
msg_warn()    { local m="  ⚠  $*"; echo -e "${YELLOW}${m}${RESET}";            _log "WARN " "$*"; }
msg_error()   { local m="  ✖  $*"; echo -e "${RED}${m}${RESET}" >&2;           _log "ERROR" "$*"; }
msg_section() { local m="══  $*";  echo -e "\n${BOLD}${BLUE}${m}${RESET}";     _log "---  " "$*"; }
msg_fatal()   {
  local m="  ✖  $*"
  echo -e "${RED}${BOLD}${m}${RESET}" >&2
  _log "FATAL" "$*"
  exit 1
}

# --- Escrita no arquivo de log (sem cores ANSI) ---
_log() {
  local level="$1"; shift
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  # LOG_FILE é definido pelo script chamador ou por _init_log
  if [[ -n "${LOG_FILE:-}" ]]; then
    printf '[%s] [%s] %s\n' "$ts" "$level" "$*" >> "$LOG_FILE"
  fi
}

# --- Inicializar arquivo de log ---
# Uso: _init_log "nome-do-script"
# Se LOG_FILE já estiver definido (passado pelo install.sh), reutiliza.
_init_log() {
  local script_name="${1:-script}"
  if [[ -z "${LOG_FILE:-}" ]]; then
    local log_dir="/var/log/lamp-install"
    mkdir -p "$log_dir"
    LOG_FILE="${log_dir}/${script_name}-$(date '+%Y%m%d-%H%M%S').log"
    export LOG_FILE
  fi
  _log "---  " "========================================"
  _log "---  " "Iniciando: $script_name"
  _log "---  " "Script   : ${BASH_SOURCE[1]:-desconhecido}"
  _log "---  " "Usuário  : $(whoami) (EUID=$EUID)"
  _log "---  " "Sistema  : $(uname -a)"
  _log "---  " "========================================"
  msg_info "Log desta sessão: ${LOG_FILE}"
}

# --- Trap de erro com contexto ---
_trap_error() {
  local exit_code=$?
  local line_no="${1:-?}"
  local script="${BASH_SOURCE[1]:-${0}}"
  msg_error "Falha na linha ${line_no} de $(basename "$script") (exit code: ${exit_code})"
  _log "FATAL" "Falha na linha ${line_no} | script: $(basename "$script") | exit: ${exit_code}"
  msg_error "Verifique o log completo: ${LOG_FILE:-'(log não inicializado)'}"
}

# Ativa o trap — chamar após source lib.sh em cada script
enable_trap() {
  set -o pipefail
  trap '_trap_error $LINENO' ERR
}

# --- Executar comando logando stdout+stderr ---
# Uso: log_cmd "Descrição" comando arg1 arg2 ...
#
# Implementação com process substitution para capturar o exit code real
# do comando, evitando o problema do pipefail capturar o exit do pipe
# intermediário (o `while` sempre retorna 0, mascarando falhas).
log_cmd() {
  local desc="$1"; shift
  msg_info "$desc"
  _log "CMD  " "$ $*"

  local fifo rc=0
  fifo="$(mktemp -u)"
  mkfifo "$fifo"

  # Consumidor: lê do fifo, exibe indentado no terminal e grava no log
  while IFS= read -r line; do
    echo -e "        ${line}"
    printf '        %s\n' "$line" >> "${LOG_FILE:-/dev/null}"
  done < "$fifo" &
  local consumer_pid=$!

  # Produtor: executa o comando redirecionando para o fifo
  "$@" > "$fifo" 2>&1 || rc=$?

  # Aguarda o consumidor terminar de drenar o fifo antes de prosseguir
  wait "$consumer_pid" 2>/dev/null || true
  rm -f "$fifo"

  if [[ $rc -eq 0 ]]; then
    msg_ok "$desc — concluído."
  else
    msg_error "$desc — falhou (exit: $rc)."
    _log "ERROR" "Comando falhou com exit $rc: $*"
  fi

  return $rc
}

# --- Verificações comuns ---

check_root() {
  if [[ $EUID -ne 0 ]]; then
    msg_fatal "Este script deve ser executado como root. Use: sudo bash $0"
  fi
}

# Retorna 0 se o pacote apt está instalado
pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# Retorna 0 se o serviço systemd existe e está ativo
service_active() {
  systemctl is-active --quiet "$1" 2>/dev/null
}

# Retorna 0 se o serviço systemd está habilitado
service_enabled() {
  systemctl is-enabled --quiet "$1" 2>/dev/null
}

# Retorna 0 se o comando existe no PATH
cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Strip de códigos ANSI (para gravar saída limpa no log)
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}
