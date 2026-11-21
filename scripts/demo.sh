#!/usr/bin/env bash
# scripts/demo.sh — simula uma instalação (sem instalar nada) para ver a interface e os temas.
#   scripts/demo.sh [tema]

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_LOG_DIR="${SETUP_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-setup/demo-logs}"
UI_TITLE="ubuntu-setup · demonstração"
# shellcheck source=lib/ui.sh
source "$ROOT/lib/ui.sh"

fake_work()   { sleep "$1"; echo "trabalho simulado por ${1}s"; }
fake_fail()   { sleep "$1"; echo "E: Unable to locate package pacote-que-nao-existe" >&2; return 100; }
fake_broken() { sleep 1; echo "baixando..."; false; echo "nunca chega aqui"; }
fake_stdin()  { sleep 0.5; read -r _ || true; }   # mostra que stdin não trava a etapa
always_true() { true; }

ui_init "${1:-${SETUP_THEME:-catppuccin}}"

plan_section "Base do sistema"
plan_step --check always_true "Atualizar índice de pacotes" fake_work 1
plan_step "Ferramentas de rede e certificados" fake_work 2
plan_step --check always_true "Git" fake_work 1
plan_section "Desenvolvimento"
plan_step "Docker Engine" fake_work 3
plan_step "Pacote inexistente (falha proposital)" fake_fail 1.5
plan_step "Node.js via mise" fake_work 2
plan_step "Etapa com comando quebrado (falha proposital)" fake_broken
plan_section "Desktop"
plan_step "Fontes Nerd Font" fake_work 1.5
plan_step "Etapa que tenta ler stdin" fake_stdin
plan_step --check always_true "Extensões do GNOME" fake_work 1

ui_header
ui_run_plan
ui_summary
