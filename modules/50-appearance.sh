#!/usr/bin/env bash
# modules/50-appearance.sh — aparência: fastfetch, ícones Papirus e cursor Windows 11 Concept (jepriCreations).
# O cursor original (.cur/.ani do Windows) é convertido para Xcursor com win2xcur, instalado só
# durante a conversão e removido no fim. Créditos e licença: assets/cursors/CREDITS.md

# ── fastfetch: .deb oficial da última release (o apt do 24.04 não tem; o do 26.04 é antigo) ──
fastfetch_latest() { curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | jq -r .tag_name; }

check_fastfetch() {
  [[ "$(dpkg-query -W -f='${Version}' fastfetch 2>/dev/null)" == "$(fastfetch_latest)" ]]
}

step_fastfetch() {
  local arch tag
  case "$(deb_arch)" in amd64) arch=amd64 ;; arm64) arch=aarch64 ;; *) require_arch amd64 arm64 ;; esac
  tag=$(fastfetch_latest)
  install_deb_url "https://github.com/fastfetch-cli/fastfetch/releases/download/$tag/fastfetch-linux-$arch.deb"
}

# ── Cursor ───────────────────────────────────────────────────────────────────
CURSOR_ZIP="windows_11_cursors_concept_by_jepricreations_densjkc.zip"
CURSOR_THEME_PREFIX="W11-Cursors-jepriCreations"
CURSOR_VARIANT="${SETUP_CURSOR_VARIANT:-dark}"   # light (seta branca) | dark (seta preta)
ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
WIN2XCUR_VERSION="0.2.1"
WIN2XCUR=""   # definido durante a conversão; SETUP_WIN2XCUR usa um conversor externo (testes)

# Papel do cursor no Windows -> nomes Xcursor/CSS. O primeiro nome é o arquivo real; os outros, links.
CURSOR_MAP=(
  "arrow:default left_ptr arrow top_left_arrow context-menu copy alias dnd-copy dnd-link dnd-move dnd-ask X_cursor"
  "help:help question_arrow whats_this left_ptr_help"
  "appstarting:progress left_ptr_watch half-busy"
  "wait:wait watch"
  "crosshair:crosshair cross tcross cell"
  "ibeam:text xterm ibeam vertical-text"
  "nwpen:pencil draft"
  "no:not-allowed no-drop dnd-none forbidden crossed_circle circle"
  "sizens:ns-resize n-resize s-resize row-resize size_ver sb_v_double_arrow v_double_arrow double_arrow top_side bottom_side"
  "sizewe:ew-resize e-resize w-resize col-resize size_hor sb_h_double_arrow h_double_arrow left_side right_side"
  "sizenwse:nwse-resize nw-resize se-resize size_fdiag bd_double_arrow top_left_corner bottom_right_corner"
  "sizenesw:nesw-resize ne-resize sw-resize size_bdiag fd_double_arrow top_right_corner bottom_left_corner"
  "sizeall:move all-scroll fleur size_all"
  "uparrow:up-arrow center_ptr sb_up_arrow"
  "hand:pointer hand hand1 hand2 pointing_hand grab grabbing openhand closedhand"
)

cursor_zip_path() { printf '%s' "$SETUP_ROOT/assets/cursors/$CURSOR_ZIP"; }
cursor_zip_sha() { sha256sum "$(cursor_zip_path)" | cut -d' ' -f1; }

# ── Conversor temporário ────────────────────────────────────────────────────
# Instala python3-venv + imagemagick (traz a libMagickWand certa de cada Ubuntu) e o win2xcur num
# venv temporário. No fim, remove SÓ os pacotes que esta etapa adicionou (diff do dpkg antes/depois);
# o que já existia antes fica intocado.
__CURSOR_TMP="" __CURSOR_ADDED=()

