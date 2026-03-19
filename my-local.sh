#!/bin/bash
# =============================================================================
# my-local — Gerenciador do ambiente LAMP local (Moodle)
#
# Cobre três áreas de gestão do dia a dia:
#   · PHP         — alternar versão ativa (FPM + CLI + Apache)
#   · Banco       — backup, restore, remoção e otimização do MariaDB
#   · Permissões  — corrigir ownership e ACLs em /var/www
#
# Arquivo autossuficiente — não depende de lib.sh externo.
#
# Instalação como comando:
#   sudo bash my-local.sh --install
#   → copia para /usr/local/bin/my-local e torna executável
#   → após isso: sudo my-local
#
# Remoção do comando:
#   sudo bash my-local.sh --uninstall
#
# Uso direto (sem instalar):
#   sudo bash my-local.sh
# =============================================================================

set -euo pipefail

# =============================================================================
# BIBLIOTECA INTERNA (equivalente ao lib.sh)
# =============================================================================

# --- Cores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Funções de mensagem ---
msg_info()    { echo -e "${CYAN}  ➜  $*${RESET}";           _log "INFO " "$*"; }
msg_ok()      { echo -e "${GREEN}  ✔  $*${RESET}";          _log "OK   " "$*"; }
msg_warn()    { echo -e "${YELLOW}  ⚠  $*${RESET}";         _log "WARN " "$*"; }
msg_error()   { echo -e "${RED}  ✖  $*${RESET}" >&2;        _log "ERROR" "$*"; }
msg_section() { echo -e "\n${BOLD}${BLUE}══  $*${RESET}";   _log "---  " "$*"; }
msg_fatal()   {
  echo -e "${RED}${BOLD}  ✖  $*${RESET}" >&2
  _log "FATAL" "$*"
  exit 1
}

# --- Log ---
LOG_FILE=""

_log() {
  local level="$1"; shift
  [[ -z "${LOG_FILE:-}" ]] && return
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE"
}

_init_log() {
  local log_dir="/var/log/lamp-install"
  mkdir -p "$log_dir"
  LOG_FILE="${log_dir}/my-local-$(date '+%Y%m%d-%H%M%S').log"
  _log "---  " "========================================"
  _log "---  " "Iniciando: my-local"
  _log "---  " "Usuário  : $(whoami) (EUID=$EUID)"
  _log "---  " "Sistema  : $(uname -srm)"
  _log "---  " "========================================"
  msg_info "Log desta sessão: ${LOG_FILE}"
}

# --- Trap de erro ---
_trap_error() {
  local exit_code=$?
  local line_no="${1:-?}"
  msg_error "Falha na linha ${line_no} de my-local (exit: ${exit_code})"
  _log "FATAL" "Linha ${line_no} | exit: ${exit_code}"
  [[ -n "${LOG_FILE:-}" ]] && msg_error "Log completo: ${LOG_FILE}"
}

_enable_trap() {
  trap '_trap_error $LINENO' ERR
}

# --- log_cmd: executa comando exibindo e logando saída ---
log_cmd() {
  local desc="$1"; shift
  msg_info "$desc"
  _log "CMD  " "$ $*"

  local fifo rc=0
  fifo="$(mktemp -u)"
  mkfifo "$fifo"

  while IFS= read -r line; do
    echo -e "        ${line}"
    printf '        %s\n' "$line" >> "${LOG_FILE:-/dev/null}"
  done < "$fifo" &
  local consumer_pid=$!

  "$@" > "$fifo" 2>&1 || rc=$?

  wait "$consumer_pid" 2>/dev/null || true
  rm -f "$fifo"

  if [[ $rc -eq 0 ]]; then
    msg_ok "$desc — concluído."
  else
    msg_error "$desc — falhou (exit: $rc)."
    _log "ERROR" "Falhou com exit $rc: $*"
  fi

  return $rc
}

