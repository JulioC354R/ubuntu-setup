#!/usr/bin/env bash
# modules/30-dev.sh — linguagens e ferramentas de desenvolvimento.

# ── Python (do Ubuntu) ───────────────────────────────────────────────────────
PYTHON_PKGS=(python3 python3-venv python3-pip python3-dev pipx)

# ── Go (tarball oficial em /usr/local/go, sempre a última versão estável) ──
go_latest() { curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1; }

check_go() {
  [[ -x /usr/local/go/bin/go ]] && has_snippet go &&
    [[ "$(/usr/local/go/bin/go env GOVERSION)" == "$(go_latest)" ]]
}

step_go() {
  local version arch file sha tmp
  version=$(go_latest)
  arch=$(deb_arch)   # amd64/arm64 usam o mesmo nome no Go
  file="$version.linux-$arch.tar.gz"
  sha=$(curl -fsSL 'https://go.dev/dl/?mode=json' |
    jq -r --arg f "$file" '.[].files[] | select(.filename == $f) | .sha256')
  [[ -n "$sha" ]] || { echo "Checksum de $file não encontrado." >&2; return 1; }

  tmp=$(mktemp -d)
  download "https://go.dev/dl/$file" "$tmp/$file"
  echo "$sha  $tmp/$file" | sha256sum -c -
  as_root rm -rf /usr/local/go   # caminho fixo, recomendado pela documentação oficial
  as_root tar -C /usr/local -xzf "$tmp/$file"
  rm -rf "$tmp"
  # shellcheck disable=SC2016
  shell_snippet go 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"'
}

# ── nvm + Node ───────────────────────────────────────────────────────────────
NVM_DIR="$HOME/.nvm"
NODE_VERSION="${SETUP_NODE_VERSION:-lts/*}"

step_nvm() {
  if [[ ! -d "$NVM_DIR/.git" ]]; then
    [[ -e "$NVM_DIR" ]] && { echo "$NVM_DIR existe mas não é um clone git; remova-o e rode de novo." >&2; return 1; }
    git clone -q https://github.com/nvm-sh/nvm.git "$NVM_DIR"
  fi
  git -C "$NVM_DIR" fetch -q --tags
  local tag
  tag=$(git -C "$NVM_DIR" describe --abbrev=0 --tags --match 'v[0-9]*' "$(git -C "$NVM_DIR" rev-list --tags --max-count=1)")
  git -C "$NVM_DIR" -c advice.detachedHead=false checkout -q "$tag"
  # shellcheck disable=SC2016
  shell_snippet nvm 'export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"'
}

check_nvm() { [[ -s "$NVM_DIR/nvm.sh" ]] && has_snippet nvm; }

__load_nvm() {  # nvm não funciona com set -eu
  set +eu; trap - ERR
  export NVM_DIR
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
}

check_node() {
  __load_nvm || return 1
  local want; want=$(nvm version-remote "$NODE_VERSION") || return 1
  [[ "$(nvm version default)" == "$want" ]]
}

step_node() {
  __load_nvm || return 1
  nvm install "$NODE_VERSION" --latest-npm || return 1
  nvm alias default "$NODE_VERSION" || return 1
}

# ── Rust (rustup oficial, em ~/.cargo; atualizar: rustup update) ────────────
check_rust() { [[ -x "$HOME/.cargo/bin/rustup" ]] && has_snippet rust; }

step_rust() {
  local tmp; tmp=$(mktemp)
  download https://sh.rustup.rs "$tmp"
  sh "$tmp" -y --no-modify-path --profile default   # PATH fica no shell.d, não no .bashrc
  rm -f "$tmp"
  # shellcheck disable=SC2016
  shell_snippet rust '[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"'
}

# ── Bun (binário da última release, com sha256 verificado; atualizar: bun upgrade) ──
BUN_DIR="$HOME/.bun"

check_bun() { [[ -x "$BUN_DIR/bin/bun" ]] && has_snippet bun; }

step_bun() {
  local asset tag tmp
  case "$(deb_arch)" in
    amd64) asset=bun-linux-x64.zip; grep -qw avx2 /proc/cpuinfo || asset=bun-linux-x64-baseline.zip ;;
    arm64) asset=bun-linux-aarch64.zip ;;
    *) echo "Arquitetura $(deb_arch) não suportada pelo Bun." >&2; return 1 ;;
  esac
  tag=$(curl -fsSL https://api.github.com/repos/oven-sh/bun/releases/latest | jq -r .tag_name)
  tmp=$(mktemp -d)
  download "https://github.com/oven-sh/bun/releases/download/$tag/$asset" "$tmp/$asset"
  download "https://github.com/oven-sh/bun/releases/download/$tag/SHASUMS256.txt" "$tmp/SHASUMS256.txt"
  (cd "$tmp" && grep " $asset\$" SHASUMS256.txt | sha256sum -c -)
  unzip -q -o "$tmp/$asset" -d "$tmp"
  install -D -m 755 "$tmp/${asset%.zip}/bun" "$BUN_DIR/bin/bun"
  ln -sfn bun "$BUN_DIR/bin/bunx"
  rm -rf "$tmp"
  # shellcheck disable=SC2016
  shell_snippet bun 'export BUN_INSTALL="$HOME/.bun"
case ":$PATH:" in *":$BUN_INSTALL/bin:"*) ;; *) export PATH="$BUN_INSTALL/bin:$PATH" ;; esac'
}

