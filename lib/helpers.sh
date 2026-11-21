#!/usr/bin/env bash
# lib/helpers.sh — helpers idempotentes usados pelas etapas dos módulos.

[[ -n "${__HELPERS_LOADED:-}" ]] && return 0
__HELPERS_LOADED=1

export DEBIAN_FRONTEND=noninteractive

has_cmd() { command -v "$1" >/dev/null 2>&1; }

is_root() { [[ $EUID -eq 0 ]]; }

# Executa como root sem nunca pedir senha no meio de uma etapa (sudo validado em ensure_sudo).
as_root() {
  if is_root; then "$@"; else sudo -n "$@"; fi
}

# Pede a senha do sudo uma vez (via /dev/tty, funciona no `curl | bash`) e a mantém viva.
ensure_sudo() {
  is_root && return 0
  has_cmd sudo || { ui_error "sudo não encontrado. Rode como root."; return 1; }
  if ! sudo -n true 2>/dev/null; then
    ui_info "Precisamos de permissão de administrador para instalar pacotes."
    sudo -v </dev/tty || { ui_error "Não foi possível obter sudo."; return 1; }
  fi
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
  UI_CLEANUP_PIDS+=($!)
}

# ── apt ──────────────────────────────────────────────────────────────────────

APT_OPTS=(-y -q -o DPkg::Lock::Timeout=120 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

pkg_installed() {  # pkg... -> 0 se todos estão instalados
  local p
  for p in "$@"; do
    # sem pipe com grep -q: com pipefail, o SIGPIPE no dpkg-query daria falso negativo
    [[ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" == "install ok installed" ]] || return 1
  done
}

apt_install() {  # instala apenas os pacotes que faltam
  local p missing=()
  for p in "$@"; do pkg_installed "$p" || missing+=("$p"); done
  (( ${#missing[@]} )) || return 0
  as_root apt-get install "${APT_OPTS[@]}" --no-install-recommends "${missing[@]}"
}

apt_install_latest() {  # instala ou atualiza para a versão candidata (ex.: após trocar de repositório)
  as_root apt-get install "${APT_OPTS[@]}" --no-install-recommends "$@"
}

apt_fresh() {  # [segundos] -> 0 se o índice do apt foi atualizado há menos que isso (padrão 6h)
  local max=${1:-21600} stamp=/var/lib/apt/periodic/update-success-stamp
  [[ -e "$stamp" ]] || stamp=/var/cache/apt/pkgcache.bin
  [[ -e "$stamp" ]] && (( $(date +%s) - $(stat -c %Y "$stamp") < max ))
}

apt_update() {
  as_root apt-get update -q -o DPkg::Lock::Timeout=120
  as_root touch /var/lib/apt/periodic/update-success-stamp 2>/dev/null || true
}

deb_arch() { dpkg --print-architecture; }

require_arch() {  # arch... -> falha com mensagem se a arquitetura atual não estiver na lista
  local a cur; cur=$(deb_arch)
  for a in "$@"; do [[ "$a" == "$cur" ]] && return 0; done
  echo "Arquitetura $cur não suportada (suportadas: $*)." >&2
  return 1
}

# Atualiza só o índice de um arquivo de repositório (bem mais rápido que apt-get update completo).
apt_update_source() {  # /etc/apt/sources.list.d/arquivo
  as_root apt-get update -q -o DPkg::Lock::Timeout=120 \
    -o Dir::Etc::sourcelist="$1" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
}

# Adiciona repositório apt no formato deb822. Reescreve só se mudou.
# Use os MESMOS caminhos de chave que o fornecedor documenta: Signed-By diferente para a
# mesma URL faz o apt recusar todos os repositórios ("Conflicting values set for option Signed-By").
apt_add_repo() {  # arquivo.sources keyring(.asc|.gpg) url_da_chave uris suites [componentes]
  local file="/etc/apt/sources.list.d/$1" keyring=$2 key_url=$3 tmp changed=0 body
  tmp=$(mktemp -d)
  download "$key_url" "$tmp/key"
  # .gpg = formato binário; converte só se a chave baixada vier em ASCII-armor
  if [[ "$keyring" == *.gpg ]] && grep -q -- '-----BEGIN PGP' "$tmp/key"; then
    gpg --dearmor <"$tmp/key" >"$tmp/keyring"
  else
    cp "$tmp/key" "$tmp/keyring"
  fi
  write_root_file "$keyring" "$(base64 -w0 "$tmp/keyring")" base64 && changed=1
  body="Types: deb
URIs: $4
Suites: $5"
  [[ -n "${6:-}" ]] && body+=$'\n'"Components: $6"
  body+=$'\n'"Architectures: $(deb_arch)"$'\n'"Signed-By: $keyring"
  write_root_file "$file" "$body" && changed=1
  rm -rf "$tmp"
  (( changed )) && apt_update_source "$file"
  return 0
}

# Baixa um .deb e instala com apt (resolve dependências).
install_deb_url() {  # url
  local tmp; tmp=$(mktemp -d)
  chmod 755 "$tmp"   # o apt baixa como usuário _apt; precisa ler o arquivo
  download "$1" "$tmp/pacote.deb"
  chmod 644 "$tmp/pacote.deb"
  as_root apt-get install "${APT_OPTS[@]}" "$tmp/pacote.deb"
  rm -rf "$tmp"
}

# ── rede ─────────────────────────────────────────────────────────────────────

download() {  # url destino
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$2" "$1"
}

github_latest_tag() {  # dono/repo -> tag da última release (ex.: v0.33.0)
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" | jq -r '.tag_name // empty'
}

verify_sha256() {  # arquivo arquivo_de_checksums [nome_no_checksums] -> falha se não bater
  local file=$1 sums=$2 name=${3:-$(basename "$1")} want
  want=$(awk -v n="$name" '{f=$2; sub(/^\*/, "", f)} f == n || $2 == "" {print $1; exit}' "$sums")
  [[ -n "$want" ]] || { echo "Checksum de $name não encontrado em $(basename "$sums")." >&2; return 1; }
  echo "$want  $file" | sha256sum -c - >/dev/null || { echo "Checksum não confere para $name." >&2; return 1; }
}

github_latest_asset() {  # dono/repo regex_do_nome -> URL do asset da última release
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" |
    jq -r --arg re "$2" '[.assets[] | select(.name | test($re))][0].browser_download_url // empty'
}

# ── arquivos ─────────────────────────────────────────────────────────────────

# Escreve arquivo de sistema (como root) só se o conteúdo for diferente. Retorna 0 se escreveu.
write_root_file() {  # destino conteúdo [base64]
  local dst=$1 tmp; tmp=$(mktemp)
  if [[ "${3:-}" == base64 ]]; then base64 -d <<<"$2" >"$tmp"; else printf '%s\n' "$2" >"$tmp"; fi
  if [[ -f "$dst" ]] && cmp -s "$tmp" "$dst"; then rm -f "$tmp"; return 1; fi
  as_root install -D -m 644 "$tmp" "$dst"
  rm -f "$tmp"
}

# Trechos de shell (PATH, nvm...) ficam em arquivos separados, carregados por UMA linha no .bashrc.
SETUP_SHELL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ubuntu-setup/shell.d"

shell_snippet() {  # nome conteúdo
  local file="$SETUP_SHELL_DIR/$1.sh"
  mkdir -p "$SETUP_SHELL_DIR"
  [[ -f "$file" ]] && [[ "$(cat "$file")" == "$2" ]] || printf '%s\n' "$2" >"$file"
  # shellcheck disable=SC2016  # a linha é literal, expandida pelo bash do usuário
  ensure_line 'for f in "${XDG_CONFIG_HOME:-$HOME/.config}"/ubuntu-setup/shell.d/*.sh; do [ -r "$f" ] && . "$f"; done; unset f  # ubuntu-setup' \
    "$HOME/.bashrc"
}

has_snippet() { [[ -f "$SETUP_SHELL_DIR/$1.sh" ]]; }

ensure_line() {  # linha arquivo -> adiciona a linha só se ainda não existir
  local line=$1 file=$2
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -qxF -- "$line" "$file" || printf '%s\n' "$line" >>"$file"
}

install_file() {  # origem destino -> copia; se destino existe e é diferente, faz backup antes
  local src=$1 dst=$2
  [[ -f "$src" ]] || { echo "origem não existe: $src" >&2; return 1; }
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" ]]; then
    cmp -s "$src" "$dst" && return 0
    cp -a "$dst" "$dst.bak-$(date +%Y%m%d-%H%M%S)"
  fi
  cp "$src" "$dst"
}

# Bloco marcado num arquivo que é seu (não do setup): o setup só mexe entre os marcadores
#   # >>> ubuntu-setup: <nome> >>>
#   ...
#   # <<< ubuntu-setup: <nome> <<<
# O resto do arquivo fica intocado. Backup se o arquivo mudar.
__block() { printf '# >>> ubuntu-setup: %s >>>\n%s\n# <<< ubuntu-setup: %s <<<' "$1" "$2" "$1"; }

has_block() {  # arquivo nome conteúdo -> 0 se o bloco existe com exatamente esse conteúdo
  [[ -f "$1" ]] || return 1
  local want got
  want=$(__block "$2" "$3")
  got=$(awk -v s="# >>> ubuntu-setup: $2 >>>" -v e="# <<< ubuntu-setup: $2 <<<" \
    '$0 == s {on = 1} on {print} on && $0 == e {exit}' "$1")
  [[ "$got" == "$want" ]]
}

ensure_block() {  # arquivo nome conteúdo
  local file=$1 tmp
  has_block "$@" && return 0
  mkdir -p "$(dirname "$file")"
  tmp=$(mktemp)
  if [[ -f "$file" ]] && grep -qxF "# >>> ubuntu-setup: $2 >>>" "$file"; then
    # substitui o bloco existente (conteúdo via ENVIRON: awk -v não aceita várias linhas)
    BLOCK=$(__block "$2" "$3") awk -v s="# >>> ubuntu-setup: $2 >>>" -v e="# <<< ubuntu-setup: $2 <<<" '
      $0 == s { print ENVIRON["BLOCK"]; skip = 1; next }
      skip && $0 == e { skip = 0; next }
      !skip { print }' "$file" >"$tmp"
  else
    { [[ -s "$file" ]] && { cat "$file"; echo; }; __block "$2" "$3"; echo; } >"$tmp"
  fi
  install_file "$tmp" "$file"
  rm -f "$tmp"
}

git_sync() {  # url dir -> clona ou atualiza (fast-forward)
  local url=$1 dir=$2
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" pull --ff-only -q
  else
    git clone -q --depth 1 "$url" "$dir"
  fi
}

# ── dconf (configurações do GNOME) ──────────────────────────────────────────
# Arquivos .ini no formato `dconf load /`: [caminho/da/seção] + chave=valor (valores GVariant).

dconf_apply() { dconf load / <"$1"; }   # mescla: não apaga chaves que não estão no arquivo

dconf_applied() {  # arquivo.ini -> 0 se todas as chaves já têm o valor do arquivo
  local line section="" key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" =~ ^\[(.+)\]$ ]]; then section=${BASH_REMATCH[1]}; continue; fi
    key=${line%%=*} value=${line#*=}
    [[ "$(dconf read "/$section/$key")" == "$value" ]] || return 1
  done <"$1"
}

# ── config local (dados pessoais ficam fora do repo) ────────────────────────

SETUP_LOCAL_ENV="${SETUP_LOCAL_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/ubuntu-setup/local.env}"

load_local_env() {
  # shellcheck source=/dev/null
  [[ -f "$SETUP_LOCAL_ENV" ]] && source "$SETUP_LOCAL_ENV"
  return 0
}

require_var() {  # NOME -> falha a etapa com mensagem clara se a variável não estiver definida
  [[ -n "${!1:-}" ]] && return 0
  echo "Variável $1 não definida. Configure em $SETUP_LOCAL_ENV (veja config/local.env.example)." >&2
  return 1
}
