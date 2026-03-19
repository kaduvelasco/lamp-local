#!/bin/bash
# =============================================================================
# install-apache.sh — Instalação do Apache (modo PHP-FPM para Moodle)
#
# Instala o Apache a partir do repositório Ondřej, configurado para trabalhar
# exclusivamente com PHP-FPM via proxy_fcgi. O mod_php é removido para evitar
# conflito com múltiplas versões PHP.
#
# Idempotência:
#   · Pula instalação se Apache já estiver presente e ativo
#   · Não duplica entradas no apache2.conf (ServerName, AcceptFilter WSL)
#   · Não recria var-www.conf se já existir
#
# Módulos ativados: proxy · proxy_fcgi · setenvif · rewrite · headers · env
#
# Uso: sudo bash install-apache.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

check_root
_init_log "install-apache"
enable_trap

echo ""
echo -e "${BOLD}Apache — Instalação (PHP-FPM Ready | Moodle)${RESET}"
echo ""

# -------------------------
# Idempotência: Apache já instalado?
# -------------------------
msg_section "Verificando instalação existente..."

if pkg_installed "apache2" && service_active "apache2"; then
  msg_ok "Apache já instalado e em execução."
  APACHE_ALREADY_INSTALLED=true
else
  APACHE_ALREADY_INSTALLED=false
  msg_info "Apache não encontrado ou inativo. Prosseguindo com a instalação."
fi

# -------------------------
# Dependência: software-properties-common
# -------------------------
if [[ "$APACHE_ALREADY_INSTALLED" == false ]]; then
  msg_section "Instalando dependências de sistema..."
  log_cmd "apt update" apt update -y
  log_cmd "Instalar software-properties-common" apt install -y software-properties-common

  msg_section "Adicionando repositório Ondřej (Apache)..."
  log_cmd "add-apt-repository ppa:ondrej/apache2" add-apt-repository -y ppa:ondrej/apache2
  log_cmd "apt update pós-PPA" apt update -y

  msg_section "Instalando Apache..."
  log_cmd "Instalar apache2" apt install -y apache2
fi

# -------------------------
# Remover mod_php (conflita com PHP-FPM)
# -------------------------
msg_section "Verificando conflitos com mod_php..."
if dpkg -l 'libapache2-mod-php*' 2>/dev/null | grep -q '^ii'; then
  log_cmd "Remover libapache2-mod-php*" apt purge -y 'libapache2-mod-php*'
  msg_ok "mod_php removido."
else
  msg_ok "mod_php não presente. Nenhuma ação necessária."
fi

# -------------------------
# Módulos essenciais para PHP-FPM
# -------------------------
msg_section "Verificando módulos essenciais..."

MODULES_NEEDED=(proxy proxy_fcgi setenvif rewrite headers env)
MODULES_TO_ENABLE=()

for mod in "${MODULES_NEEDED[@]}"; do
  if apachectl -M 2>/dev/null | grep -q "${mod}_module"; then
    msg_ok "Módulo já ativo: $mod"
  else
    MODULES_TO_ENABLE+=("$mod")
  fi
done

if [[ ${#MODULES_TO_ENABLE[@]} -gt 0 ]]; then
  log_cmd "a2enmod ${MODULES_TO_ENABLE[*]}" a2enmod "${MODULES_TO_ENABLE[@]}"
  msg_ok "Módulos ativados: ${MODULES_TO_ENABLE[*]}"
else
  msg_ok "Todos os módulos necessários já estão ativos."
fi

# -------------------------
# Idempotência: ServerName
# -------------------------
msg_section "Ajustando configuração global..."

if grep -q "^ServerName" /etc/apache2/apache2.conf; then
  msg_ok "ServerName já definido em apache2.conf. Pulando."
else
  echo "ServerName 127.0.0.1" >> /etc/apache2/apache2.conf
  msg_ok "ServerName definido como 127.0.0.1"
fi

# -------------------------
# Idempotência: var-www.conf
# -------------------------
if [ -f /etc/apache2/conf-available/var-www.conf ]; then
  msg_ok "var-www.conf já existe. Pulando."
else
  cat > /etc/apache2/conf-available/var-www.conf <<'EOF'
<Directory /var/www/>
  Options FollowSymLinks
  AllowOverride All
  Require all granted
</Directory>
EOF
  log_cmd "Ativar var-www.conf" a2enconf var-www
  msg_ok "var-www.conf criado e ativado."
fi

# -------------------------
# Idempotência: ajustes WSL
# -------------------------
if grep -qEi "(Microsoft|WSL)" /proc/version &>/dev/null; then
  if grep -q "AcceptFilter http none" /etc/apache2/apache2.conf; then
    msg_ok "Ajustes WSL já presentes em apache2.conf. Pulando."
  else
    msg_warn "Ambiente WSL detectado. Aplicando ajustes de AcceptFilter..."
    cat >> /etc/apache2/apache2.conf <<'EOF'

# Ajustes WSL — evita travamento de accept socket
AcceptFilter http none
AcceptFilter https none
EOF
    msg_ok "Ajustes WSL aplicados."
  fi
fi

# -------------------------
# Testar configuração
# -------------------------
msg_section "Testando configuração do Apache..."
if ! log_cmd "apachectl configtest" apachectl configtest; then
  msg_fatal "Configuração do Apache inválida. Verifique o log: ${LOG_FILE}"
fi

# -------------------------
# Ativar e iniciar
# -------------------------
msg_section "Ativando e iniciando Apache..."
log_cmd "Habilitar apache2" systemctl enable apache2
log_cmd "Reiniciar apache2" systemctl restart apache2

if ! service_active "apache2"; then
  msg_fatal "Apache não iniciou corretamente. Verifique: journalctl -u apache2 e ${LOG_FILE}"
fi

# -------------------------
# Resumo final
# -------------------------
echo ""
echo -e "${BOLD}${GREEN}  Apache instalado com sucesso!${RESET}"
echo ""
echo -e "  ${BOLD}Status:${RESET}"
systemctl --no-pager status apache2 | grep -E "Active:|Loaded:" | sed 's/^/    /'
echo ""
echo -e "  ${BOLD}Módulos proxy/fcgi ativos:${RESET}"
apachectl -M 2>/dev/null | grep -E "proxy|fcgi" | sed 's/^/    /' \
  || msg_warn "Nenhum módulo proxy/fcgi encontrado na listagem."
echo ""
echo -e "  ${BOLD}Log:${RESET} ${LOG_FILE}"
echo ""
msg_ok "Apache pronto para uso com PHP-FPM e Moodle."
echo ""
