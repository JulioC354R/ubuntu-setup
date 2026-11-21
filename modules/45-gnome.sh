#!/usr/bin/env bash
# modules/45-gnome.sh — extensões do GNOME (extensions.gnome.org) e suas configurações.
# Configs: config/gnome/*.ini. Exportar de novo da máquina atual: scripts/export-gnome.sh

# uuid|nome exibido
GNOME_EXTENSIONS=(
  "blur-my-shell@aunetx|Blur my Shell"
  "Vitals@CoreCoding.com|Vitals"
  "caffeine@patapon.info|Caffeine"
  "lilypad@shendrew.github.io|Lilypad"
  "Bluetooth-Battery-Meter@maniacx.github.com|Bluetooth Battery Meter"
  "openbar@neuromorph|Open Bar"
)

# Extensões sem versão para o GNOME atual (ex.: Open Bar no GNOME 50) só carregam com a
# checagem de versão desligada. Risco: uma extensão incompatível pode travar o painel.
GNOME_DISABLE_VERSION_VALIDATION="${SETUP_GNOME_DISABLE_VERSION_VALIDATION:-true}"

GNOME_EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"

# Ferramentas para ajustar o GNOME à mão (apt do Ubuntu)
GNOME_TOOLS=(gnome-tweaks gnome-shell-extension-manager dconf-editor)

gnome_shell_major() { gnome-shell --version | grep -oE '[0-9]+' | head -n1; }

check_gnome_ext() { [[ -f "$GNOME_EXT_DIR/$1/metadata.json" ]]; }

step_gnome_ext() {  # uuid
  local uuid=$1 major info path tmp
  has_cmd gnome-shell || { echo "GNOME Shell não encontrado." >&2; return 1; }
  major=$(gnome_shell_major)
  info=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$major")

  if ! jq -e --arg v "$major" '.shell_version_map | has($v)' <<<"$info" >/dev/null; then
    if [[ "$GNOME_DISABLE_VERSION_VALIDATION" != true ]]; then
      echo "$uuid não tem versão para o GNOME $major (suporta: $(jq -r '.shell_version_map|keys|join(", ")' <<<"$info"))." >&2
      return 1
    fi
    echo "AVISO: $uuid não declara suporte ao GNOME $major; instalando a última versão disponível." >&2
  fi
  path=$(jq -r '.download_url // empty' <<<"$info")
  [[ -n "$path" ]] || { echo "extensions.gnome.org não retornou download para $uuid." >&2; return 1; }

  tmp=$(mktemp -d)
  download "https://extensions.gnome.org$path" "$tmp/ext.zip"
  mkdir -p "$GNOME_EXT_DIR/$uuid"
  unzip -q -o "$tmp/ext.zip" -d "$GNOME_EXT_DIR/$uuid"
  if compgen -G "$GNOME_EXT_DIR/$uuid/schemas/*.gschema.xml" >/dev/null; then
    glib-compile-schemas "$GNOME_EXT_DIR/$uuid/schemas"
  fi
  rm -rf -- "$tmp"
}

check_version_validation() {
  [[ "$(gsettings get org.gnome.shell disable-extension-version-validation)" == "$GNOME_DISABLE_VERSION_VALIDATION" ]]
}
step_version_validation() {
  gsettings set org.gnome.shell disable-extension-version-validation "$GNOME_DISABLE_VERSION_VALIDATION"
}

plan_section "Extensões do GNOME"
plan_step --check "pkg_installed ${GNOME_TOOLS[*]}" "Ajustes, Gerenciador de Extensões e dconf-editor" \
  apt_install "${GNOME_TOOLS[@]}"
for __e in "${GNOME_EXTENSIONS[@]}"; do
  plan_step --check "check_gnome_ext ${__e%%|*}" "${__e#*|}" step_gnome_ext "${__e%%|*}"
done
unset __e
plan_step --check check_version_validation "Checagem de versão das extensões ($GNOME_DISABLE_VERSION_VALIDATION)" step_version_validation
plan_step --check "dconf_applied $SETUP_ROOT/config/gnome/extensions.ini" "Configurações das extensões" \
  dconf_apply "$SETUP_ROOT/config/gnome/extensions.ini"
plan_step --check "dconf_applied $SETUP_ROOT/config/gnome/shell.ini" "Habilitar extensões" \
  dconf_apply "$SETUP_ROOT/config/gnome/shell.ini"
