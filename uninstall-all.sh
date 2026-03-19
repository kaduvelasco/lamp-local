#!/bin/bash
# =============================================================================
# uninstall-all.sh — Reset total do ambiente LAMP (Apache + PHP + MariaDB)
#
# Remove completamente todos os componentes instalados pelos scripts deste
# conjunto, incluindo configurações, dados e PPAs Ondřej.
#
# ⚠⚠  ATENÇÃO — OPERAÇÃO DESTRUTIVA E IRREVERSÍVEL  ⚠⚠
#
# Este script irá APAGAR:
#   · Apache2 e todos os módulos
#   · Todas as versões de PHP instaladas
#   · MariaDB / MySQL e todos os dados
#   · /etc/apache2, /etc/php, /etc/mysql
#   · /var/log/apache2, /var/log/mysql
#   · Opcionalmente: /var/www (incluindo arquivos Moodle!)
#   · PPAs ppa:ondrej/php e ppa:ondrej/apache2
#
# Requer confirmação explícita com a palavra RESET antes de executar.
#
# Uso: sudo bash uninstall-all.sh
# =============================================================================

set -uo pipefail
# Nota: -e deliberadamente ausente neste script — operações de remoção devem
# continuar mesmo com erros parciais (pacote já removido, serviço inexistente).
# Cada bloco trata erros individualmente com || true ou msg_warn.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

check_root
_init_log "uninstall-all"
# Não usa enable_trap aqui: operações de remoção devem continuar mesmo com
# erros parciais (ex: pacote já removido). Erros são logados manualmente.

# -------------------------
# Aviso e confirmação
# -------------------------
echo ""
echo -e "${BOLD}${RED}  ╔═══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${RED}  ║      RESET TOTAL DO AMBIENTE WEB          ║${RESET}"
echo -e "${BOLD}${RED}  ║  Apache + PHP (todas versões) + MariaDB   ║${RESET}"
echo -e "${BOLD}${RED}  ╚═══════════════════════════════════════════╝${RESET}"
echo ""
msg_warn "Apache, PHP e MariaDB serão COMPLETAMENTE REMOVIDOS."
msg_warn "Configurações e dados do banco serão APAGADOS."
msg_warn "Esta operação é IRREVERSÍVEL."
echo ""

read -rp "  Para continuar, digite exatamente RESET: " CONFIRM
if [[ "$CONFIRM" != "RESET" ]]; then
  msg_error "Confirmação incorreta. Operação cancelada."
  _log "INFO " "Operação cancelada pelo usuário."
  exit 1
fi

_log "---  " "Confirmação recebida. Iniciando remoção."

# -------------------------
# Parar serviços
# -------------------------
msg_section "Parando serviços..."

_stop_service() {
  local svc="$1"
  if service_active "$svc" 2>/dev/null || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
    systemctl stop "$svc" 2>/dev/null && msg_ok "$svc parado." || msg_warn "Falha ao parar $svc (pode já estar inativo)."
    _log "INFO " "Serviço parado: $svc"
  else
    msg_info "$svc não está ativo. Pulando."
  fi
}

_stop_service apache2
_stop_service mariadb
_stop_service mysql

for svc_path in /lib/systemd/system/php*-fpm.service; do
  [ -e "$svc_path" ] || continue
  _stop_service "$(basename "$svc_path")"
done

# -------------------------
# Remover Apache
# -------------------------
msg_section "Removendo Apache..."
if pkg_installed apache2; then
  log_cmd "apt purge apache2" apt purge -y apache2 'apache2-*' libapache2-mod-fcgid 2>/dev/null || true
  msg_ok "Pacotes Apache removidos."
else
  msg_ok "Apache não estava instalado."
fi
rm -rf /etc/apache2 /var/lib/apache2 /var/log/apache2
msg_ok "Diretórios do Apache limpos."