# ── Docker Engine (repositório oficial) ─────────────────────────────────────
DOCKER_PKGS=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

step_docker() {
  local codename; codename=$(. /etc/os-release && echo "$UBUNTU_CODENAME")
  apt_add_repo docker.sources /etc/apt/keyrings/docker.asc https://download.docker.com/linux/ubuntu/gpg \
    https://download.docker.com/linux/ubuntu "$codename" stable
  apt_install "${DOCKER_PKGS[@]}"
}

check_docker_group() { [[ " $(id -nG "${USER:-$(id -un)}") " == *" docker "* ]]; }
step_docker_group()  { as_root usermod -aG docker "${USER:-$(id -un)}"; }

# Limite de logs dos containers: sem isso o json-file cresce sem fim e pode lotar o disco.
# Vale para containers criados depois da mudança. Outras chaves do daemon.json são preservadas.
DOCKER_DAEMON_JSON=/etc/docker/daemon.json
DOCKER_LOG_MAX_SIZE="${SETUP_DOCKER_LOG_MAX_SIZE:-10m}"   # por arquivo
DOCKER_LOG_MAX_FILE="${SETUP_DOCKER_LOG_MAX_FILE:-3}"     # arquivos por container
DOCKER_LOG_JQ='."log-driver" == "json-file" and ."log-opts"."max-size" == $size and ."log-opts"."max-file" == $files'

check_docker_logs() {
  [[ -f "$DOCKER_DAEMON_JSON" ]] &&
    jq -e --arg size "$DOCKER_LOG_MAX_SIZE" --arg files "$DOCKER_LOG_MAX_FILE" "$DOCKER_LOG_JQ" \
      "$DOCKER_DAEMON_JSON" >/dev/null 2>&1
}

step_docker_logs() {
  local cur='{}' new
  [[ -s "$DOCKER_DAEMON_JSON" ]] && cur=$(as_root cat "$DOCKER_DAEMON_JSON")
  new=$(jq --arg size "$DOCKER_LOG_MAX_SIZE" --arg files "$DOCKER_LOG_MAX_FILE" \
    '. + {"log-driver": "json-file", "log-opts": ((."log-opts" // {}) + {"max-size": $size, "max-file": $files})}' \
    <<<"$cur") || { echo "$DOCKER_DAEMON_JSON não é um JSON válido." >&2; return 1; }
  [[ -f "$DOCKER_DAEMON_JSON" ]] && as_root cp -p "$DOCKER_DAEMON_JSON" "$DOCKER_DAEMON_JSON.bak-$(date +%Y%m%d-%H%M%S)"
  write_root_file "$DOCKER_DAEMON_JSON" "$new" || true
  # Reinicia o Docker só se não houver containers rodando (reiniciar derrubaria todos)
  if systemctl is-active --quiet docker 2>/dev/null; then
    if [[ -z "$(as_root docker ps -q 2>/dev/null)" ]]; then
      as_root systemctl restart docker
    else
      echo "Há containers rodando: o limite passa a valer quando o Docker for reiniciado."
    fi
  fi
}

# ── Claude Code (instalador nativo oficial) ─────────────────────────────────
check_claude_code() { [[ -x "$HOME/.local/bin/claude" ]] || has_cmd claude; }

step_claude_code() {
  local tmp; tmp=$(mktemp)
  download https://claude.ai/install.sh "$tmp"
  bash "$tmp"
  rm -f "$tmp"
}

plan_section "Desenvolvimento"
plan_step --check "pkg_installed ${PYTHON_PKGS[*]}" "Python 3 (venv, pip, pipx)" apt_install "${PYTHON_PKGS[@]}"
plan_step --check check_go "Go (última versão)" step_go
plan_step --check check_nvm "nvm" step_nvm
plan_step --check check_node "Node.js $NODE_VERSION (via nvm)" step_node
plan_step --check check_bun "Bun" step_bun
plan_step --check check_rust "Rust (rustup)" step_rust
plan_step --check "pkg_installed ${DOCKER_PKGS[*]}" "Docker Engine + Compose" step_docker
plan_step --check check_docker_group "Docker sem sudo (grupo docker)" step_docker_group
plan_step --check check_docker_logs "Docker: limite de logs ($DOCKER_LOG_MAX_SIZE × $DOCKER_LOG_MAX_FILE por container)" step_docker_logs
plan_step --check check_claude_code "Claude Code (CLI)" step_claude_code