# --- Utilitários ---
check_root() {
  [[ $EUID -eq 0 ]] || msg_fatal "Execute como root: sudo my-local"
}

cmd_exists()     { command -v "$1" >/dev/null 2>&1; }
service_active() { systemctl is-active --quiet "$1" 2>/dev/null; }
pkg_installed()  { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

_pause() {
  echo ""
  read -rp "  Pressione Enter para continuar..." _
}

_submenu_header() {
  echo ""
  echo -e "${BOLD}${BLUE}══  $*${RESET}"
  echo ""
}

# =============================================================================
# AUTO-INSTALAÇÃO COMO COMANDO
# =============================================================================

INSTALL_PATH="/usr/local/bin/my-local"

cmd_install() {
  check_root
  echo ""
  msg_section "Instalando my-local como comando do sistema..."

  local src
  # Resolve o caminho real do script mesmo quando chamado via bash <script>
  src="$(realpath "${BASH_SOURCE[0]}")"

  if [[ "$src" == "$INSTALL_PATH" ]]; then
    msg_warn "my-local já está instalado em $INSTALL_PATH."
    exit 0
  fi

  cp "$src" "$INSTALL_PATH"
  chmod 755 "$INSTALL_PATH"

  msg_ok "Instalado em: $INSTALL_PATH"
  msg_info "Uso: sudo my-local"
  echo ""
}

cmd_uninstall() {
  check_root
  echo ""
  msg_section "Removendo my-local do sistema..."

  if [[ ! -f "$INSTALL_PATH" ]]; then
    msg_warn "my-local não está instalado em $INSTALL_PATH."
    exit 0
  fi

  rm -f "$INSTALL_PATH"
  msg_ok "my-local removido de $INSTALL_PATH."
  echo ""
}

# Processar flags antes de qualquer outra coisa
case "${1:-}" in
  --install)   cmd_install;   exit 0 ;;
  --uninstall) cmd_uninstall; exit 0 ;;
esac

# =============================================================================
# CONFIGURAÇÃO GLOBAL
# =============================================================================

APACHE_SERVICE="apache2"
DB_SERVICE="mariadb"
WEB_GROUP="www-data"
BASE_DIR="/var/www"
DIRECTORIES=("/var/www/html" "/var/www/data" "/var/www/databases")
INOTIFY_LIMIT=524288
BACKUP_FILENAME="backup-databases.sql"
MARIADB_PERF_CNF="/etc/mysql/mariadb.conf.d/99-moodle-performance.cnf"
PHP_FPM_ALT_NAME="php-fpm.sock"
PHP_FPM_ALT_LINK="/run/php/php-fpm.sock"

trap 'echo ""; msg_warn "Operação interrompida."; exit 1' SIGINT

# =============================================================================
# ÁREA 1 — PHP
# =============================================================================

