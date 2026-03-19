#!/bin/bash
# =============================================================================
# install-mariadb.sh — Instalação do MariaDB 10.11 para ambiente local
#
# Instala e configura o MariaDB 10.11 a partir do repositório oficial,
# compatível com Ubuntu, Linux Mint e Zorin OS. Cria automaticamente um
# usuário 'admin' com privilégios totais para uso em desenvolvimento local.
#
# Idempotência:
#   · Detecta MariaDB já instalado na versão correta e pula a instalação
#   · Verifica se o usuário 'admin' já existe antes de criá-lo
#   · Não sobrescreve a configuração utf8mb4 se já estiver presente
#
# ⚠  Voltado para ambiente LOCAL de desenvolvimento. Não use em produção.
#
# Uso: sudo bash install-mariadb.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

MARIADB_VERSION="10.11"
MOODLE_CNF="/etc/mysql/mariadb.conf.d/60-moodle.cnf"

check_root
_init_log "install-mariadb"
enable_trap

echo ""
echo -e "${BOLD}MariaDB ${MARIADB_VERSION} — Instalação (Ambiente Local)${RESET}"
echo ""

# -------------------------
# Gerador de senha segura
# -------------------------
generate_password() {
  < /dev/urandom tr -dc 'A-Za-z0-9_@#' | dd bs=16 count=1 2>/dev/null
}

# -------------------------
# Detectar sistema e codename Ubuntu
# -------------------------
msg_section "Detectando sistema..."

if [ -f /etc/linuxmint/info ]; then
  SYSTEM_NAME="Linux Mint"
  UBUNTU_CODENAME=$(grep -oP 'UBUNTU_CODENAME=\K.*' /etc/os-release)
elif grep -qi zorin /etc/os-release; then
  SYSTEM_NAME="Zorin OS"
  UBUNTU_CODENAME=$(grep -oP 'UBUNTU_CODENAME=\K.*' /etc/os-release)
else
  SYSTEM_NAME="Ubuntu"
  UBUNTU_CODENAME=$(lsb_release -cs)
fi

msg_info "Sistema detectado : $SYSTEM_NAME"
msg_info "Base Ubuntu       : $UBUNTU_CODENAME"

# -------------------------
# Idempotência: MariaDB já instalado?
# -------------------------
msg_section "Verificando instalação existente..."

MARIADB_ALREADY_INSTALLED=false
if pkg_installed "mariadb-server"; then
  INSTALLED_VERSION=$(mariadb --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1 || echo "desconhecida")
  if [[ "$INSTALLED_VERSION" == "$MARIADB_VERSION" ]]; then
    msg_ok "MariaDB ${MARIADB_VERSION} já instalado. Pulando instalação de pacotes."
    MARIADB_ALREADY_INSTALLED=true
  else
    msg_warn "MariaDB instalado mas na versão $INSTALLED_VERSION (esperado: $MARIADB_VERSION). Continuando..."
  fi
else
  msg_info "MariaDB não encontrado. Prosseguindo com a instalação."
fi

# -------------------------
# Senha do usuário admin
# -------------------------
msg_section "Configuração de credenciais"
echo ""
echo -e "  ${BOLD}Senha do usuário 'admin' do MariaDB${RESET}"
echo -e "  ${CYAN}Deixe em branco para gerar automaticamente${RESET}"
echo -n "  Senha: "
read -rs ADMIN_PASSWORD
echo ""

if [ -z "$ADMIN_PASSWORD" ]; then
  ADMIN_PASSWORD=$(generate_password)
  msg_info "Senha gerada automaticamente."
else
  msg_ok "Senha definida manualmente."
fi

# Salvar credenciais em arquivo protegido para não perder após fechar o terminal
CREDS_FILE="/root/.lamp-mariadb-credentials"
cat > "$CREDS_FILE" <<EOF
# Credenciais MariaDB — ambiente local de desenvolvimento
# Gerado em $(date '+%Y-%m-%d %H:%M:%S')
MARIADB_USER=admin
MARIADB_HOST=localhost
MARIADB_PASSWORD=${ADMIN_PASSWORD}
EOF
chmod 600 "$CREDS_FILE"
msg_ok "Credenciais salvas em $CREDS_FILE (chmod 600)."

