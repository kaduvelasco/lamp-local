#!/bin/bash
# =============================================================================
# fix-virtualserver.sh — Corrige configuração Apache para instâncias Moodle
#
# Aplica uma configuração genérica do Apache que cobre todas as instâncias
# Moodle instaladas sob /var/www/html/mdle, habilitando AllowOverride e
# AcceptPathInfo (necessários para o roteamento interno do Moodle).
#
# Idempotência:
#   · Compara o conteúdo do .conf antes de reescrever
#   · Não recarrega o Apache se nada foi alterado
#   · Não reaplica permissões se owner e bits já estiverem corretos
#
# ⚠  Permissões 644/755 são adequadas para dev local.
#    Em produção, scripts e configs podem precisar de ajuste manual.
#
# Uso: sudo bash fix-virtualserver.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

APACHE_CONF_DIR="/etc/apache2/conf-available"
CONF_NAME="moodle-mdle.conf"
CONF_PATH="$APACHE_CONF_DIR/$CONF_NAME"
MOODLE_BASE="/var/www/html/mdle"

check_root
_init_log "fix-virtualserver"
enable_trap

echo ""
echo -e "${BOLD}Apache — Correção de VirtualServer para Moodle${RESET}"
echo ""

# -------------------------
# Verificações de pré-requisitos
# -------------------------
msg_section "Verificando pré-requisitos..."

if ! cmd_exists apache2; then
  msg_fatal "Apache não encontrado. Execute install-apache.sh primeiro."
fi

if ! service_active "apache2"; then
  msg_warn "Apache instalado mas inativo. Tentando iniciar..."
  log_cmd "Iniciar apache2" systemctl start apache2
fi

if [ ! -d "$MOODLE_BASE" ]; then
  msg_fatal "Diretório não encontrado: $MOODLE_BASE — instale o Moodle antes de executar este script."
fi

msg_ok "Pré-requisitos verificados."

# -------------------------
# Idempotência: gerar conteúdo esperado e comparar
# -------------------------
msg_section "Verificando configuração Apache: $CONF_NAME..."

EXPECTED_CONF="# Configuração genérica para todas as instâncias Moodle em $MOODLE_BASE
# Gerado por fix-virtualserver.sh

<Directory $MOODLE_BASE>
    Options FollowSymLinks
    AllowOverride All
    Require all granted
    AcceptPathInfo On
</Directory>"

CONF_CHANGED=false

if [ -f "$CONF_PATH" ]; then
  # Compara ignorando a linha de timestamp (segunda linha)
  EXISTING=$(grep -v "^# Gerado em" "$CONF_PATH" 2>/dev/null || echo "")
  EXPECTED_NODATE=$(echo "$EXPECTED_CONF" | grep -v "^# Gerado em")
  if [[ "$EXISTING" == "$EXPECTED_NODATE" ]]; then
    msg_ok "Configuração $CONF_NAME já está correta. Pulando reescrita."
  else
    msg_info "Configuração existente difere do esperado. Atualizando..."
    CONF_CHANGED=true
  fi
else
  msg_info "Configuração não encontrada. Criando..."
  CONF_CHANGED=true
fi

if [[ "$CONF_CHANGED" == true ]]; then
  cat > "$CONF_PATH" <<EOF
# Configuração genérica para todas as instâncias Moodle em $MOODLE_BASE
# Gerado em $(date '+%Y-%m-%d %H:%M:%S') por fix-virtualserver.sh

<Directory $MOODLE_BASE>
    Options FollowSymLinks
    AllowOverride All
    Require all granted
    AcceptPathInfo On
</Directory>
EOF
  msg_ok "Arquivo criado/atualizado: $CONF_PATH"
fi

# -------------------------
# Ativar configuração e módulos (idempotente por natureza)
# -------------------------
msg_section "Ativando configuração e módulos..."
log_cmd "a2enconf $CONF_NAME" a2enconf "$CONF_NAME" 2>&1 | grep -v "already enabled" || true
log_cmd "a2enmod rewrite actions alias proxy_fcgi setenvif" \
  a2enmod rewrite actions alias proxy_fcgi setenvif 2>&1 | grep -v "already enabled" || true
msg_ok "Configuração e módulos ativados."

# -------------------------
# Idempotência: permissões
# -------------------------
msg_section "Verificando permissões em $MOODLE_BASE..."

CURRENT_OWNER=$(stat -c '%U:%G' "$MOODLE_BASE" 2>/dev/null || echo "desconhecido")

if [[ "$CURRENT_OWNER" == "www-data:www-data" ]]; then
  msg_ok "Owner já é www-data:www-data. Verificando bits..."
  # Verifica apenas arquivos com permissão errada antes de aplicar find em tudo
  WRONG_DIRS=$(find "$MOODLE_BASE" -type d ! -perm 755 | wc -l)
  WRONG_FILES=$(find "$MOODLE_BASE" -type f ! -perm 644 | wc -l)

  if [[ "$WRONG_DIRS" -eq 0 && "$WRONG_FILES" -eq 0 ]]; then
    msg_ok "Permissões já corretas (dirs: 755, files: 644). Pulando."
  else
    msg_info "Corrigindo $WRONG_DIRS diretório(s) e $WRONG_FILES arquivo(s) com permissão errada..."
    find "$MOODLE_BASE" -type d ! -perm 755 -exec chmod 755 {} \;
    find "$MOODLE_BASE" -type f ! -perm 644 -exec chmod 644 {} \;
    msg_ok "Permissões corrigidas."
  fi
else
  msg_info "Owner atual: $CURRENT_OWNER. Aplicando www-data:www-data..."
  log_cmd "chown -R www-data:www-data $MOODLE_BASE" chown -R www-data:www-data "$MOODLE_BASE"
  find "$MOODLE_BASE" -type d -exec chmod 755 {} \;
  find "$MOODLE_BASE" -type f -exec chmod 644 {} \;
  msg_ok "Owner e permissões aplicados."
fi

msg_warn "Permissões 644 aplicadas globalmente. Verifique scripts e configs em produção."

# -------------------------
# Testar configuração do Apache
# -------------------------
msg_section "Testando configuração do Apache..."
if ! log_cmd "apachectl configtest" apachectl configtest; then
  msg_fatal "Configuração do Apache inválida. Verifique o log: ${LOG_FILE}"
fi

# -------------------------
# Recarregar Apache apenas se necessário
# -------------------------
msg_section "Recarregando Apache..."
if [[ "$CONF_CHANGED" == true ]]; then
  log_cmd "systemctl reload apache2" systemctl reload apache2
  msg_ok "Apache recarregado."
else
  msg_ok "Nenhuma alteração de configuração — reload não necessário."
fi

# -------------------------
# Resumo
# -------------------------
echo ""
echo -e "${BOLD}${GREEN}  Correção aplicada com sucesso!${RESET}"
echo ""
echo -e "  ${BOLD}Diretório base :${RESET} $MOODLE_BASE"
echo -e "  ${BOLD}Configuração   :${RESET} $CONF_PATH"
echo -e "  ${BOLD}Log            :${RESET} ${LOG_FILE}"
echo ""
msg_info "Todas as instâncias Moodle abaixo de $MOODLE_BASE estão cobertas."
msg_info "Se alguma instância ainda falhar, execute dentro dela:"
echo -e "       ${CYAN}php admin/cli/purge_caches.php${RESET}"
echo ""