_php_get_versions() {
  local versions=()
  for dir in /etc/php/*/fpm; do
    [[ -d "$dir" ]] && versions+=("$(basename "$(dirname "$dir")")")
  done
  # Ordena por versão
  printf '%s\n' "${versions[@]}" | sort -V
}

_php_stop_all_fpm() {
  msg_info "Parando todas as versões PHP-FPM..."
  systemctl stop 'php*-fpm' 2>/dev/null || true
  msg_ok "PHP-FPM parado."
}

_php_start_fpm() {
  local v="$1"
  local socket="/run/php/php$v-fpm.sock"

  log_cmd "Iniciar php$v-fpm" systemctl start "php$v-fpm"

  msg_info "Aguardando socket $socket..."
  local i
  for i in {1..15}; do
    [[ -S "$socket" ]] && return 0
    sleep 0.4
  done
  msg_fatal "Socket não criado após timeout: $socket"
}

_php_ensure_alternative() {
  local v="$1"
  local socket="/run/php/php$v-fpm.sock"
  local priority="${v//./}"

  if ! update-alternatives --query "$PHP_FPM_ALT_NAME" &>/dev/null; then
    msg_info "Registrando alternativa $PHP_FPM_ALT_NAME..."
    update-alternatives --install \
      "$PHP_FPM_ALT_LINK" "$PHP_FPM_ALT_NAME" "$socket" "$priority"
  fi
}

_php_set_fpm_socket() {
  local v="$1"
  local socket="/run/php/php$v-fpm.sock"
  _php_ensure_alternative "$v"
  log_cmd "Definir socket ativo: $socket" \
    update-alternatives --set "$PHP_FPM_ALT_NAME" "$socket"
}

_php_set_cli() {
  local v="$1"
  local bin="/usr/bin/php$v"
  [[ -x "$bin" ]] || msg_fatal "Binário PHP CLI não encontrado: $bin"
  log_cmd "Definir PHP CLI $v" update-alternatives --set php "$bin"
}

_php_configure_apache() {
  local v="$1"
  local conf="php${v}-fpm"
  local conf_file="/etc/apache2/conf-available/${conf}.conf"

  msg_info "Ajustando Apache para PHP $v..."
  a2enmod proxy proxy_fcgi setenvif >/dev/null 2>&1
  a2disconf 'php*-fpm' >/dev/null 2>&1 || true

  [[ -f "$conf_file" ]] || msg_fatal "Conf Apache não encontrada: ${conf}.conf"
  log_cmd "a2enconf $conf" a2enconf "$conf"
}

_php_reload_services() {
  apachectl configtest
  log_cmd "Recarregar Apache" systemctl reload "$APACHE_SERVICE"
  systemctl start "$DB_SERVICE" 2>/dev/null || true
}

_php_show_state() {
  echo ""
  echo -e "  ${BOLD}Estado do ambiente:${RESET}"
  echo -e "  PHP CLI    : $(php -v 2>/dev/null | head -n 1 || echo 'não encontrado')"
  echo -e "  Socket FPM : $(readlink -f "$PHP_FPM_ALT_LINK" 2>/dev/null || echo 'não encontrado')"
  echo -e "  Apache FPM : $(apachectl -M 2>/dev/null | grep -oE 'proxy[^ ]*|fcgi[^ ]*' | tr '\n' ' ' || echo 'nenhum')"
}

menu_php() {
  local versions=()
  while IFS= read -r v; do versions+=("$v"); done < <(_php_get_versions)

  if [[ ${#versions[@]} -eq 0 ]]; then
    msg_error "Nenhuma versão PHP-FPM instalada."
    _pause
    return
  fi

  while true; do
    _submenu_header "PHP — Alternar versão ativa"
    local i
    for i in "${!versions[@]}"; do
      echo -e "  $((i+1)). PHP ${versions[$i]}"
    done
    echo ""
    echo -e "  0. Voltar"
    echo ""
    read -rp "  Versão: " choice

    [[ "$choice" == "0" ]] && return

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || \
       [[ "$choice" -lt 1 ]] || \
       [[ "$choice" -gt "${#versions[@]}" ]]; then
      msg_warn "Opção inválida."
      sleep 1
      continue
    fi

    local VERSION="${versions[$((choice-1))]}"
    msg_section "Alternando para PHP $VERSION..."

    _php_stop_all_fpm
    _php_start_fpm        "$VERSION"
    _php_set_fpm_socket   "$VERSION"
    _php_set_cli          "$VERSION"
    _php_configure_apache "$VERSION"
    _php_reload_services

    _php_show_state
    echo ""
    msg_ok "Ambiente ativo com PHP $VERSION."
    _log "OK   " "PHP alternado para $VERSION"
    _pause
    return
  done
}

# =============================================================================
# ÁREA 2 — BANCO DE DADOS
# =============================================================================

_db_selecionar_diretorio() {
  # Seta BACKUP_DIR
  echo ""
  echo -e "  ${BOLD}Local do arquivo:${RESET}"
  echo -e "  1. Downloads ($HOME/Downloads)"
  echo -e "  2. /var/www/databases"
  echo -e "  3. Personalizado"
  echo ""
  read -rp "  Opção: " _dir_op

  case "$_dir_op" in
    1) BACKUP_DIR="$HOME/Downloads" ;;
    2) BACKUP_DIR="/var/www/databases" ;;
    3)
      read -rp "  Caminho completo: " _caminho
      [[ -d "$_caminho" ]] && BACKUP_DIR="$_caminho" || BACKUP_DIR="$HOME/Documents"
      ;;
    *) BACKUP_DIR="$HOME/Documents" ;;
  esac

  mkdir -p "$BACKUP_DIR"
  msg_ok "Diretório: $BACKUP_DIR"
}

_db_credenciais() {
  # Seta DB_USER e DB_PASSWORD
  read -rp "  Usuário: " DB_USER
  echo -n "  Senha  : "
  read -rs DB_PASSWORD
  echo ""
}

db_backup() {
  _submenu_header "Banco — Backup geral"

  read -rp "  Nome personalizado para o arquivo? (s/N): " _usar_nome
  [[ "$_usar_nome" =~ ^[sS]$ ]] && read -rp "  Nome do arquivo (.sql): " BACKUP_FILENAME

  _db_selecionar_diretorio
  _db_credenciais

  msg_info "Executando mysqldump..."
  if mysqldump -u "$DB_USER" -p"$DB_PASSWORD" --all-databases \
      > "$BACKUP_DIR/$BACKUP_FILENAME" 2>/dev/null; then
    msg_ok "Backup salvo em: $BACKUP_DIR/$BACKUP_FILENAME"
    _log "OK   " "Backup: $BACKUP_DIR/$BACKUP_FILENAME"
  else
    msg_error "Falha no backup. Verifique credenciais e estado do MariaDB."
    _log "ERROR" "mysqldump falhou para usuário: $DB_USER"
  fi
  _pause
}

db_restore() {
  _submenu_header "Banco — Restore"

  _db_selecionar_diretorio
  read -rp "  Nome do arquivo (.sql): " BACKUP_FILENAME

  local arquivo="$BACKUP_DIR/$BACKUP_FILENAME"
  if [[ ! -f "$arquivo" ]]; then
    msg_error "Arquivo não encontrado: $arquivo"
    _pause
    return
  fi

  _db_credenciais

  msg_info "Executando restore de $arquivo..."
  if mysql -u "$DB_USER" -p"$DB_PASSWORD" < "$arquivo" 2>/dev/null; then
    msg_ok "Restore concluído."
    _log "OK   " "Restore: $arquivo"
  else
    msg_error "Falha no restore. Verifique o arquivo e as credenciais."
    _log "ERROR" "mysql restore falhou: $arquivo"
  fi
  _pause
}

db_remover() {
  _submenu_header "Banco — Remover bancos de dados"
  msg_warn "Bancos do sistema não serão listados (mysql, information_schema, etc.)."
  echo ""

  _db_credenciais

  local DBS
  DBS=$(mysql -u "$DB_USER" -p"$DB_PASSWORD" -e "SHOW DATABASES;" 2>/dev/null \
    | grep -Ev "^(Database|mysql|information_schema|performance_schema|sys)$" || true)

  if [[ -z "$DBS" ]]; then
    msg_info "Nenhum banco de usuário encontrado."
    _pause
    return
  fi

  echo ""
  local db
  for db in $DBS; do
    read -rp "  Remover '$db'? (s/N): " resp
    if [[ "$resp" =~ ^[sS]$ ]]; then
      if mysql -u "$DB_USER" -p"$DB_PASSWORD" \
          -e "DROP DATABASE \`$db\`;" 2>/dev/null; then
        msg_ok "'$db' removido."
        _log "OK   " "Banco removido: $db"
      else
        msg_error "Falha ao remover '$db'."
      fi
    fi
  done
  _pause
}

db_verificar_tabelas() {
  _submenu_header "Banco — Verificar e otimizar tabelas"
  _db_credenciais
  log_cmd "mysqlcheck --all-databases --optimize" \
    mysqlcheck -u "$DB_USER" -p"$DB_PASSWORD" --all-databases --optimize
  _pause
}

db_otimizar_moodle() {
  _submenu_header "Banco — Otimizar MariaDB para Moodle"

  local TOTAL_RAM_MB BUFFER_POOL_MB
  TOTAL_RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
  BUFFER_POOL_MB=$((TOTAL_RAM_MB / 2))

  msg_info "RAM detectada      : ${TOTAL_RAM_MB} MB"
  msg_info "innodb_buffer_pool : ${BUFFER_POOL_MB} MB (50% da RAM)"
  echo ""
  read -rp "  Confirmar otimização? (s/N): " _conf
  if ! [[ "$_conf" =~ ^[sS]$ ]]; then
    msg_info "Cancelado."
    _pause
    return
  fi

  if [[ -f "$MARIADB_PERF_CNF" ]]; then
    local bak="$MARIADB_PERF_CNF.bak.$(date '+%Y%m%d-%H%M%S')"
    cp "$MARIADB_PERF_CNF" "$bak"
    msg_ok "Backup da conf anterior: $bak"
  fi

  cat > "$MARIADB_PERF_CNF" <<EOF
[mariadb]
max_allowed_packet             = 64M
innodb_buffer_pool_size        = ${BUFFER_POOL_MB}M
innodb_log_file_size           = 256M
innodb_file_per_table          = 1
innodb_flush_log_at_trx_commit = 2
binlog_format                  = ROW
EOF

  log_cmd "Reiniciar MariaDB" systemctl restart mariadb
  msg_ok "MariaDB otimizado para Moodle."
  _log "OK   " "MariaDB otimizado: buffer_pool=${BUFFER_POOL_MB}M"
  _pause
}

menu_banco() {
  while true; do
    _submenu_header "Banco de Dados — MariaDB"
    echo -e "  1. Backup geral"
    echo -e "  2. Restore"
    echo -e "  3. Remover bancos"
    echo -e "  4. Verificar / Otimizar tabelas"
    echo -e "  5. Otimizar MariaDB para Moodle"
    echo ""
    echo -e "  0. Voltar"
    echo ""
    read -rp "  Opção: " _op

    case "$_op" in
      1) db_backup ;;
      2) db_restore ;;
      3) db_remover ;;
      4) db_verificar_tabelas ;;
      5) db_otimizar_moodle ;;
      0) return ;;
      *) msg_warn "Opção inválida."; sleep 1 ;;
    esac
  done
}

# =============================================================================
# ÁREA 3 — PERMISSÕES
# =============================================================================

_perm_check_sudo_user() {
  if [[ -z "${SUDO_USER:-}" ]]; then
    msg_fatal "Usuário original não detectado. Execute via sudo, não como root direto."
  fi
  echo "$SUDO_USER"
}

_perm_fix_dir() {
  local dir="$1"
  local user="$2"

  if [[ ! -d "$dir" ]]; then
    msg_warn "Ignorado — diretório não existe: $dir"
    return
  fi

  msg_info "Ajustando: $dir"

  chown -R "$user:$WEB_GROUP" "$dir"
  chmod -R u=rwX,g=rwX,o=r "$dir"
  find "$dir" -type d -exec chmod g+s {} +

  setfacl -R -b "$dir"
  setfacl -R -m "u:$user:rwx,g:$WEB_GROUP:rwx" "$dir"
  setfacl -R -d -m "u:$user:rwx,g:$WEB_GROUP:rwx" "$dir"

  msg_ok "Concluído: $dir"
  _log "OK   " "Permissões: $dir (owner: $user:$WEB_GROUP)"
}

_perm_configure_inotify() {
  msg_info "Configurando fs.inotify.max_user_watches=$INOTIFY_LIMIT..."

  if grep -q "^fs.inotify.max_user_watches" /etc/sysctl.conf; then
    sed -i "s/^fs.inotify.max_user_watches=.*/fs.inotify.max_user_watches=$INOTIFY_LIMIT/" \
      /etc/sysctl.conf
  else
    echo "fs.inotify.max_user_watches=$INOTIFY_LIMIT" >> /etc/sysctl.conf
  fi

  sysctl -p >/dev/null 2>&1 || true
  msg_ok "inotify configurado (limite: $INOTIFY_LIMIT)."
  _log "OK   " "inotify max_user_watches=$INOTIFY_LIMIT"
}

