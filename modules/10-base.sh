#!/usr/bin/env bash
# modules/10-base.sh — base do sistema: índice do apt, ferramentas essenciais e PATH do usuário.

step_local_bin_path() {
  # shellcheck disable=SC2016
  shell_snippet 00-local-bin 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'
}

# Pacotes saudáveis têm status "?i" (instalado), "?c" (só config) ou "?n" (ausente), sem flag de erro.
# Qualquer outro (U unpacked, F half-configured, t triggers pendentes...) trava o apt.
dpkg_broken() { dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' | awk '$1 !~ /^[a-z][icn]$/ {print $2}'; }
check_dpkg_ok() { [[ -z "$(dpkg_broken)" ]]; }
step_dpkg_repair() {
  as_root dpkg --configure -a
  as_root apt-get install -f "${APT_OPTS[@]}"
}

plan_section "Base do sistema"
plan_step --check check_dpkg_ok "Reparar pacotes interrompidos" step_dpkg_repair
plan_step --check "apt_fresh" "Atualizar índice de pacotes" apt_update
plan_step --check "pkg_installed curl wget ca-certificates gnupg jq" \
  "Rede, certificados e jq" apt_install curl wget ca-certificates gnupg jq
plan_step --check "pkg_installed git" "Git" apt_install git
plan_step --check "pkg_installed build-essential" "Compiladores (build-essential)" apt_install build-essential
plan_step --check "pkg_installed unzip zip" "Compactação (zip/unzip)" apt_install unzip zip
plan_step --check "has_snippet 00-local-bin" "PATH do usuário (~/.local/bin)" step_local_bin_path
