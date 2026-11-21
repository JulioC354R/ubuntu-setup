#!/usr/bin/env bash
# modules/22-git.sh — identidade do Git e chave SSH.
# Nome e e-mail NUNCA ficam no repo: vêm de ~/.config/ubuntu-setup/local.env
# (GIT_USER_NAME / GIT_USER_EMAIL; modelo em config/local.env.example).

GIT_DEFAULT_BRANCH="${SETUP_GIT_DEFAULT_BRANCH:-main}"
SSH_KEY="$HOME/.ssh/id_ed25519"

__git_get() { git config --global --get "$1" 2>/dev/null || true; }

# Com as variáveis definidas, confere se batem; sem elas, aceita a identidade que já existir.
check_git_identity() {
  has_cmd git || return 1
  [[ "$(__git_get init.defaultBranch)" == "$GIT_DEFAULT_BRANCH" ]] || return 1
  if [[ -n "${GIT_USER_NAME:-}" || -n "${GIT_USER_EMAIL:-}" ]]; then
    [[ "$(__git_get user.name)" == "${GIT_USER_NAME:-}" && "$(__git_get user.email)" == "${GIT_USER_EMAIL:-}" ]]
  else
    [[ -n "$(__git_get user.name)" && -n "$(__git_get user.email)" ]]
  fi
}

step_git_identity() {
  git config --global init.defaultBranch "$GIT_DEFAULT_BRANCH"
  if [[ -n "$(__git_get user.name)" && -n "$(__git_get user.email)" &&
        -z "${GIT_USER_NAME:-}" && -z "${GIT_USER_EMAIL:-}" ]]; then
    return 0   # já tem identidade e o local.env não pede outra
  fi
  require_var GIT_USER_NAME
  require_var GIT_USER_EMAIL
  git config --global user.name "$GIT_USER_NAME"
  git config --global user.email "$GIT_USER_EMAIL"
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
plan_step --check check_git_identity "Identidade do Git (local.env) e branch padrão $GIT_DEFAULT_BRANCH" step_git_identity
plan_step --check check_ssh_key "Chave SSH (ed25519)" step_ssh_key
