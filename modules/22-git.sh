#!/usr/bin/env bash
# modules/22-git.sh — identidade do Git e chave SSH.
# Usuário e e-mail do GitHub NUNCA ficam no repo: o install.sh pergunta no início (ask_git_identity),
# antes do plano. Sem perguntar (automação): GIT_USER_NAME=... GIT_USER_EMAIL=... ./install.sh

GIT_DEFAULT_BRANCH="${SETUP_GIT_DEFAULT_BRANCH:-main}"
SSH_KEY="$HOME/.ssh/id_ed25519"
GITHUB_USER_RE='^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$'
EMAIL_RE='^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'

__git_get() { git config --global --get "$1" 2>/dev/null || true; }

# E-mail anônimo do GitHub (<id>+<usuário>@users.noreply.github.com): não expõe o e-mail real em repos públicos
github_noreply_email() {
  local id
  id=$(curl -fsSL --connect-timeout 5 "https://api.github.com/users/$1" 2>/dev/null | jq -r '.id // empty' 2>/dev/null)
  [[ "$id" =~ ^[0-9]+$ ]] && printf '%s+%s@users.noreply.github.com' "$id" "$1"
}

# Chamado pelo install.sh antes do plano (não é uma etapa). Enter aceita o valor sugerido.
ask_git_identity() {
  local user="${GIT_USER_NAME:-}" email="${GIT_USER_EMAIL:-}" def
  if [[ -z "$user" || -z "$email" ]] && ui_can_ask; then
    printf '\n'
    ui_info "GitHub: usado na identidade do Git e no comentário da chave SSH (Enter aceita o sugerido)"
    if [[ -z "$user" ]]; then
      def=$(__git_get user.name); [[ "$def" =~ $GITHUB_USER_RE ]] || def=""
      ui_ask user "Usuário do GitHub" "$def" "$GITHUB_USER_RE" || true
    fi
    if [[ -z "$email" ]]; then
      def=$(__git_get user.email)
      [[ -z "$def" && -n "$user" ]] && def=$(github_noreply_email "$user")
      ui_ask email "E-mail" "$def" "$EMAIL_RE" || true
    fi
    printf '\n'
  fi
  if [[ -n "$user" && -n "$email" ]]; then
    export GIT_USER_NAME="$user" GIT_USER_EMAIL="$email"
  else
    unset GIT_USER_NAME GIT_USER_EMAIL
  fi
}

# Com usuário/e-mail informados, confere se batem; sem eles, aceita a identidade que já existir.
check_git_identity() {
  has_cmd git || return 1
  [[ "$(__git_get init.defaultBranch)" == "$GIT_DEFAULT_BRANCH" ]] || return 1
  if [[ -n "${GIT_USER_NAME:-}" ]]; then
    [[ "$(__git_get user.name)" == "$GIT_USER_NAME" && "$(__git_get user.email)" == "$GIT_USER_EMAIL" ]]
  else
    [[ -n "$(__git_get user.name)" && -n "$(__git_get user.email)" ]]
  fi
}

step_git_identity() {
  git config --global init.defaultBranch "$GIT_DEFAULT_BRANCH"
  if [[ -n "${GIT_USER_NAME:-}" ]]; then
    git config --global user.name "$GIT_USER_NAME"
    git config --global user.email "$GIT_USER_EMAIL"
  elif [[ -z "$(__git_get user.name)" || -z "$(__git_get user.email)" ]]; then
    echo "Usuário e e-mail do GitHub não informados no início da instalação. Rode de novo e responda às perguntas." >&2
    return 1
  fi
}

# Chave ed25519 sem senha (a instalação não pode pedir input). Para pôr senha depois:
#   ssh-keygen -p -f ~/.ssh/id_ed25519
# Nunca sobrescreve uma chave existente.
check_ssh_key() { [[ -f "$SSH_KEY" && -f "$SSH_KEY.pub" ]]; }

step_ssh_key() {
  check_ssh_key && return 0
  [[ -e "$SSH_KEY" ]] && { echo "$SSH_KEY existe sem a .pub; não vou sobrescrever." >&2; return 1; }
  has_cmd ssh-keygen || apt_install openssh-client
  install -d -m 700 "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N "" -C "${GIT_USER_EMAIL:-$(id -un)@${HOSTNAME:-$(uname -n)}}" -f "$SSH_KEY" </dev/null
}

plan_section "Git e SSH"
plan_step --check check_git_identity "Identidade do Git (GitHub) e branch padrão $GIT_DEFAULT_BRANCH" step_git_identity
plan_step --check check_ssh_key "Chave SSH (ed25519)" step_ssh_key
