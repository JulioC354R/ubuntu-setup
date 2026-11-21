#!/usr/bin/env bash
# modules/35-infra.sh — infraestrutura e cloud.

# ── Terraform: repositório apt oficial da HashiCorp ─────────────────────────
step_terraform() {
  local codename; codename=$(. /etc/os-release && echo "$UBUNTU_CODENAME")
  apt_add_repo hashicorp.sources /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    https://apt.releases.hashicorp.com/gpg https://apt.releases.hashicorp.com "$codename" main
  apt_install terraform
}

# ── kubectl: repositório oficial pkgs.k8s.io ────────────────────────────────
# O repo é separado por versão minor (v1.37, v1.38...). O check compara com a última estável,
# então rodar o setup de novo migra para a minor nova.
KUBE_SOURCES=/etc/apt/sources.list.d/kubernetes.sources

kube_minor() { curl -fsSL https://dl.k8s.io/release/stable.txt | cut -d. -f1,2; }

check_kubectl() {
  pkg_installed kubectl && [[ -f "$KUBE_SOURCES" ]] &&
    [[ "$(cat "$KUBE_SOURCES")" == *"core:/stable:/$(kube_minor)/deb/"* ]]
}

step_kubectl() {
  local minor; minor=$(kube_minor)
  [[ "$minor" =~ ^v1\.[0-9]+$ ]] || { echo "Versão do Kubernetes inválida: '$minor'" >&2; return 1; }
  apt_add_repo kubernetes.sources /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    "https://pkgs.k8s.io/core:/stable:/$minor/deb/Release.key" \
    "https://pkgs.k8s.io/core:/stable:/$minor/deb/" /
  apt_install_latest kubectl
}

# ── Azure CLI: repositório apt oficial da Microsoft (caminhos da documentação do az) ──
step_azure_cli() {
  local codename; codename=$(. /etc/os-release && echo "$UBUNTU_CODENAME")
  apt_add_repo azure-cli.sources /etc/apt/keyrings/microsoft.gpg https://packages.microsoft.com/keys/microsoft.asc \
    https://packages.microsoft.com/repos/azure-cli/ "$codename" main
  apt_install azure-cli
}

# ── AWS CLI v2: snap oficial da AWS (assinado e com atualização automática) ──
step_aws_cli() { as_root snap install aws-cli --classic; }

# ── Helm: repositório apt oficial (Buildkite, indicado na documentação do Helm) ──
step_helm() {
  apt_add_repo helm.sources /usr/share/keyrings/helm.gpg https://packages.buildkite.com/helm-linux/helm-debian/gpgkey \
    https://packages.buildkite.com/helm-linux/helm-debian/any/ any main
  apt_install helm
}

# ── Binários das releases do GitHub em ~/.local/bin (sem sudo), com sha256 conferido.
#    O check compara com a última release: rodar o setup de novo atualiza. ──
LOCAL_BIN="$HOME/.local/bin"
k8s_arch() { case "$(deb_arch)" in amd64) echo amd64 ;; arm64) echo arm64 ;; *) require_arch amd64 arm64 ;; esac; }

# kind (Kubernetes in Docker)
check_kind() { [[ -x "$LOCAL_BIN/kind" ]] && [[ "$("$LOCAL_BIN/kind" version 2>/dev/null)" == "kind $(github_latest_tag kubernetes-sigs/kind) "* ]]; }
step_kind() {
  local tag arch tmp; tag=$(github_latest_tag kubernetes-sigs/kind); arch=$(k8s_arch); tmp=$(mktemp -d)
  download "https://github.com/kubernetes-sigs/kind/releases/download/$tag/kind-linux-$arch" "$tmp/kind-linux-$arch"
  download "https://github.com/kubernetes-sigs/kind/releases/download/$tag/kind-linux-$arch.sha256sum" "$tmp/sums"
  verify_sha256 "$tmp/kind-linux-$arch" "$tmp/sums"
  install -D -m 755 "$tmp/kind-linux-$arch" "$LOCAL_BIN/kind"
  rm -rf -- "$tmp"
}

# kustomize (releases com tag "kustomize/vX.Y.Z", misturadas com outras do monorepo)
kustomize_latest() {
  curl -fsSL "https://api.github.com/repos/kubernetes-sigs/kustomize/releases?per_page=30" |
    jq -r '[.[] | select(.tag_name | startswith("kustomize/")) | select(.prerelease | not)][0].tag_name // empty'
}
check_kustomize() { [[ -x "$LOCAL_BIN/kustomize" ]] && [[ "kustomize/$("$LOCAL_BIN/kustomize" version 2>/dev/null)" == "$(kustomize_latest)" ]]; }
step_kustomize() {
  local tag ver arch file tmp; tag=$(kustomize_latest); ver=${tag#kustomize/}; arch=$(k8s_arch); tmp=$(mktemp -d)
  [[ -n "$ver" ]] || { echo "Não encontrei a última release do kustomize." >&2; return 1; }
  file="kustomize_${ver}_linux_${arch}.tar.gz"
  download "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F$ver/$file" "$tmp/$file"
  download "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F$ver/checksums.txt" "$tmp/sums"
  verify_sha256 "$tmp/$file" "$tmp/sums"
  tar -xzf "$tmp/$file" -C "$tmp" kustomize
  install -D -m 755 "$tmp/kustomize" "$LOCAL_BIN/kustomize"
  rm -rf -- "$tmp"
}

# tflint (linter de Terraform)
check_tflint() {
  [[ -x "$LOCAL_BIN/tflint" ]] &&
    [[ "$("$LOCAL_BIN/tflint" --version 2>/dev/null | head -n1)" == "TFLint version $(github_latest_tag terraform-linters/tflint | sed 's/^v//')" ]]
}
step_tflint() {
  local tag arch file tmp; tag=$(github_latest_tag terraform-linters/tflint); arch=$(k8s_arch); tmp=$(mktemp -d)
  file="tflint_linux_${arch}.zip"
  download "https://github.com/terraform-linters/tflint/releases/download/$tag/$file" "$tmp/$file"
  download "https://github.com/terraform-linters/tflint/releases/download/$tag/checksums.txt" "$tmp/sums"
  verify_sha256 "$tmp/$file" "$tmp/sums"
  unzip -q -o "$tmp/$file" tflint -d "$tmp"
  install -D -m 755 "$tmp/tflint" "$LOCAL_BIN/tflint"
  rm -rf -- "$tmp"
}

plan_section "Infraestrutura"
plan_step --check "pkg_installed azure-cli" "Azure CLI" step_azure_cli
plan_step --check "has_cmd aws" "AWS CLI" step_aws_cli
plan_step --check "pkg_installed terraform" "Terraform" step_terraform
plan_step --check check_tflint "tflint" step_tflint
plan_step --check check_kubectl "kubectl" step_kubectl
plan_step --check "pkg_installed helm" "Helm" step_helm
plan_step --check check_kustomize "kustomize" step_kustomize
plan_step --check check_kind "kind" step_kind
