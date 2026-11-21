#!/usr/bin/env bash
# scripts/preview-themes.sh — mostra uma amostra estática de cada tema.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/ui.sh
source "$ROOT/lib/ui.sh"

swatch() { printf '%s██%s' "$1" "$C_RESET"; }

for t in "${UI_THEMES[@]}"; do
  ui_init "$t"
  UI_TOTAL=12 UI_CURRENT=5
  printf '\n  %s%s%s  %s %s %s %s %s %s\n' "$C_BOLD$C_ACCENT" "$t" "$C_RESET" \
    "$(swatch "$C_ACCENT")" "$(swatch "$C_OK")" "$(swatch "$C_WARN")" \
    "$(swatch "$C_ERR")" "$(swatch "$C_INFO")" "$(swatch "$C_MUTED")"
  __ui_section_line "Base do sistema"
  __ui_draw_result "$T_ICON_OK" "$C_OK" "Git" "3s"
  __ui_draw_result "$T_ICON_SKIP" "$C_MUTED" "${C_MUTED}Ferramentas de rede" "já ok"
  __ui_draw_result "$T_ICON_FAIL" "$C_ERR" "${C_ERR}Pacote inexistente" "falhou (código 100)"
  __ui_draw_running "Docker Engine" "${T_SPINNER[2]}" 7
  printf '\n'
done
printf '\n  Use: ./install.sh --theme <nome>   ou   SETUP_THEME=<nome>\n\n'