# -------------------------
# Instalação de pacotes (se necessário)
# -------------------------
if [[ "$MARIADB_ALREADY_INSTALLED" == false ]]; then
  MARIADB_REPO_URL="https://downloads.mariadb.com/MariaDB/mariadb-$MARIADB_VERSION/repo/ubuntu/dists/$UBUNTU_CODENAME"

  msg_section "Instalando dependências básicas..."
  log_cmd "Atualizar índice apt" apt update -y
  log_cmd "Instalar dependências" apt install -y apt-transport-https curl ca-certificates software-properties-common

  msg_section "Verificando repositório MariaDB ${MARIADB_VERSION}..."
  if curl -fsI "$MARIADB_REPO_URL/" >/dev/null 2>&1; then
    msg_ok "Repositório oficial encontrado para '$UBUNTU_CODENAME'."

    mkdir -p /etc/apt/keyrings
    log_cmd "Baixar chave GPG do MariaDB" \
      curl -fsSL https://mariadb.org/mariadb_release_signing_key.pgp \
        -o /etc/apt/keyrings/mariadb-keyring.pgp

    echo "deb [signed-by=/etc/apt/keyrings/mariadb-keyring.pgp arch=amd64,arm64,ppc64el] \
https://downloads.mariadb.com/MariaDB/mariadb-$MARIADB_VERSION/repo/ubuntu \
$UBUNTU_CODENAME main" \
    > /etc/apt/sources.list.d/mariadb.list

    msg_ok "Repositório configurado em /etc/apt/sources.list.d/mariadb.list"
  else
    msg_fatal "Repositório MariaDB ${MARIADB_VERSION} não encontrado para '${UBUNTU_CODENAME}'. Abortando."
  fi

  msg_section "Instalando MariaDB ${MARIADB_VERSION}..."
  log_cmd "apt update" apt update -y
  log_cmd "Instalar mariadb-server e mariadb-client" \
    apt install -y \
      "mariadb-server=1:${MARIADB_VERSION}*" \
      "mariadb-client=1:${MARIADB_VERSION}*"
fi

# -------------------------
# Idempotência: configuração utf8mb4
# -------------------------
msg_section "Verificando configuração Moodle (utf8mb4)..."

if [ -f "$MOODLE_CNF" ]; then
  msg_ok "Configuração $MOODLE_CNF já existe. Pulando."
else
  cat > "$MOODLE_CNF" <<'EOF'
[mysqld]
character-set-server = utf8mb4
collation-server     = utf8mb4_unicode_ci
innodb_file_per_table = 1
innodb_large_prefix   = ON
EOF
  msg_ok "Configuração utf8mb4 criada em $MOODLE_CNF"
fi

# -------------------------
# Iniciar / reiniciar serviço
# -------------------------
msg_section "Iniciando MariaDB..."
log_cmd "Habilitar serviço mariadb" systemctl enable mariadb
log_cmd "Reiniciar serviço mariadb" systemctl restart mariadb

# -------------------------
# Idempotência: usuário admin
# -------------------------
msg_section "Verificando usuário 'admin'..."

ADMIN_EXISTS=$(echo "SELECT COUNT(*) FROM mysql.user WHERE User='admin' AND Host='localhost';" \
  | mariadb -N 2>/dev/null || true)
# Garante valor numérico mesmo se mariadb retornar vazio ou falhar
ADMIN_EXISTS="${ADMIN_EXISTS//[^0-9]/}"
ADMIN_EXISTS="${ADMIN_EXISTS:-0}"

if [[ "$ADMIN_EXISTS" -ge 1 ]]; then
  msg_warn "Usuário 'admin'@'localhost' já existe."
  echo ""
  echo -e "  ${YELLOW}Deseja redefinir a senha do usuário 'admin'? (s/N):${RESET} "
  read -rp "  " REDEFINE
  if [[ "$REDEFINE" =~ ^(s|S)$ ]]; then
    echo "ALTER USER 'admin'@'localhost' IDENTIFIED BY '${ADMIN_PASSWORD}'; FLUSH PRIVILEGES;" \
      | mariadb
    msg_ok "Senha do usuário 'admin' redefinida."
  else
    msg_info "Senha mantida. A senha exibida no resumo pode não ser a atual."
  fi
else
  msg_info "Criando usuário 'admin'@'localhost'..."
  cat <<EOF | mariadb
CREATE USER 'admin'@'localhost' IDENTIFIED BY '${ADMIN_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
  msg_ok "Usuário 'admin' criado com sucesso."
fi

# -------------------------
# Teste de acesso
# -------------------------
msg_section "Testando acesso com usuário 'admin'..."
if echo "SHOW DATABASES;" | mariadb -u admin -p"${ADMIN_PASSWORD}" >/dev/null 2>&1; then
  msg_ok "Login com usuário 'admin' validado com sucesso."
else
  msg_error "Falha no teste de login. Verifique a senha e o estado do serviço."
  msg_info  "Log completo: ${LOG_FILE}"
  exit 1
fi

# -------------------------
# Resumo final
# -------------------------
echo ""
echo -e "${BOLD}${GREEN}  MariaDB instalado com sucesso!${RESET}"
echo ""
echo -e "  ${BOLD}Versão   :${RESET} $(mariadb --version | awk '{print $1, $2, $3}')"
echo -e "  ${BOLD}Usuário  :${RESET} admin"
echo -e "  ${BOLD}Host     :${RESET} localhost"
echo -e "  ${BOLD}Senha    :${RESET} ${YELLOW}${ADMIN_PASSWORD}${RESET}"
echo -e "  ${BOLD}Creds    :${RESET} ${CREDS_FILE} (chmod 600)"
echo -e "  ${BOLD}Log      :${RESET} ${LOG_FILE}"
echo ""
msg_warn "Este é um ambiente LOCAL — não use em produção."
echo ""
