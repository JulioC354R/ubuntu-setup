#!/usr/bin/env bash
# modules/25-terminal.sh — Kitty + zsh + Oh My Zsh (plugins) + Oh My Posh (prompt if_tea).

ZSH_DIR="$HOME/.oh-my-zsh"
ZSH_PLUGINS_DIR="${ZSH_CUSTOM:-$ZSH_DIR/custom}/plugins"
OMP_BIN="$HOME/.local/bin/oh-my-posh"
OMP_THEME="${XDG_CONFIG_HOME:-$HOME/.config}/oh-my-posh/if_tea.omp.json"
KITTY_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
TERMINAL_FONT="MesloLGM Nerd Font"

# nome|url (ordem do plugins=() fica no config/zsh/zshrc)
ZSH_PLUGINS=(
  "fzf-tab|https://github.com/Aloxaf/fzf-tab.git"
  "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions.git"
  "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git"
)

# ── Oh My Zsh (não interativo, sem trocar o shell, sem mexer no .zshrc) ─────
check_ohmyzsh() { [[ -f "$ZSH_DIR/oh-my-zsh.sh" ]]; }

step_ohmyzsh() {
  local tmp; tmp=$(mktemp)
  download https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh "$tmp"
  ZSH="$ZSH_DIR" RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$tmp" --unattended
  rm -f "$tmp"
}

check_zsh_plugins() {
  local p
  for p in "${ZSH_PLUGINS[@]}"; do [[ -d "$ZSH_PLUGINS_DIR/${p%%|*}/.git" ]] || return 1; done
}

step_zsh_plugins() {
  local p
  for p in "${ZSH_PLUGINS[@]}"; do git_sync "${p#*|}" "$ZSH_PLUGINS_DIR/${p%%|*}"; done
}

# ── Oh My Posh (script oficial, em ~/.local/bin) ────────────────────────────
check_ohmyposh() { [[ -x "$OMP_BIN" ]]; }

step_ohmyposh() {
  local tmp; tmp=$(mktemp)
  download https://ohmyposh.dev/install.sh "$tmp"
  mkdir -p "$HOME/.local/bin"   # o instalador exige que o diretório exista
  bash "$tmp" -d "$HOME/.local/bin"
  rm -f "$tmp"
  # o instalador pode sair com código 0 mesmo falhando: confere o resultado
  check_ohmyposh || { echo "oh-my-posh não foi instalado em $OMP_BIN." >&2; return 1; }
}

check_terminal_font() { [[ "$(fc-list : family)" == *"$TERMINAL_FONT"* ]]; }

step_terminal_font() {
  "$OMP_BIN" font install meslo
  fc-cache -f >/dev/null
  check_terminal_font || { echo "Fonte $TERMINAL_FONT não apareceu no fc-list após a instalação." >&2; return 1; }
}

# ── Tema if_tea: original da mesma versão do Oh My Posh instalado, com duas mudanças:
#    1. path → style "folder" (só o nome da pasta atual)
#    2. segmento "terraform" logo após o path: workspace atual, só em pastas com projeto Terraform
OMP_TERRAFORM_BG="#7b42bc"   # roxo HashiCorp

check_omp_theme() {
  [[ -f "$OMP_THEME" ]] &&
    [[ "$(jq -r '[.blocks[].segments[] | select(.type == "path") | (.options // .properties).style] | unique | join(",")' "$OMP_THEME")" == folder ]] &&
    jq -e '[.blocks[].segments[] | select(.type == "terraform")] | length == 1' "$OMP_THEME" >/dev/null
}

