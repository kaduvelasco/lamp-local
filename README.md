# lamp-local

Scripts para montar e gerenciar um ambiente LAMP local para desenvolvimento com Moodle — Ubuntu, Linux Mint e Zorin OS.

> ⚠️ **Projeto pessoal, em desenvolvimento lento.**
> Boa parte do esforço que iria para cá está sendo redirecionado para o [Lumina Stack](https://github.com/kaduvelasco/lumina-stack), um projeto mais completo para o mesmo propósito. Este repositório continua ativo para o meu uso pessoal, mas sem roadmap ou garantias de atualização frequente.

---

## Estrutura

```
.
├── install.sh               # Menu principal de instalação
├── my-local.sh              # Gerenciador do ambiente (uso diário)
├── lib.sh                   # Funções compartilhadas (log, erros, utilitários)
├── install-mariadb.sh       # Instala MariaDB 10.11
├── install-apache.sh        # Instala Apache (modo PHP-FPM)
├── install-php-prereqs.sh   # Adiciona PPA Ondřej PHP
├── install-php.sh           # Instala uma versão do PHP-FPM
├── fix-virtualserver.sh     # Corrige configuração Apache para Moodle
├── uninstall-all.sh         # Remove tudo (Apache + PHP + MariaDB)
└── php-ini/
    └── 99-custom.ini        # Configurações PHP para desenvolvimento
```

---

## Instalação do ambiente

Execute como root:

```bash
sudo bash install.sh
```

O menu oferece as seguintes opções:

| Opção | Descrição |
|-------|-----------|
| 1 | Instalar MariaDB 10.11 |
| 2 | Instalar Apache (PHP-FPM ready) |
| 3 | Instalar pré-requisitos do PHP (PPA Ondřej) |
| 4–8 | Instalar PHP 7.4, 8.0, 8.1, 8.2 ou 8.3 |
| 9 | Instalar o comando `my-local` no sistema |
| 0 | Sair |

A ordem recomendada é: **MariaDB → Apache → Pré-requisitos → PHP**.

Logs de instalação são gravados em `/var/log/lamp-install/`.

---

## Gerenciador diário (my-local)

O `my-local.sh` é um arquivo autossuficiente — não depende de nenhum outro arquivo do projeto após instalado.

### Instalar como comando do sistema

Via menu do `install.sh` (opção 9), ou diretamente:

```bash
sudo bash my-local.sh --install
```

Isso copia o script para `/usr/local/bin/my-local`. Após isso, basta:

```bash
sudo my-local
```

### Remover o comando

```bash
sudo my-local.sh --uninstall
```

### Funcionalidades

**PHP — Alternar versão ativa**

Lista todas as versões PHP-FPM instaladas e alterna o ambiente completo para a versão escolhida: para todos os FPMs, inicia o escolhido, atualiza o socket via `update-alternatives`, redefine o PHP CLI e reconfigura o Apache.

**Banco de dados — MariaDB**

- Backup geral (`mysqldump --all-databases`)
- Restore a partir de arquivo `.sql`
- Remoção interativa de bancos (com confirmação individual)
- Verificação e otimização de tabelas (`mysqlcheck --optimize`)
- Otimização do MariaDB para Moodle — detecta a RAM disponível e ajusta `innodb_buffer_pool_size` automaticamente

**Permissões — /var/www**

- Corrige ownership (`$SUDO_USER:www-data`) e ACLs em `/var/www/html`, `/var/www/data` e `/var/www/databases`
- Aplica `setfacl` com permissões padrão e herança para novos arquivos
- Ajusta o limite de `inotify` para uso com MegaSync

---

## Desinstalar o ambiente

```bash
sudo bash uninstall-all.sh
```

Remove Apache, todas as versões de PHP, MariaDB, PPAs Ondřej e opcionalmente `/var/www`. Requer confirmação explícita digitando `RESET`.

---

## Requisitos

- Ubuntu 22.04 / 24.04, Linux Mint ou Zorin OS (base Ubuntu)
- Bash 5+
- Acesso root (`sudo`)
