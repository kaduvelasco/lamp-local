#!/bin/bash
# =============================================================================
# install.sh — Menu principal de instalação do ambiente LAMP para Moodle
#
# Ponto de entrada do conjunto de scripts. Apresenta um menu interativo para
# instalar individualmente cada componente da stack:
#   MariaDB · Apache · PHP-FPM (7.4, 8.0, 8.1, 8.2, 8.3)
#
# Um único arquivo de log é criado por sessão em /var/log/lamp-install/
# e compartilhado com todos os scripts filhos via $LOG_FILE.
#
# Uso: sudo bash install.sh
#
# Ordem recomendada:
#   1. MariaDB  2. Apache  3. Pré-requisitos PHP  4. PHP (versão desejada)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

check_root
_init_log "install"
enable_trap
export LOG_FILE

# -------------------------
# Menu
# -------------------------
exibir_menu() {
  echo ""
  echo -e "${BOLD}╔══════════════════════════════╗${RESET}"
  echo -e "${BOLD}║   Menu de Instalação LAMP    ║${RESET}"
  echo -e "${BOLD}╚══════════════════════════════╝${RESET}"
  echo -e ""
  echo -e "1. Instalar MariaDB"
  echo -e "2. Instalar Apache"
  echo -e "3. Pré-requisitos do PHP"
  echo -e ""
  echo -e "4. Instalar PHP 7.4"
  echo -e "5. Instalar PHP 8.0"
  echo -e "6. Instalar PHP 8.1"
  echo -e "7. Instalar PHP 8.2"
  echo -e "8. Instalar PHP 8.3"
  echo -e ""
  echo -e "9. Instalar comando my-local"
  echo -e ""
  echo -e "0. Sair"
  echo ""
}

declare -A PHP_VERSIONS=([4]="7.4" [5]="8.0" [6]="8.1" [7]="8.2" [8]="8.3")

while true; do
  exibir_menu
  read -rp "  Opção: " escolha

  case "$escolha" in
    1) msg_section "Instalando MariaDB..."
       bash "$SCRIPT_DIR/install-mariadb.sh" ;;
    2) msg_section "Instalando Apache..."
       bash "$SCRIPT_DIR/install-apache.sh" ;;
    3) msg_section "Instalando pré-requisitos do PHP..."
       bash "$SCRIPT_DIR/install-php-prereqs.sh" ;;
    4|5|6|7|8)
       V="${PHP_VERSIONS[$escolha]}"
       msg_section "Instalando PHP $V..."
       bash "$SCRIPT_DIR/install-php.sh" "$V" ;;
    9)
       msg_section "Instalando comando my-local..."
       if [[ ! -f "$SCRIPT_DIR/my-local.sh" ]]; then
         msg_error "my-local.sh não encontrado em $SCRIPT_DIR"
       else
         bash "$SCRIPT_DIR/my-local.sh" --install
       fi ;;
    0) msg_ok "Saindo. Até mais!"
       _log "---  " "Sessão encerrada pelo usuário."
       break ;;
    *) msg_warn "Opção inválida. Digite um número entre 0 e 9." ;;
  esac
done

echo ""
msg_info "Log completo da sessão: ${LOG_FILE}"
