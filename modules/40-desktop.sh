#!/usr/bin/env bash
# modules/40-desktop.sh — aplicativos gráficos.

# ── Google Chrome: o .deb oficial cria o próprio repositório (atualiza via apt) ──
step_chrome() {
  require_arch amd64
  install_deb_url https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
}

# ── VS Code: repositório oficial da Microsoft (caminhos iguais aos da documentação) ──
check_vscode() { pkg_installed code && [[ -f /etc/apt/sources.list.d/vscode.sources ]]; }

step_vscode() {
  apt_add_repo vscode.sources /usr/share/keyrings/microsoft.gpg https://packages.microsoft.com/keys/microsoft.asc \
    https://packages.microsoft.com/repos/code stable main
  apt_install_latest code
}

# ── Obsidian: .deb da última release no GitHub (o app se atualiza sozinho) ──
step_obsidian() {
  local url
  url=$(github_latest_asset obsidianmd/obsidian-releases "_$(deb_arch)\\.deb$")
  [[ -n "$url" ]] || { echo "Nenhum .deb do Obsidian para $(deb_arch)." >&2; return 1; }
  install_deb_url "$url"
}

# ── Claude Desktop: repositório oficial, com chave baixada da URL oficial. Os arquivos são
#    idênticos aos que o próprio pacote cria (o postinst reescreve sem gerar conflito) ──
CLAUDE_DESKTOP_KEY_URL=https://downloads.claude.ai/claude-desktop/key.asc
CLAUDE_DESKTOP_KEYRING=/usr/share/keyrings/claude-desktop-archive-keyring.asc
CLAUDE_DESKTOP_LIST=/etc/apt/sources.list.d/claude-desktop.list

step_claude_desktop() {
  local tmp
  require_arch amd64 arm64
  tmp=$(mktemp)
  download "$CLAUDE_DESKTOP_KEY_URL" "$tmp"
  grep -q -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' "$tmp" || { echo "Chave inválida em $CLAUDE_DESKTOP_KEY_URL" >&2; return 1; }
  write_root_file "$CLAUDE_DESKTOP_KEYRING" "$(base64 -w0 "$tmp")" base64 || true
  rm -f "$tmp"
  write_root_file "$CLAUDE_DESKTOP_LIST" \
    "deb [arch=amd64,arm64 signed-by=$CLAUDE_DESKTOP_KEYRING] https://downloads.claude.ai/claude-desktop/apt/stable stable main" || true
  apt_update_source "$CLAUDE_DESKTOP_LIST"
  apt_install claude-desktop
}

# ── OBS Studio: PPA oficial do projeto (versão mais nova que a do Ubuntu) ──
obs_sources() {
  printf '/etc/apt/sources.list.d/obsproject-ubuntu-obs-studio-%s.sources' "$(. /etc/os-release && echo "$UBUNTU_CODENAME")"
}

check_obs() { pkg_installed obs-studio && [[ -f "$(obs_sources)" ]]; }

step_obs() {
  apt_install software-properties-common
  as_root add-apt-repository -y -n ppa:obsproject/obs-studio
  apt_update_source "$(obs_sources)"
  apt_install_latest obs-studio
}

# ── RustDesk: .deb oficial da última release no GitHub (sem repo apt; atualiza ao rodar o setup) ──
rustdesk_latest() { curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest | jq -r .tag_name; }

check_rustdesk() {
  [[ "$(dpkg-query -W -f='${Version}' rustdesk 2>/dev/null)" == "$(rustdesk_latest)" ]]
}

step_rustdesk() {
  local arch tag
  case "$(deb_arch)" in amd64) arch=x86_64 ;; arm64) arch=aarch64 ;; *) require_arch amd64 arm64 ;; esac
  tag=$(rustdesk_latest)
  [[ -n "$tag" && "$tag" != null ]] || { echo "Não consegui descobrir a última versão do RustDesk." >&2; return 1; }
  install_deb_url "https://github.com/rustdesk/rustdesk/releases/download/$tag/rustdesk-$tag-$arch.deb"
}

# ── DBeaver Community: repositório apt oficial (dbeaver.io; repo "flat", só amd64) ──
step_dbeaver() {
  require_arch amd64
  apt_add_repo dbeaver.sources /usr/share/keyrings/dbeaver.gpg https://dbeaver.io/debs/dbeaver.gpg.key \
    https://dbeaver.io/debs/dbeaver-ce /
  apt_install dbeaver-ce
}

plan_section "Aplicativos"
plan_step --check "pkg_installed google-chrome-stable" "Google Chrome" step_chrome
plan_step --check check_vscode "Visual Studio Code" step_vscode
plan_step --check "pkg_installed obsidian" "Obsidian" step_obsidian
plan_step --check "pkg_installed claude-desktop" "Claude Desktop" step_claude_desktop
plan_step --check check_obs "OBS Studio (PPA oficial)" step_obs
plan_step --check check_rustdesk "RustDesk (acesso remoto)" step_rustdesk
plan_step --check "pkg_installed gparted" "GParted" apt_install gparted
plan_step --check "pkg_installed dbeaver-ce" "DBeaver" step_dbeaver