# -------------------------
# Remover PHP (todas as versões)
# -------------------------
msg_section "Removendo PHP (todas as versões)..."
if dpkg -l 'php*' 2>/dev/null | grep -q '^ii'; then
  log_cmd "apt purge php*" apt purge -y 'php*' 'libapache2-mod-php*' 2>/dev/null || true
  msg_ok "Pacotes PHP removidos."
else
  msg_ok "Nenhuma versão PHP encontrada."
fi
rm -rf /etc/php /var/lib/php /run/php
msg_ok "Diretórios do PHP limpos."

# -------------------------
# Remover MariaDB / MySQL
# -------------------------
msg_section "Removendo MariaDB / MySQL..."
if pkg_installed mariadb-server || pkg_installed mysql-server; then
  log_cmd "apt purge mariadb-server mysql-server" \
    apt purge -y \
      mariadb-server mariadb-client mariadb-common \
      mysql-server mysql-client mysql-common 2>/dev/null || true
  msg_ok "Pacotes MariaDB/MySQL removidos."
else
  msg_ok "MariaDB/MySQL não estava instalado."
fi
rm -rf /etc/mysql /var/lib/mysql /var/log/mysql*
msg_ok "Diretórios do banco limpos."

# -------------------------
# Remover usuário e grupo mysql
# -------------------------
if getent passwd mysql >/dev/null 2>&1; then
  userdel -r mysql 2>/dev/null && msg_ok "Usuário 'mysql' removido." \
    || msg_warn "Não foi possível remover o usuário 'mysql'."
fi
if getent group mysql >/dev/null 2>&1; then
  groupdel mysql 2>/dev/null && msg_ok "Grupo 'mysql' removido." \
    || msg_warn "Não foi possível remover o grupo 'mysql'."
fi

# -------------------------
# Remover PPAs Ondřej
# -------------------------
msg_section "Removendo PPAs Ondřej..."
add-apt-repository --remove -y ppa:ondrej/php    2>/dev/null && msg_ok "PPA ondrej/php removido."    || msg_warn "PPA ondrej/php não encontrado."
add-apt-repository --remove -y ppa:ondrej/apache2 2>/dev/null && msg_ok "PPA ondrej/apache2 removido." || msg_warn "PPA ondrej/apache2 não encontrado."

# -------------------------
# Limpeza de pacotes órfãos
# -------------------------
msg_section "Limpando pacotes órfãos..."
log_cmd "apt autoremove" apt autoremove -y --purge
log_cmd "apt autoclean"  apt autoclean
msg_ok "Limpeza concluída."

# -------------------------
# Remoção de /var/www (confirmação extra)
# -------------------------
echo ""
msg_warn "/var/www pode conter arquivos Moodle e outros projetos web."
read -rp "  Confirmar REMOÇÃO TOTAL de /var/www? (sim/N): " CONFIRM_WWW

if [[ "$CONFIRM_WWW" =~ ^(sim|SIM)$ ]]; then
  rm -rf /var/www
  msg_ok "/var/www removido."
  _log "INFO " "/var/www removido pelo usuário."
else
  msg_info "/var/www mantido."
  _log "INFO " "/var/www mantido a pedido do usuário."
fi

# -------------------------
# Verificação final
# -------------------------
msg_section "Verificação final..."

cmd_exists apache2  \
  && msg_warn "Apache ainda presente no sistema." \
  || msg_ok  "Apache: removido."

cmd_exists php \
  && msg_warn "PHP ainda presente no sistema." \
  || msg_ok  "PHP: removido."

{ cmd_exists mariadb || cmd_exists mysql; } \
  && msg_warn "Banco de dados ainda presente no sistema." \
  || msg_ok  "MariaDB/MySQL: removido."

echo ""
echo -e "${BOLD}${GREEN}  Reset completo finalizado.${RESET}"
echo ""
msg_info "Log desta operação: ${LOG_FILE}"
msg_info "Sistema pronto para reinstalação limpa."
echo ""