menu_permissoes() {
  while true; do
    _submenu_header "Permissões — /var/www"
    echo -e "  1. Corrigir permissões (todos os diretórios)"
    echo -e "  2. Otimizar inotify para MegaSync"
    echo ""
    echo -e "  0. Voltar"
    echo ""
    read -rp "  Opção: " _op

    case "$_op" in
      1)
        _submenu_header "Permissões — Aplicando"
        local USER_OWNER
        USER_OWNER=$(_perm_check_sudo_user)

        msg_info "Usuário proprietário : $USER_OWNER"
        msg_info "Grupo web            : $WEB_GROUP"
        echo ""

        if ! cmd_exists setfacl; then
          log_cmd "Instalar pacote acl" apt install -y acl
        fi

        if ! id "$USER_OWNER" 2>/dev/null | grep -qw "$WEB_GROUP"; then
          log_cmd "Adicionar $USER_OWNER ao grupo $WEB_GROUP" \
            usermod -aG "$WEB_GROUP" "$USER_OWNER"
        else
          msg_ok "$USER_OWNER já pertence ao grupo $WEB_GROUP."
        fi

        chown root:"$WEB_GROUP" "$BASE_DIR"
        chmod 775 "$BASE_DIR"
        msg_ok "Base $BASE_DIR: root:$WEB_GROUP 775"

        local dir
        for dir in "${DIRECTORIES[@]}"; do
          _perm_fix_dir "$dir" "$USER_OWNER"
        done

        echo ""
        msg_ok "Permissões ajustadas com sucesso."
        msg_info "Reinicie o MegaSync para garantir que as ACLs sejam aplicadas."
        _pause
        ;;
      2)
        _submenu_header "Permissões — inotify"
        _perm_configure_inotify
        _pause
        ;;
      0) return ;;
      *) msg_warn "Opção inválida."; sleep 1 ;;
    esac
  done
}

# =============================================================================
# MENU PRINCIPAL
# =============================================================================

check_root
_init_log
_enable_trap

while true; do
  echo ""
  echo -e "${BOLD}╔══════════════════════════════╗${RESET}"
  echo -e "${BOLD}║     my-local — LAMP Moodle   ║${RESET}"
  echo -e "${BOLD}╚══════════════════════════════╝${RESET}"
  echo ""
  echo -e "  1. PHP         — alternar versão ativa"
  echo -e "  2. Banco       — backup, restore, otimização"
  echo -e "  3. Permissões  — corrigir /var/www"
  echo ""
  echo -e "  0. Sair"
  echo ""
  read -rp "  Opção: " escolha

  case "$escolha" in
    1) menu_php ;;
    2) menu_banco ;;
    3) menu_permissoes ;;
    0)
      msg_ok "Saindo."
      _log "---  " "Sessão encerrada pelo usuário."
      break
      ;;
    *) msg_warn "Opção inválida."; sleep 1 ;;
  esac
done

echo ""
msg_info "Log desta sessão: ${LOG_FILE}"
