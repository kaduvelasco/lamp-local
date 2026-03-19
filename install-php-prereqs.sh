#!/bin/bash
# =============================================================================
# install-php-prereqs.sh — Pré-requisitos para instalação de múltiplas versões PHP
#
# Prepara o sistema para instalar qualquer versão do PHP (7.4 a 8.3) via
# repositório PPA Ondřej Surý.
#
# Idempotência:
#   · Não adiciona o PPA se já estiver configurado
#   · Não reinstala pacotes já presentes
#
# Execute este script ANTES de install-php.sh e APÓS install-apache.sh.
#
# Uso: sudo bash install-php-prereqs.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

check_root
_init_log "install-php-prereqs"
enable_trap

echo ""
echo -e "${BOLD}PHP — Pré-requisitos (Ambiente Local)${RESET}"
echo ""

# -------------------------
# Dependências de sistema
# -------------------------
msg_section "Instalando dependências básicas..."
log_cmd "apt update" apt update -y
log_cmd "Instalar pacotes base" apt install -y \
  software-properties-common \
  apt-transport-https \
  ca-certificates \
  lsb-release \
  curl \
  wget \
  gnupg2
msg_ok "Dependências instaladas."

# -------------------------
# Idempotência: PPA Ondřej PHP
# -------------------------
msg_section "Configurando repositório Ondřej PHP..."

if grep -Rq "^deb .*ondrej/php" /etc/apt/sources.list.d/ 2>/dev/null; then
  msg_ok "PPA ppa:ondrej/php já está configurado. Pulando."
else
  log_cmd "Adicionar ppa:ondrej/php" add-apt-repository -y ppa:ondrej/php
  msg_ok "PPA adicionado com sucesso."
fi

# -------------------------
# Atualizar pacotes
# -------------------------
msg_section "Atualizando lista de pacotes..."
log_cmd "apt update" apt update -y
msg_ok "Índice atualizado."

# -------------------------
# Verificações de ambiente
# -------------------------
msg_section "Verificando ambiente..."

if ! cmd_exists apache2; then
  msg_warn "Apache não detectado. Execute install-apache.sh antes de instalar o PHP."
else
  msg_ok "Apache detectado."
fi

if ! pkg_installed mariadb-server; then
  msg_warn "MariaDB não detectado. Execute install-mariadb.sh antes de configurar o Moodle."
else
  msg_ok "MariaDB detectado."
fi

# -------------------------
# Resumo
# -------------------------
echo ""
echo -e "${BOLD}${GREEN}  Pré-requisitos do PHP instalados!${RESET}"
echo ""
msg_info "Próximo passo: execute install-php.sh com a versão desejada."
msg_info "Versões disponíveis: 7.4, 8.0, 8.1, 8.2, 8.3"
echo -e "  ${BOLD}Log:${RESET} ${LOG_FILE}"
echo ""
