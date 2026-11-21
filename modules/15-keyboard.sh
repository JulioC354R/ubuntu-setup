#!/usr/bin/env bash
# modules/15-keyboard.sh — layouts US Internacional (principal) e ABNT2, alternando com Super+Espaço.
# US Internacional (dead keys) com cedilha brasileira:
#   '+a = á   ~+a = ã   ^+e = ê   `+a = à   "+u = ü   '+c = ç (em vez de ć)
#   Para digitar só o apóstrofo/aspas: a tecla seguida de espaço.
# O US Intl gera ć por padrão; o ~/.XCompose (lido pelo IBus no GNOME/Wayland) troca para ç.
# ABNT2 ("br" no xkb): teclado brasileiro, com tecla própria de ç.

KEYBOARD_SOURCES="${SETUP_KEYBOARD_SOURCES:-[('xkb', 'us+intl'), ('xkb', 'br')]}"
KEYBOARD_SWITCH="<Super>space"   # padrão do GNOME; Shift+Super+Espaço volta para o anterior
XCOMPOSE="$HOME/.XCompose"
XCOMPOSE_CEDILHA='<dead_acute> <c> : "ç" ccedilla
<dead_acute> <C> : "Ç" Ccedilla
<acute> <c>      : "ç" ccedilla
<acute> <C>      : "Ç" Ccedilla'

check_keyboard_layout() { [[ "$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null)" == "$KEYBOARD_SOURCES" ]]; }
step_keyboard_layout()  { gsettings set org.gnome.desktop.input-sources sources "$KEYBOARD_SOURCES"; }

check_cedilha() {
  [[ "$(head -n1 "$XCOMPOSE" 2>/dev/null)" == 'include "%L"' ]] && has_block "$XCOMPOSE" cedilha "$XCOMPOSE_CEDILHA"
}

step_cedilha() {
  local tmp
  # 1ª linha: herda o Compose padrão do idioma (sem isso, as outras combinações param de funcionar)
  if [[ "$(head -n1 "$XCOMPOSE" 2>/dev/null)" != 'include "%L"' ]]; then
    tmp=$(mktemp)
    { echo 'include "%L"'; [[ -f "$XCOMPOSE" ]] && grep -vxF 'include "%L"' "$XCOMPOSE"; } >"$tmp" || true
    install_file "$tmp" "$XCOMPOSE"
    rm -f "$tmp"
  fi
  ensure_block "$XCOMPOSE" cedilha "$XCOMPOSE_CEDILHA"
  # Recarrega o IBus para ler o Compose novo (sem precisar sair da sessão)
  if has_cmd ibus && pgrep -x ibus-daemon >/dev/null; then ibus restart || true; fi
}

# Atalho para alternar layouts: garante Super+Espaço sem apagar outros atalhos que existam ali
check_keyboard_switch() {
  [[ "$(gsettings get org.gnome.desktop.wm.keybindings switch-input-source 2>/dev/null)" == *"'$KEYBOARD_SWITCH'"* ]]
}
step_keyboard_switch() {
  local cur; cur=$(gsettings get org.gnome.desktop.wm.keybindings switch-input-source)
  if [[ "$cur" == "@as []" || "$cur" == "[]" ]]; then
    gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['$KEYBOARD_SWITCH']"
  else
    gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['$KEYBOARD_SWITCH', ${cur#[}"
  fi
}

plan_section "Teclado"
plan_step --check check_keyboard_layout "Layouts US Internacional + ABNT2" step_keyboard_layout
plan_step --check check_keyboard_switch "Alternar layout com Super+Espaço" step_keyboard_switch
plan_step --check check_cedilha "Cedilha: ' + c = ç" step_cedilha
