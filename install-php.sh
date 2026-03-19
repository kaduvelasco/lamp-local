#!/bin/bash
# =============================================================================
# install-php.sh — Instalação de uma versão específica do PHP (FPM) para Moodle
#
# Instala o PHP na versão indicada via argumento, configurado para rodar como
# PHP-FPM via socket Unix. Aplica o 99-custom.ini em FPM e CLI.
#
# Idempotência:
#   · Pula instalação de pacotes se php$V-fpm já estiver instalado
#   · Pula configuração do pool se o socket já estiver correto
#   · Pula cópia do .ini se o destino for idêntico ao source
#   · Pula restart do serviço se já estiver ativo e configurado
#
# O arquivo 99-custom.ini deve estar em: <dir do script>/php-ini/99-custom.ini
#
# Uso: sudo bash install-php.sh <versão>
#      sudo bash install-php.sh 8.2
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

check_root

# -------------------------
# Argumento obrigatório
# -------------------------
if [ -z "${1:-}" ]; then
  msg_error "Versão do PHP não informada."
  echo -e "  Uso: $0 <versão>   (ex: $0 8.2)"
  exit 1
fi

V="$1"
SOURCE_INI="$SCRIPT_DIR/php-ini/99-custom.ini"
POOL="/etc/php/$V/fpm/pool.d/www.conf"
FPM_INI="/etc/php/$V/fpm/conf.d/99-custom.ini"
CLI_INI="/etc/php/$V/cli/conf.d/99-custom.ini"
EXPECTED_LISTEN="/run/php/php$V-fpm.sock"

# Validar versão contra lista de versões suportadas
SUPPORTED_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")
VERSION_VALID=false
for supported in "${SUPPORTED_VERSIONS[@]}"; do
  [[ "$V" == "$supported" ]] && VERSION_VALID=true && break
done

if [[ "$VERSION_VALID" == false ]]; then
  msg_error "Versão PHP '$V' não é suportada."
  echo -e "  Versões suportadas: ${SUPPORTED_VERSIONS[*]}"
  exit 1
fi

_init_log "install-php-$V"
enable_trap

echo ""
echo -e "${BOLD}PHP ${V} (FPM) — Instalação Moodle-ready${RESET}"
echo ""

# -------------------------
# Extensões a validar (Moodle)
# -------------------------
MOODLE_EXTENSIONS=(
  sodium exif bcmath intl gd curl xml zip mbstring soap imap tidy
)

# -------------------------
# Pacotes apt
# -------------------------
PHP_PACKAGES=(
  php$V-fpm php$V-cli php$V-common php$V-opcache php$V-readline
  php$V-zip php$V-gd php$V-mysql php$V-mbstring php$V-xml php$V-xsl
  php$V-curl php$V-tidy php$V-soap php$V-sqlite3 php$V-intl
  php$V-imap php$V-bz2 php$V-bcmath
)

# -------------------------
# Idempotência: pacotes
# -------------------------
msg_section "Verificando instalação existente de PHP ${V}..."

if pkg_installed "php$V-fpm"; then
  msg_ok "php$V-fpm já instalado. Pulando instalação de pacotes."
else
  msg_info "php$V-fpm não encontrado. Instalando..."
  log_cmd "apt update" apt update -y
  log_cmd "Instalar PHP $V e extensões" apt install -y "${PHP_PACKAGES[@]}"
fi

# -------------------------
# Idempotência: pool FPM
# -------------------------
msg_section "Verificando configuração do pool PHP-FPM ${V}..."

if [ ! -f "$POOL" ]; then
  msg_fatal "Arquivo de pool não encontrado: $POOL — verifique se o php$V-fpm foi instalado."
fi

CURRENT_LISTEN=$(grep "^listen = " "$POOL" 2>/dev/null | awk '{print $3}' || echo "")
POOL_CHANGED=false

if [[ "$CURRENT_LISTEN" == "$EXPECTED_LISTEN" ]]; then
  msg_ok "Pool já configurado com socket correto: $EXPECTED_LISTEN"
