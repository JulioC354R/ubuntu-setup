#!/usr/bin/env bash
# scripts/export-gnome.sh — exporta as configurações atuais das extensões do GNOME para
# config/gnome/extensions.ini, removendo dados da máquina e estado interno.
# Depois de rodar: revise o diff (git diff config/gnome) antes de commitar.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/config/gnome/extensions.ini"

# Seções exportadas (dconf: /org/gnome/shell/extensions/<nome>/)
SECTIONS=(Bluetooth-Battery-Meter blur-my-shell caffeine dash-to-dock ding lilypad openbar tiling-assistant vitals)

# Chaves que nunca vão para o repo: seção/chave (regex ERE, aplicada ao caminho completo da chave)
EXCLUDE='^(Bluetooth-Battery-Meter/device-list|openbar/(bguri|dark-bguri|light-bguri|trigger-reload|import-export|pause-reload|reloadstyle|monitor-width|monitor-height)|tiling-assistant/(overridden-settings|last-version-installed)|blur-my-shell/settings-version|caffeine/user-enabled)$'

{
  cat <<'EOF'
# Configurações das extensões do GNOME (formato `dconf load /`).
# Fora daqui de propósito: dados da máquina e estado interno das extensões
#   Bluetooth-Battery-Meter/device-list (MAC e nome dos seus dispositivos)
#   openbar/*bguri (caminho do wallpaper), openbar/trigger-reload, openbar/import-export,
#   openbar/pause-reload, openbar/reloadstyle, openbar/monitor-* (estado e tamanho da tela)
#   tiling-assistant/overridden-settings, tiling-assistant/last-version-installed
#   blur-my-shell/settings-version, caffeine/user-enabled
# Para atualizar a partir da máquina atual: scripts/export-gnome.sh
EOF
  for s in "${SECTIONS[@]}"; do
    dconf dump "/org/gnome/shell/extensions/$s/" | awk -v base="$s" -v ex="$EXCLUDE" '
      /^\[.*\]$/ { s = substr($0, 2, length($0) - 2); path = (s == "/" ? base : base "/" s); pending = 1; next }
      /=/ {
        key = substr($0, 1, index($0, "=") - 1)
        if ((path "/" key) ~ ex) next
        if (pending) { printf "\n[org/gnome/shell/extensions/%s]\n", path; pending = 0 }
        print
      }'
  done
} >"$OUT"

# Segurança extra: nada com caminho de home, e-mail ou endereço MAC
if grep -nEi '/home/|@[a-z0-9.-]+\.[a-z]{2,}|([0-9a-f]{2}[:_]){5}[0-9a-f]{2}' "$OUT"; then
  echo "✘ Possível dado pessoal acima — revise $OUT" >&2
  exit 1
fi
echo "✔ Exportado para ${OUT#"$ROOT"/}"
