#!/usr/bin/env bash
# modules/20-cli.sh — ferramentas de terminal.

# ── GitHub CLI: repositório oficial (o do Ubuntu fica desatualizado) ────────
check_gh() { pkg_installed gh && [[ -f /etc/apt/sources.list.d/github-cli.sources ]]; }

step_gh() {
  apt_add_repo github-cli.sources /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    https://cli.github.com/packages stable main
  apt_install_latest gh   # troca a versão do Ubuntu pela do repo oficial
}

plan_section "Terminal"
plan_step --check "pkg_installed btop" "btop" apt_install btop
plan_step --check check_gh "GitHub CLI (repo oficial)" step_gh