installed_pkgs() { dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' | awk '$1 == "ii" {print $2}' | sort; }

__cursor_converter_up() {
  local before
  if [[ -n "${SETUP_WIN2XCUR:-}" ]]; then WIN2XCUR=$SETUP_WIN2XCUR; return 0; fi
  before=$(installed_pkgs)
  apt_install python3-venv imagemagick
  mapfile -t __CURSOR_ADDED < <(comm -13 <(printf '%s\n' "$before") <(installed_pkgs))
  python3 -m venv "$__CURSOR_TMP/venv"
  "$__CURSOR_TMP/venv/bin/pip" install -q --disable-pip-version-check "win2xcur==$WIN2XCUR_VERSION"
  WIN2XCUR="$__CURSOR_TMP/venv/bin/win2xcur"
}

__cursor_converter_down() {  # roda no EXIT da etapa: também limpa quando a conversão falha
  [[ -n "$__CURSOR_TMP" ]] && rm -rf -- "$__CURSOR_TMP"
  if (( ${#__CURSOR_ADDED[@]} )); then
    echo "Removendo conversor temporário: ${__CURSOR_ADDED[*]}"
    as_root apt-get purge "${APT_OPTS[@]}" "${__CURSOR_ADDED[@]}"
  fi
}

# ── Conversão: gera os dois temas (light e dark) ────────────────────────────
check_cursor_themes() {
  local v sha; sha=$(cursor_zip_sha) || return 1
  for v in light dark; do
    [[ "$(cat "$ICONS_DIR/$CURSOR_THEME_PREFIX-${v^}/.source-sha256" 2>/dev/null)" == "$sha" ]] || return 1
  done
}

build_cursor_theme() {  # pasta_com_cur_ani destino nome
  local src=$1 dest=$2 name=$3 work entry win names first n file
  work=$(mktemp -d)
  "$WIN2XCUR" -o "$work" "$src"/*.cur "$src"/*.ani >/dev/null

  mkdir -p "$dest.new/cursors"
  for entry in "${CURSOR_MAP[@]}"; do
    win=${entry%%:*}; read -r -a names <<<"${entry#*:}"; first=${names[0]}
    file=$(find "$work" -maxdepth 1 -iname "$win" -print -quit)
    [[ -n "$file" ]] || { echo "Cursor '$win' não encontrado no pacote." >&2; return 1; }
    cp "$file" "$dest.new/cursors/$first"
    for n in "${names[@]:1}"; do ln -sfn "$first" "$dest.new/cursors/$n"; done
  done
  cat >"$dest.new/index.theme" <<EOF
[Icon Theme]
Name=$name
Comment=Windows 11 Cursors Concept by jepriCreations — https://www.deviantart.com/jepricreations (convertido com win2xcur)
Inherits=Adwaita
EOF
  # Troca atômica: o tema antigo só sai depois que o novo está completo.
  [[ -d "$dest" ]] && mv "$dest" "$dest.old"
  mv "$dest.new" "$dest"
  [[ -d "$dest.old" ]] && rm -rf -- "$dest.old"
  rm -rf -- "$work"
}

step_cursor_themes() {  # roda em subshell próprio (ui.sh), então o trap EXIT vale só para esta etapa
  local v sha
  __CURSOR_TMP=$(mktemp -d)
  trap __cursor_converter_down EXIT
  sha=$(cursor_zip_sha)
  unzip -q "$(cursor_zip_path)" -d "$__CURSOR_TMP/zip"
  __cursor_converter_up
  for v in light dark; do
    [[ -d "$__CURSOR_TMP/zip/$v" ]] || { echo "Variante '$v' não encontrada no zip." >&2; return 1; }
    build_cursor_theme "$__CURSOR_TMP/zip/$v" "$ICONS_DIR/$CURSOR_THEME_PREFIX-${v^}" "$CURSOR_THEME_PREFIX-${v^}"
    printf '%s\n' "$sha" >"$ICONS_DIR/$CURSOR_THEME_PREFIX-${v^}/.source-sha256"
  done
}

# ── Aplicar no GNOME ─────────────────────────────────────────────────────────
cursor_theme_name() { printf '%s-%s' "$CURSOR_THEME_PREFIX" "${CURSOR_VARIANT^}"; }

check_cursor_applied() {
  [[ "$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null)" == "'$(cursor_theme_name)'" ]]
}

step_cursor_apply() {
  has_cmd gsettings || { echo "gsettings não encontrado (sem GNOME?)." >&2; return 1; }
  [[ -d "$ICONS_DIR/$(cursor_theme_name)" ]] || { echo "Tema $(cursor_theme_name) não instalado." >&2; return 1; }
  gsettings set org.gnome.desktop.interface cursor-theme "$(cursor_theme_name)"
}

# ── Ícones Papirus (PPA oficial do projeto) ─────────────────────────────────
# Usa add-apt-repository, como na documentação do Papirus: ele grava a chave dentro do .sources.
# Criar outro arquivo para o mesmo PPA com chave em outro caminho geraria conflito de Signed-By.
ICON_THEME="${SETUP_ICON_THEME:-Papirus-Dark}"   # Papirus | Papirus-Dark | Papirus-Light

papirus_sources() {
  printf '/etc/apt/sources.list.d/papirus-ubuntu-papirus-%s.sources' "$(. /etc/os-release && echo "$UBUNTU_CODENAME")"
}

check_papirus() { pkg_installed papirus-icon-theme && [[ -f "$(papirus_sources)" ]]; }

step_papirus() {
  apt_install software-properties-common
  as_root add-apt-repository -y -n ppa:papirus/papirus
  apt_update_source "$(papirus_sources)"
  apt_install_latest papirus-icon-theme
}

check_icon_theme() { [[ "$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null)" == "'$ICON_THEME'" ]]; }

step_icon_theme() {
  [[ -d "/usr/share/icons/$ICON_THEME" ]] || { echo "Tema de ícones $ICON_THEME não instalado." >&2; return 1; }
  gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"
}

plan_section "Aparência"
plan_step --check check_fastfetch "fastfetch" step_fastfetch
plan_step --check check_papirus "Ícones Papirus (PPA)" step_papirus
plan_step --check check_icon_theme "Aplicar ícones ($ICON_THEME)" step_icon_theme
plan_step --check check_cursor_themes "Cursor Windows 11 Concept (converte e remove o conversor)" step_cursor_themes
plan_step --check check_cursor_applied "Aplicar cursor ($CURSOR_VARIANT)" step_cursor_apply