step_omp_theme() {
  local version tmp
  version=$("$OMP_BIN" version)
  tmp=$(mktemp -d)
  download "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/v$version/themes/if_tea.omp.json" "$tmp/original.json"
  # 1. style do "path"; a chave é "options" (schema novo) ou "properties" (antigo).
  # 2. insere o "terraform" logo após o path, com os mesmos separadores (diamond) do path.
  jq --arg bg "$OMP_TERRAFORM_BG" '
    (.blocks[].segments[] | select(.type == "path")) |=
      (if has("options") then .options.style = "folder"
       elif has("properties") then .properties.style = "folder"
       else error("segmento path sem options/properties") end)
    | .blocks[].segments |= (if any(.[]; .type == "terraform") then . else
        reduce .[] as $s ([]; . + [$s] + (if $s.type != "path" then [] else [{
          type: "terraform",
          style: "diamond",
          foreground: "#ffffff",
          background: $bg,
          leading_diamond: (($s.leading_diamond // "") | gsub("(?i)" + ($s.background // "#none"); $bg)),
          trailing_diamond: ($s.trailing_diamond // ""),
          template: "  {{ .WorkspaceName }} "
        }] end))
      end)' "$tmp/original.json" >"$tmp/if_tea.omp.json"
  install_file "$tmp/if_tea.omp.json" "$OMP_THEME"
  rm -rf -- "$tmp"
}

# ── ~/.zshrc versionado ─────────────────────────────────────────────────────
check_zshrc() { cmp -s "$SETUP_ROOT/config/zsh/zshrc" "$HOME/.zshrc"; }
step_zshrc()  { install_file "$SETUP_ROOT/config/zsh/zshrc" "$HOME/.zshrc"; }   # backup se diferente

# ── Kitty: config versionada em ubuntu-setup.conf, incluída no TOPO do kitty.conf ──
# Assim o kitty.conf continua sendo seu: o que estiver abaixo do include sobrescreve o setup.
KITTY_SETUP_CONF="$(dirname "$KITTY_CONF")/ubuntu-setup.conf"
KITTY_INCLUDE="include ubuntu-setup.conf"

KITTY_MENU="$(dirname "$KITTY_CONF")/ubuntu-setup-menu.py"   # kitten do menu do clique direito

check_kitty_conf() {
  cmp -s "$SETUP_ROOT/config/kitty/ubuntu-setup.conf" "$KITTY_SETUP_CONF" &&
    cmp -s "$SETUP_ROOT/config/kitty/ubuntu-setup-menu.py" "$KITTY_MENU" &&
    [[ -f "$KITTY_CONF" ]] && grep -qxF "$KITTY_INCLUDE" "$KITTY_CONF" &&
    [[ -d "$(dirname "$KITTY_CONF")/sessions" ]]
}

step_kitty_conf() {
  local tmp
  install_file "$SETUP_ROOT/config/kitty/ubuntu-setup.conf" "$KITTY_SETUP_CONF"
  install_file "$SETUP_ROOT/config/kitty/ubuntu-setup-menu.py" "$KITTY_MENU"
  mkdir -p "$(dirname "$KITTY_CONF")/sessions"   # grupos de tabs (alt+shift+a / alt+shift+s)
  if ! { [[ -f "$KITTY_CONF" ]] && grep -qxF "$KITTY_INCLUDE" "$KITTY_CONF"; }; then
    tmp=$(mktemp)
    { printf '%s\n\n# Suas configurações abaixo sobrescrevem as do ubuntu-setup.\n' "$KITTY_INCLUDE"
      [[ -f "$KITTY_CONF" ]] && cat "$KITTY_CONF"; } >"$tmp"
    install_file "$tmp" "$KITTY_CONF"   # backup do kitty.conf anterior, se existia
    rm -f "$tmp"
  fi
}

# ── Kitty como terminal padrão (Ctrl+Alt+T, "Abrir no terminal") ────────────
# Ubuntu 25.10+: o GNOME chama xdg-terminal-exec, que usa o 1º item válido de
# ~/.config/[<desktop>-]xdg-terminals.list. Ubuntu 24.04: lê o gsettings default-applications.terminal.
# O Kitty vai para o topo; o que já estava na lista (ex.: Warp) continua como reserva.
XDG_TERMINALS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

check_default_terminal() {
  if has_cmd xdg-terminal-exec; then
    [[ "$(xdg-terminal-exec --print-id 2>/dev/null)" == kitty.desktop ]]
  else
    [[ "$(gsettings get org.gnome.desktop.default-applications.terminal exec 2>/dev/null)" == "'kitty'" ]]
  fi
}

step_default_terminal() {
  [[ -f /usr/share/applications/kitty.desktop ]] || { echo "kitty.desktop não encontrado (Kitty instalado?)." >&2; return 1; }
  if has_cmd xdg-terminal-exec; then
    local f tmp files=("$XDG_TERMINALS_DIR/xdg-terminals.list")
    # listas específicas do desktop (ex.: ubuntu-xdg-terminals.list) têm prioridade: ajusta também
    for f in "$XDG_TERMINALS_DIR"/*-xdg-terminals.list; do [[ -f "$f" ]] && files+=("$f"); done
    for f in "${files[@]}"; do
      tmp=$(mktemp)
      { echo kitty.desktop; [[ -f "$f" ]] && grep -vxF kitty.desktop "$f"; } >"$tmp" || true
      install_file "$tmp" "$f"   # backup da lista anterior
      rm -f "$tmp"
    done
  else
    gsettings set org.gnome.desktop.default-applications.terminal exec 'kitty'
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg ''
  fi
  check_default_terminal || { echo "Kitty não ficou como terminal padrão." >&2; return 1; }
}

# ── zsh como shell padrão (como root para não pedir senha do chsh) ─────────
check_default_shell() { [[ "$(getent passwd "${USER:-$(id -un)}" | cut -d: -f7)" == "$(command -v zsh)" ]]; }
step_default_shell()  { has_cmd zsh && as_root chsh -s "$(command -v zsh)" "${USER:-$(id -un)}"; }

plan_section "Terminal: Kitty + zsh"
plan_step --check "pkg_installed kitty zsh fzf wl-clipboard fontconfig" "Kitty, zsh, fzf e wl-clipboard" \
  apt_install kitty zsh fzf wl-clipboard fontconfig
plan_step --check check_ohmyzsh "Oh My Zsh" step_ohmyzsh
plan_step --check check_zsh_plugins "Plugins: fzf-tab, autosuggestions, syntax-highlighting" step_zsh_plugins
plan_step --check check_ohmyposh "Oh My Posh" step_ohmyposh
plan_step --check check_terminal_font "Fonte $TERMINAL_FONT" step_terminal_font
plan_step --check check_omp_theme "Tema if_tea (pasta atual + workspace Terraform)" step_omp_theme
plan_step --check check_zshrc "~/.zshrc" step_zshrc
plan_step --check check_kitty_conf "Kitty: splits, tabs, grupos, menu, opacidade 85%" step_kitty_conf
plan_step --check check_default_terminal "Kitty como terminal padrão (Ctrl+Alt+T)" step_default_terminal
plan_step --check check_default_shell "zsh como shell padrão" step_default_shell
