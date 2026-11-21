#!/usr/bin/env bash
# lib/themes.sh — paletas e estilos visuais do instalador.
# Cada tema define cores (hex) e estilo (spinner, barra). Adicionar tema = criar theme_<nome>.

UI_THEMES=(catppuccin dracula nord tokyonight gruvbox mono)

# Valores comuns; cada tema sobrescreve o que quiser.
__theme_defaults() {
  T_ACCENT="" T_OK="" T_WARN="" T_ERR="" T_INFO="" T_MUTED="" T_TEXT=""
  T_SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  T_BAR_FULL="━" T_BAR_EMPTY="─"
  T_ICON_OK="✔" T_ICON_FAIL="✘" T_ICON_SKIP="↷" T_ICON_SECTION="◆" T_ICON_INFO="›" T_ICON_PENDING="○"
  T_BOX=(╭ ╮ ╰ ╯ │ ─)
}

theme_catppuccin() {  # Mocha
  T_ACCENT="#cba6f7" T_OK="#a6e3a1" T_WARN="#f9e2af" T_ERR="#f38ba8"
  T_INFO="#89b4fa"   T_MUTED="#6c7086" T_TEXT="#cdd6f4"
}

theme_dracula() {
  T_ACCENT="#bd93f9" T_OK="#50fa7b" T_WARN="#f1fa8c" T_ERR="#ff5555"
  T_INFO="#8be9fd"   T_MUTED="#6272a4" T_TEXT="#f8f8f2"
  T_SPINNER=(◐ ◓ ◑ ◒)
  T_BAR_FULL="█" T_BAR_EMPTY="░"
}

theme_nord() {
  T_ACCENT="#88c0d0" T_OK="#a3be8c" T_WARN="#ebcb8b" T_ERR="#bf616a"
  T_INFO="#81a1c1"   T_MUTED="#4c566a" T_TEXT="#eceff4"
  T_SPINNER=(⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷)
  T_BAR_FULL="▰" T_BAR_EMPTY="▱"
}

theme_tokyonight() {
  T_ACCENT="#7aa2f7" T_OK="#9ece6a" T_WARN="#e0af68" T_ERR="#f7768e"
  T_INFO="#7dcfff"   T_MUTED="#565f89" T_TEXT="#c0caf5"
  T_SPINNER=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █ ▇ ▆ ▅ ▄ ▃ ▂)
  T_BAR_FULL="■" T_BAR_EMPTY="·"
  T_ICON_SECTION="◈"
}

theme_gruvbox() {
  T_ACCENT="#fe8019" T_OK="#b8bb26" T_WARN="#fabd2f" T_ERR="#fb4934"
  T_INFO="#83a598"   T_MUTED="#928374" T_TEXT="#ebdbb2"
  T_SPINNER=(◢ ◣ ◤ ◥)
  T_BAR_FULL="▓" T_BAR_EMPTY="░"
  T_ICON_SECTION="■"
}

theme_mono() {  # sem cores, só negrito/esmaecido
  T_SPINNER=('|' '/' '-' '\')
  T_BAR_FULL="#" T_BAR_EMPTY="."
}

# Substitui símbolos Unicode quando o terminal não é UTF-8.
__theme_ascii() {
  T_SPINNER=('|' '/' '-' '\')
  T_BAR_FULL="#" T_BAR_EMPTY="."
  T_ICON_OK="+" T_ICON_FAIL="x" T_ICON_SKIP="=" T_ICON_SECTION="*" T_ICON_INFO=">" T_ICON_PENDING="o"
  T_BOX=(+ + + + '|' -)
}

theme_exists() {
  local t
  for t in "${UI_THEMES[@]}"; do [[ "$t" == "$1" ]] && return 0; done
  return 1
}