else
  msg_info "Configurando pool para socket: $EXPECTED_LISTEN"
  sed -i \
    -e "s|^listen = .*|listen = $EXPECTED_LISTEN|" \
    -e 's|^;listen.owner = .*|listen.owner = www-data|' \
    -e 's|^;listen.group = .*|listen.group = www-data|' \
    -e 's|^;listen.mode = .*|listen.mode = 0660|' \
    "$POOL"
  msg_ok "Pool configurado: $EXPECTED_LISTEN"
  POOL_CHANGED=true
fi

# -------------------------
# Idempotência: 99-custom.ini
# -------------------------
msg_section "Verificando 99-custom.ini..."

if [ ! -f "$SOURCE_INI" ]; then
  msg_fatal "Arquivo source não encontrado: $SOURCE_INI — crie-o antes de continuar."
fi

_copy_ini_if_changed() {
  local dest="$1"
  local dest_dir
  dest_dir="$(dirname "$dest")"
  mkdir -p "$dest_dir"

  if [ -f "$dest" ] && diff -q "$SOURCE_INI" "$dest" >/dev/null 2>&1; then
    msg_ok "$(basename "$dest") em $dest_dir já está atualizado. Pulando."
  else
    cp "$SOURCE_INI" "$dest"
    msg_ok "$(basename "$dest") copiado para $dest_dir"
    INI_CHANGED=true
  fi
}

INI_CHANGED=false
_copy_ini_if_changed "$FPM_INI"
_copy_ini_if_changed "$CLI_INI"

# -------------------------
# Serviço FPM
# -------------------------
msg_section "Gerenciando serviço php${V}-fpm..."

log_cmd "Habilitar php$V-fpm" systemctl enable "php$V-fpm"

if service_active "php$V-fpm"; then
  if [[ "$POOL_CHANGED" == true || "$INI_CHANGED" == true ]]; then
    log_cmd "Recarregar php$V-fpm (configuração alterada)" systemctl reload "php$V-fpm"
    msg_ok "php$V-fpm recarregado."
  else
    msg_ok "php$V-fpm já ativo e sem mudanças — reload desnecessário."
  fi
else
  log_cmd "Iniciar php$V-fpm" systemctl start "php$V-fpm"
  msg_ok "php$V-fpm iniciado."
fi

if ! service_active "php$V-fpm"; then
  msg_fatal "php$V-fpm não iniciou corretamente. Verifique: journalctl -u php$V-fpm e ${LOG_FILE}"
fi

# -------------------------
# Validar extensões do Moodle
# -------------------------
msg_section "Verificando extensões obrigatórias do Moodle..."

FAILED=0
for ext in "${MOODLE_EXTENSIONS[@]}"; do
  if php$V -m 2>/dev/null | grep -qi "^$ext$"; then
    msg_ok "$ext"
  elif [[ "$ext" == "sodium" ]] && php$V -r "sodium_memzero(\$x='');" 2>/dev/null; then
    msg_ok "$ext (built-in)"
  else
    msg_warn "Extensão não encontrada: $ext"
    FAILED=1
  fi
done

if [ "$FAILED" -eq 1 ]; then
  msg_fatal "Uma ou mais extensões obrigatórias estão ausentes. Verifique o log: ${LOG_FILE}"
fi

# -------------------------
# Resumo final
# -------------------------
echo ""
echo -e "${BOLD}${GREEN}  PHP ${V} instalado e pronto para Moodle!${RESET}"
echo ""
echo -e "  ${BOLD}Versão    :${RESET} $(php$V -v | head -n 1)"
echo -e "  ${BOLD}Socket    :${RESET} $EXPECTED_LISTEN"
echo -e "  ${BOLD}INI (FPM) :${RESET} $FPM_INI"
echo -e "  ${BOLD}INI (CLI) :${RESET} $CLI_INI"
echo -e "  ${BOLD}Log       :${RESET} ${LOG_FILE}"
echo ""
