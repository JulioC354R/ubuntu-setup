#!/usr/bin/env bash
# install.sh — bootstrap em uma linha do ubuntu-setup.
#
#   curl -fsSL https://raw.githubusercontent.com/JulioC354R/ubuntu-setup/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --theme nord
#   ./install.sh [--theme NOME] [--list-themes] [--help]
#
# Tudo fica dentro de main(): o bash só executa depois de baixar o arquivo inteiro.

set -uo pipefail

main() {
  local repo_url="${SETUP_REPO_URL:-https://github.com/JulioC354R/ubuntu-setup.git}"
  local setup_dir="${SETUP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ubuntu-setup}"
  local theme="${SETUP_THEME:-catppuccin}" self_dir=""

  while (( $# )); do
    case "$1" in
      --theme) theme=${2:?informe o tema}; shift 2 ;;
      --theme=*) theme=${1#*=}; shift ;;
      --list-themes) LIST_THEMES=1; shift ;;
      --dry-run) export UI_DRY_RUN=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) echo "Opção desconhecida: $1" >&2; usage; return 2 ;;
    esac
  done

  # Executado de dentro de um checkout? Usa ele. Senão (curl | bash), clona/atualiza.
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
  if [[ -n "$self_dir" && -f "$self_dir/lib/ui.sh" ]]; then
    setup_dir="$self_dir"
  else
    bootstrap_repo "$repo_url" "$setup_dir" || return 1
  fi
  SETUP_ROOT="$setup_dir"   # global: usado pelos módulos para achar arquivos do repo (config/, assets/)

  # shellcheck source=lib/ui.sh
  source "$setup_dir/lib/ui.sh"
  # shellcheck source=lib/helpers.sh
  source "$setup_dir/lib/helpers.sh"

  if [[ -n "${LIST_THEMES:-}" ]]; then
    exec bash "$setup_dir/scripts/preview-themes.sh"
  fi

  ui_init "$theme"
  check_os
  load_local_env

  local m
  for m in "$setup_dir"/modules/*.sh; do
    # shellcheck source=/dev/null
    [[ -f "$m" ]] && source "$m"
  done

  ui_header
  (( UI_DRY_RUN )) || ensure_sudo || return 1
  ui_run_plan
  ui_summary
}

usage() {
  cat <<'EOF'
Uso: install.sh [opções]

  --theme NOME     tema visual (catppuccin, dracula, nord, tokyonight, gruvbox, mono)
  --list-themes    mostra uma prévia de todos os temas
  --dry-run        só verifica: mostra o que já está ok e o que seria instalado
  -h, --help       esta ajuda

Variáveis: SETUP_THEME, SETUP_UI (panel | classic), SETUP_REPO_URL, SETUP_DIR, SETUP_LOG_DIR,
           NO_COLOR, SETUP_PLAIN
EOF
}

bootstrap_repo() {  # url dir
  local url=$1 dir=$2
  echo "› Preparando ubuntu-setup em ${dir/#$HOME/\~}"
  if ! command -v git >/dev/null 2>&1; then
    echo "› Instalando git..."
    local sudo=""; [[ $EUID -ne 0 ]] && sudo="sudo"
    $sudo apt-get update -q </dev/null >/dev/null &&
      $sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -q git </dev/null >/dev/null ||
      { echo "✘ Não foi possível instalar o git." >&2; return 1; }
  fi
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" pull --ff-only -q </dev/null || echo "! Não foi possível atualizar; usando versão local." >&2
    return 0
  fi
  # Clona ao lado e só depois troca: se a pasta já existir sem ser um clone, ela vira backup (nada é apagado)
  local tmp bak
  mkdir -p "$(dirname "$dir")"
  tmp=$(mktemp -d "$dir.clone-XXXXXX") || return 1
  if ! GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 "$url" "$tmp" </dev/null; then
    rmdir "$tmp" 2>/dev/null || rm -rf -- "${tmp:?}"
    echo "✘ Falha ao clonar $url" >&2
    return 1
  fi
  if [[ -e "$dir" ]]; then
    bak="$dir.bak-$(date +%Y%m%d-%H%M%S)"
    mv -- "$dir" "$bak" && echo "› Pasta existente guardada em ${bak/#$HOME/\~}"
  fi
  mv -- "$tmp" "$dir"
}

check_os() {
  local id="" version=""
  if [[ -r /etc/os-release ]]; then
    id=$(. /etc/os-release && echo "${ID:-}")
    version=$(. /etc/os-release && echo "${VERSION_ID:-}")
  fi
  if [[ "$id" != ubuntu ]]; then
    ui_warn "Sistema não é Ubuntu (${id:-desconhecido}). Continuando, mas algo pode falhar."
  elif [[ "$version" != 24.04 && "$version" != 26.04 ]]; then
    ui_warn "Ubuntu $version não é uma LTS testada (24.04, 26.04)."
  fi
}

main "$@"
