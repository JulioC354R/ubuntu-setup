#!/usr/bin/env bash
# modules/22-git.sh — branch padrão do Git e chave SSH.
# Nome e e-mail do Git não são configurados aqui: ficam a cargo do usuário (git config / gh auth login).

GIT_DEFAULT_BRANCH="${SETUP_GIT_DEFAULT_BRANCH:-main}"
SSH_KEY="$HOME/.ssh/id_ed25519"

check_git_default_branch() {
  [[ "$(git config --global --get init.defaultBranch 2>/dev/null)" == "$GIT_DEFAULT_BRANCH" ]]
}
step_git_default_branch() { git config --global init.defaultBranch "$GIT_DEFAULT_BRANCH"; }

# Chave ed25519 sem senha (a instalação não pode pedir input). Para pôr senha depois:
#   ssh-keygen -p -f ~/.ssh/id_ed25519
# Nunca sobrescreve uma chave existente.
check_ssh_key() { [[ -f "$SSH_KEY" && -f "$SSH_KEY.pub" ]]; }

step_ssh_key() {
  check_ssh_key && return 0
  [[ -e "$SSH_KEY" ]] && { echo "$SSH_KEY existe sem a .pub; não vou sobrescrever." >&2; return 1; }
  has_cmd ssh-keygen || apt_install openssh-client
  install -d -m 700 "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N "" -C "$(id -un)@${HOSTNAME:-$(uname -n)}" -f "$SSH_KEY" </dev/null
}

plan_section "Git e SSH"
plan_step --check check_git_default_branch "Git: branch padrão $GIT_DEFAULT_BRANCH" step_git_default_branch
plan_step --check check_ssh_key "Chave SSH (ed25519)" step_ssh_key
