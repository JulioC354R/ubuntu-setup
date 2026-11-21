#!/usr/bin/env bash
# lib/ui.sh — interface do instalador: temas, plano de etapas, progresso, resumo e logs de falha.
#
# Uso:
#   source lib/ui.sh
#   ui_init                                   # aplica tema (SETUP_THEME) e detecta terminal
#   plan_section "Base"
#   plan_step [--check "cmd args"] "Rótulo" comando args...
#   ui_header; ui_run_plan; ui_summary        # ui_summary retorna 0 / 1 (falhas) / 130 (interrompido)

[[ -n "${__UI_LOADED:-}" ]] && return 0
__UI_LOADED=1

__UI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/themes.sh
source "$__UI_DIR/themes.sh"

UI_THEME="${SETUP_THEME:-catppuccin}"
UI_TITLE="${UI_TITLE:-ubuntu-setup}"
UI_LOG_ROOT="${SETUP_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-setup/logs}"
UI_RUN_ID="$(date +%Y%m%d-%H%M%S)"
UI_LOG_DIR="$UI_LOG_ROOT/$UI_RUN_ID"

# Plano (preenchido pelos módulos)
__PLAN_KIND=() __PLAN_LABEL=() __PLAN_CMD=() __PLAN_CHECK=()
UI_TOTAL=0

# Resultados
UI_OK=() UI_OK_TIME=() UI_SKIP=() UI_FAIL=() UI_FAIL_LOG=() UI_FAIL_RC=() UI_FAIL_REASON=() UI_PENDING=()
UI_DRY_RUN="${UI_DRY_RUN:-0}"   # 1 = só roda as verificações e mostra o que seria instalado
UI_CURRENT=0
UI_CLEANUP_PIDS=()
__UI_CHILD="" __UI_INTERRUPTED=0 __UI_START=$SECONDS

# Modo de exibição: panel (tela cheia) | classic (uma linha por etapa). Ver __ui_choose_mode.
UI_MODE=classic __UI_ALT=0
# Estado por etapa (índice 0..N-1) e por seção, montado por __ui_index a partir do plano
__ST_LABEL=() __ST_SEC=() __ST_STATUS=() __ST_DUR=()
__SEC_NAME=() __SEC_FROM=() __SEC_TO=()

# ───────────────────────────── terminal e cores ─────────────────────────────

__ui_hex() {  # hex -> sequência ANSI de cor de texto (truecolor ou 256 cores)
  local h=${1#\#} r g b
  [[ -z "$h" || $UI_COLOR -eq 0 ]] && return 0
  r=$((16#${h:0:2})) g=$((16#${h:2:2})) b=$((16#${h:4:2}))
  if (( UI_TRUECOLOR )); then
    printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
  else
    printf '\033[38;5;%dm' $((16 + 36*((r*5+127)/255) + 6*((g*5+127)/255) + (b*5+127)/255))
  fi
}

ui_init() {
  [[ -n "${1:-}" ]] && UI_THEME="$1"
  if ! theme_exists "$UI_THEME"; then
    printf 'Tema desconhecido: %s (disponíveis: %s). Usando catppuccin.\n' \
      "$UI_THEME" "${UI_THEMES[*]}" >&2
    UI_THEME=catppuccin
  fi

  UI_TTY=0 UI_COLOR=0 UI_TRUECOLOR=0
  if [[ -t 1 && "${TERM:-dumb}" != dumb && -z "${SETUP_PLAIN:-}" ]]; then UI_TTY=1; fi
  if (( UI_TTY )) && [[ -z "${NO_COLOR:-}" ]]; then UI_COLOR=1; fi
  case "${COLORTERM:-}" in truecolor|24bit) UI_TRUECOLOR=1 ;; esac
  # Terminais modernos comuns no Ubuntu suportam truecolor mesmo sem COLORTERM.
  [[ -n "${VTE_VERSION:-}" || "${TERM_PROGRAM:-}" == vscode ]] && UI_TRUECOLOR=1

  __theme_defaults
  "theme_$UI_THEME"
  [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" =~ [Uu][Tt][Ff]-?8 ]] || __theme_ascii

  C_ACCENT=$(__ui_hex "$T_ACCENT") C_OK=$(__ui_hex "$T_OK")   C_WARN=$(__ui_hex "$T_WARN")
  C_ERR=$(__ui_hex "$T_ERR")       C_INFO=$(__ui_hex "$T_INFO") C_MUTED=$(__ui_hex "$T_MUTED")
  C_TEXT=$(__ui_hex "$T_TEXT")
  if (( UI_COLOR )); then
    C_BOLD=$'\033[1m' C_DIM=$'\033[2m' C_RESET=$'\033[0m'
    [[ -z "$T_MUTED" ]] && C_MUTED=$C_DIM
  else
    C_BOLD="" C_DIM="" C_RESET=""
  fi

  __ui_measure
  __UI_OS=$( (. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-Linux}") || echo Linux)

  # Painel: título em destaque (fundo na cor do tema; sem cor, vídeo reverso)
  if (( UI_COLOR )) && [[ -n "$T_ACCENT" ]]; then
    C_BAR="$(__ui_hex "#11111b")$(__ui_hex_bg "$T_ACCENT")$C_BOLD"
  else
    C_BAR=$'\033[7m'
  fi

  trap '__ui_cleanup' EXIT
  trap '__ui_on_interrupt' INT TERM
}

__ui_measure() {  # largura útil (máx. 100) e altura do terminal
  UI_REAL_COLS=$(tput cols 2>/dev/null || echo 80)
  UI_ROWS=$(tput lines 2>/dev/null || echo 24)
  [[ "$UI_REAL_COLS" =~ ^[0-9]+$ ]] || UI_REAL_COLS=80
  [[ "$UI_ROWS" =~ ^[0-9]+$ ]] || UI_ROWS=24
  UI_COLS=$UI_REAL_COLS
  (( UI_COLS > 100 )) && UI_COLS=100
  return 0
}

__ui_hex_bg() {  # hex -> sequência ANSI de cor de FUNDO
  local h=${1#\#} r g b
  [[ -z "$h" || $UI_COLOR -eq 0 ]] && return 0
  r=$((16#${h:0:2})) g=$((16#${h:2:2})) b=$((16#${h:4:2}))
  if (( UI_TRUECOLOR )); then
    printf '\033[48;2;%d;%d;%dm' "$r" "$g" "$b"
  else
    printf '\033[48;5;%dm' $((16 + 36*((r*5+127)/255) + 6*((g*5+127)/255) + (b*5+127)/255))
  fi
}

__ui_cleanup() {
  local p
  for p in "${UI_CLEANUP_PIDS[@]}"; do kill "$p" 2>/dev/null; done
  (( __UI_ALT )) && printf '\033[?1049l'   # sai da tela do painel
  (( UI_TTY )) && printf '\033[?25h'       # mostra o cursor de volta
}

__ui_kill_tree() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do __ui_kill_tree "$child"; done
  kill -TERM "$1" 2>/dev/null
}

__ui_on_interrupt() {
  __UI_INTERRUPTED=1
  [[ -n "$__UI_CHILD" ]] && __ui_kill_tree "$__UI_CHILD"
}

# ───────────────────────────── utilitários de texto ─────────────────────────

__ui_fit() {  # texto largura -> corta com … ou completa com espaços
  local s=$1 w=$2
  (( w < 1 )) && return 0
  if (( ${#s} > w )); then s="${s:0:w-1}…"; fi
  printf '%s%*s' "$s" $((w - ${#s})) ''
}

__ui_repeat() {  # caractere vezes
  local out
  (( $2 > 0 )) || return 0
  printf -v out '%*s' "$2" ''
  printf '%s' "${out// /$1}"
}

__ui_duration() {
  local s=$1
  if (( s < 60 )); then printf '%ds' "$s"; else printf '%dm%02ds' $((s / 60)) $((s % 60)); fi
}

__ui_tilde() { printf '%s' "${1/#$HOME/\~}"; }

# Versões sem subshell (escrevem numa variável), usadas pelo painel que redesenha 10×/s
__ui_fitv() {  # var texto largura
  local -n __fv_out=$1
  local __fv_s=$2 __fv_w=$3
  (( __fv_w < 1 )) && { __fv_out=""; return 0; }
  (( ${#__fv_s} > __fv_w )) && __fv_s="${__fv_s:0:__fv_w-1}…"
  printf -v __fv_out '%s%*s' "$__fv_s" $((__fv_w - ${#__fv_s})) ''
}
__ui_rfitv() {  # var texto largura (alinhado à direita)
  local -n __rv_out=$1
  local __rv_s=$2 __rv_w=$3
  (( ${#__rv_s} > __rv_w )) && __rv_s="${__rv_s:0:__rv_w}"
  printf -v __rv_out '%*s%s' $((__rv_w - ${#__rv_s})) '' "$__rv_s"
}
__ui_centerv() {  # var texto largura
  local -n __cv_out=$1
  local __cv_s=$2 __cv_w=$3 __cv_l
  (( ${#__cv_s} > __cv_w )) && __cv_s="${__cv_s:0:__cv_w}"
  __cv_l=$(( (__cv_w - ${#__cv_s}) / 2 ))
  printf -v __cv_out '%*s%s%*s' "$__cv_l" '' "$__cv_s" $((__cv_w - ${#__cv_s} - __cv_l)) ''
}
__ui_repv() {  # var caractere vezes
  local -n __pv_out=$1
  local __pv_t
  if (( $3 > 0 )); then printf -v __pv_t '%*s' "$3" ''; __pv_out=${__pv_t// /$2}; else __pv_out=""; fi
}
__ui_durv() {  # var segundos
  local -n __dv_out=$1
  if (( $2 < 60 )); then printf -v __dv_out '%ds' "$2"; else printf -v __dv_out '%dm%02ds' $(($2 / 60)) $(($2 % 60)); fi
}

__ui_slug() {
  local s
  s=$(printf '%s' "$1" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null || printf '%s' "$1")
  s=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')
  s=${s#-}; s=${s%-}
  printf '%s' "${s:-etapa}"
}

# ───────────────────────────── mensagens soltas ─────────────────────────────

ui_info()  { printf '  %s%s%s %s\n' "$C_INFO" "$T_ICON_INFO" "$C_RESET" "$*"; }
ui_warn()  { printf '  %s%s %s%s\n' "$C_WARN" "!" "$*" "$C_RESET"; }
ui_error() { printf '  %s%s %s%s\n' "$C_ERR" "$T_ICON_FAIL" "$*" "$C_RESET" >&2; }

# ───────────────────────────── perguntas ────────────────────────────────────
# Só antes do plano (as etapas nunca pedem input). Lê de /dev/tty: funciona no `curl | bash`.

ui_can_ask() { { exec 3</dev/tty; } 2>/dev/null && exec 3<&-; }

ui_ask() {  # variável "pergunta" [padrão] [regex] -> Enter aceita o padrão; vazio sem padrão = pular
  local -n __ask_out=$1
  local q=$2 def=${3:-} re=${4:-} ans tries=0
  while (( tries++ < 3 )); do
    printf '  %s?%s %s%s%s: ' "$C_ACCENT" "$C_RESET" "$q" "${def:+ ${C_MUTED}[$def]}" "$C_RESET" >/dev/tty
    IFS= read -r ans </dev/tty || { printf '\n' >/dev/tty; __ask_out=""; return 1; }
    ans=${ans:-$def}
    if [[ -z "$ans" || -z "$re" || "$ans" =~ $re ]]; then __ask_out=$ans; return 0; fi
    printf '    %sValor inválido, tente de novo.%s\n' "$C_WARN" "$C_RESET" >/dev/tty
  done
  __ask_out=""; return 1
}

ui_header() {
  local w line sub
  w=$(( UI_COLS - 4 )); (( w > 64 )) && w=64
  line=$(__ui_repeat "${T_BOX[5]}" "$w")
  sub="$__UI_OS · tema $UI_THEME · $UI_TOTAL etapas"
  printf '\n  %s%s%s%s%s\n' "$C_ACCENT" "${T_BOX[0]}" "$line" "${T_BOX[1]}" "$C_RESET"
  printf '  %s%s%s  %s%s%s%s %s%s%s\n' "$C_ACCENT" "${T_BOX[4]}" "$C_RESET" \
    "$C_BOLD$C_TEXT" "$(__ui_fit "$UI_TITLE" $((w - 3)))" "$C_RESET" "" "$C_ACCENT" "${T_BOX[4]}" "$C_RESET"
  printf '  %s%s%s  %s%s%s %s%s%s\n' "$C_ACCENT" "${T_BOX[4]}" "$C_RESET" \
    "$C_MUTED" "$(__ui_fit "$sub" $((w - 3)))" "$C_RESET" "$C_ACCENT" "${T_BOX[4]}" "$C_RESET"
  printf '  %s%s%s%s%s\n' "$C_ACCENT" "${T_BOX[2]}" "$line" "${T_BOX[3]}" "$C_RESET"
}

# ───────────────────────────── plano de etapas ──────────────────────────────

plan_section() {
  __PLAN_KIND+=(section) __PLAN_LABEL+=("$1") __PLAN_CMD+=("") __PLAN_CHECK+=("")
}

plan_step() {
  local check="" label cmd
  if [[ "${1:-}" == --check ]]; then check=$2; shift 2; fi
  label=$1; shift
  (( $# > 0 )) || { ui_error "plan_step '$label' sem comando"; return 1; }
  printf -v cmd '%s\x1f' "$@"
  __PLAN_KIND+=(step) __PLAN_LABEL+=("$label") __PLAN_CMD+=("${cmd%$'\x1f'}") __PLAN_CHECK+=("$check")
  UI_TOTAL=$((UI_TOTAL + 1))
}

__ui_section_line() {
  local w=$(( UI_COLS - 8 - ${#1} ))
  (( w > 40 )) && w=40
  printf '\n  %s%s %s%s %s%s%s\n' "$C_ACCENT$C_BOLD" "$T_ICON_SECTION" "$1" "$C_RESET" \
    "$C_MUTED" "$(__ui_repeat "${T_BOX[5]}" "$w")" "$C_RESET"
}

# Layout da linha em execução: "  ⠹ rótulo  [ 3/12] ━━━━──── 25%   4s"
__ui_draw_running() {
  local label=$1 frame=$2 elapsed=$3 bw=16 lw pct filled counter
  (( UI_COLS < 70 )) && bw=0
  lw=$(( UI_COLS - 4 - 1 - 7 - 1 - bw - 1 - 4 - 2 - 6 - 1 ))
  pct=$(( (UI_CURRENT - 1) * 100 / UI_TOTAL ))
  filled=$(( bw * (UI_CURRENT - 1) / UI_TOTAL ))
  printf -v counter '[%*d/%d]' "${#UI_TOTAL}" "$UI_CURRENT" "$UI_TOTAL"
  (( UI_TTY )) && printf '\r\033[K'
  printf '  %s%s%s %s %s%s%s' "$C_ACCENT" "$frame" "$C_RESET" \
    "$C_TEXT$(__ui_fit "$label" "$lw")$C_RESET" "$C_MUTED" "$counter" "$C_RESET"
  if (( bw > 0 )); then
    printf ' %s%s%s%s%s' "$C_ACCENT" "$(__ui_repeat "$T_BAR_FULL" "$filled")" \
      "$C_MUTED" "$(__ui_repeat "$T_BAR_EMPTY" $((bw - filled)))" "$C_RESET"
  fi
  printf ' %s%3d%%%s  %s%6s%s' "$C_INFO" "$pct" "$C_RESET" "$C_MUTED" "$(__ui_duration "$elapsed")" "$C_RESET"
}

__ui_draw_result() {  # icone cor rótulo status
  local lw=$(( UI_COLS - 4 - 22 ))
  if (( UI_TTY )); then printf '\r\033[K'; fi
  printf '  %s%s%s %s %s%s%s\n' "$2" "$1" "$C_RESET" "$(__ui_fit "$3" "$lw")" "$C_MUTED" "$4" "$C_RESET"
}

__ui_write_fail_log() {  # rótulo comando rc duração saida_tmp -> caminho do log
  local file os
  mkdir -p "$UI_LOG_DIR"
  printf -v file '%s/%02d-%s.txt' "$UI_LOG_DIR" "$UI_CURRENT" "$(__ui_slug "$1")"
  os=$( (. /etc/os-release 2>/dev/null && printf '%s' "$PRETTY_NAME") || echo desconhecido)
  {
    printf 'Etapa:           %s\n' "$1"
    printf 'Comando:         %s\n' "${2//$'\x1f'/ }"
    printf 'Código de saída: %s\n' "$3"
    printf 'Duração:         %s\n' "$(__ui_duration "$4")"
    printf 'Data:            %s\n' "$(date -Iseconds)"
    printf 'Sistema:         %s (%s)\n' "$os" "$(uname -m)"
    printf '%s\n' '──────────────────────── saída ────────────────────────'
    cat "$5"
  } >"$file"
  printf '%s' "$file"
}

# Motivo curto de uma falha, nesta ordem de preferência (últimas 30 linhas da saída):
#   1. a última linha com cara de erro (E:, error, erro, falh, not found, denied, unable...)
#   2. o comando que falhou, informado pelo trap ("[setup] falhou (código N) na linha L: cmd")
#   3. a última linha não vazia · 4. "código N"
__ui_fail_reason() {  # arquivo_de_saida código -> imprime o motivo
  local line err="" cmd="" last="" re='(^E:|[Ee]rror|ERRO|[Ee]rro[: ]|[Ff]alh|[Ff]ail|not found|denied|[Uu]nable|No such|cannot|could not)'
  while IFS= read -r line; do
    line=${line//$'\r'/}
    line=${line#"${line%%[![:space:]]*}"}
    [[ -z "$line" ]] && continue
    if [[ "$line" == "[setup] "* ]]; then cmd="falhou: ${line#*: }"; continue; fi
    last=$line
    [[ "$line" =~ $re ]] && err=$line
  done < <(tail -n 30 "$1" 2>/dev/null)
  printf '%s' "${err:-${cmd:-${last:-código $2}}}"
}

# Relata o resultado de uma etapa no modo clássico (no painel, o próximo quadro mostra)
__ui_report() {  # tipo rótulo detalhe
  [[ "$UI_MODE" == panel ]] && return 0
  if (( UI_TTY )); then
    case $1 in
      skip)    __ui_draw_result "$T_ICON_SKIP" "$C_MUTED" "$C_MUTED$2" "já ok" ;;
      pending) __ui_draw_result "$T_ICON_PENDING" "$C_WARN" "$2" "pendente" ;;
      ok)      __ui_draw_result "$T_ICON_OK" "$C_OK" "$2" "$3" ;;
      fail)    __ui_draw_result "$T_ICON_FAIL" "$C_ERR" "$C_ERR$2" "falhou ($3)" ;;
    esac
  else
    case $1 in
      skip)    printf '  [%d/%d] %s ... já ok\n' "$UI_CURRENT" "$UI_TOTAL" "$2" ;;
      pending) printf '  [%d/%d] %s ... pendente\n' "$UI_CURRENT" "$UI_TOTAL" "$2" ;;
      ok)      printf 'ok (%s)\n' "$3" ;;
      fail)    printf 'FALHOU (%s)\n' "$3" ;;
    esac
  fi
}

__ui_run_step() {  # índice rótulo comando check
  local j=$1 label=$2 cmdstr=$3 checkstr=$4 tmp pid rc start i=0 log dur
  local -a cmd check
  UI_CURRENT=$((j + 1))
  IFS=$'\x1f' read -r -a cmd <<<"$cmdstr"
  __ST_STATUS[j]=run
  [[ "$UI_MODE" == panel ]] && __ui_panel_draw "${T_SPINNER[0]}" 0

  if [[ -n "$checkstr" ]]; then
    read -r -a check <<<"$checkstr"
    if ( set -uo pipefail; "${check[@]}" ) </dev/null >/dev/null 2>&1; then
      UI_SKIP+=("$label") __ST_STATUS[j]=skip
      __ui_report skip "$label"
      return 0
    fi
  fi

  if (( UI_DRY_RUN )); then
    UI_PENDING+=("$label") __ST_STATUS[j]=pending
    __ui_report pending "$label"
    return 0
  fi

  tmp=$(mktemp)
  start=$SECONDS
  (
    set -Eeuo pipefail
    trap 'echo "[setup] falhou (código $?) na linha $LINENO: $BASH_COMMAND" >&2' ERR
    "${cmd[@]}"
  ) </dev/null >"$tmp" 2>&1 &
  pid=$!
  __UI_CHILD=$pid

  if [[ "$UI_MODE" == panel ]]; then
    while kill -0 "$pid" 2>/dev/null; do
      __ui_panel_draw "${T_SPINNER[i++ % ${#T_SPINNER[@]}]}" $((SECONDS - start))
      sleep 0.1
    done
  elif (( UI_TTY )); then
    printf '\033[?25l'
    while kill -0 "$pid" 2>/dev/null; do
      __ui_draw_running "$label" "${T_SPINNER[i++ % ${#T_SPINNER[@]}]}" $((SECONDS - start))
      sleep 0.1
    done
  else
    printf '  [%d/%d] %s ... ' "$UI_CURRENT" "$UI_TOTAL" "$label"
  fi
  wait "$pid"; rc=$?
  __UI_CHILD=""
  (( __UI_INTERRUPTED )) && rc=130
  dur=$((SECONDS - start))
  __ST_DUR[j]=$dur

  if (( rc == 0 )); then
    UI_OK+=("$label") UI_OK_TIME+=("$dur") __ST_STATUS[j]=ok
    __ui_report ok "$label" "$(__ui_duration "$dur")"
  else
    log=$(__ui_write_fail_log "$label" "$cmdstr" "$rc" "$dur" "$tmp")
    UI_FAIL+=("$label") UI_FAIL_LOG+=("$log") UI_FAIL_RC+=("$rc") __ST_STATUS[j]=fail
    UI_FAIL_REASON+=("$( (( rc == 130 )) && echo "interrompida" || __ui_fail_reason "$tmp" "$rc")")
    __ui_report fail "$label" "código $rc"
  fi
  rm -f "$tmp"
}

# Monta o índice etapa → seção a partir do plano registrado pelos módulos
__ui_index() {
  local i s=-1 j=0
  __SEC_NAME=() __SEC_FROM=() __SEC_TO=() __ST_LABEL=() __ST_SEC=() __ST_STATUS=() __ST_DUR=()
  for i in "${!__PLAN_KIND[@]}"; do
    if [[ "${__PLAN_KIND[i]}" == section ]]; then
      (( s >= 0 )) && __SEC_TO[s]=$j
      s=$((s + 1)); __SEC_NAME[s]=${__PLAN_LABEL[i]}; __SEC_FROM[s]=$j
    else
      if (( s < 0 )); then s=0; __SEC_NAME[0]="Geral"; __SEC_FROM[0]=0; fi
      __ST_LABEL[j]=${__PLAN_LABEL[i]} __ST_SEC[j]=$s __ST_STATUS[j]=todo __ST_DUR[j]=0
      j=$((j + 1))
    fi
  done
  (( s >= 0 )) && __SEC_TO[s]=$j
  return 0
}

# Painel só em terminal interativo, com espaço suficiente e fora do --dry-run (que é um relatório)
__ui_choose_mode() {
  UI_MODE=classic
  [[ "${SETUP_UI:-panel}" == classic ]] && return 0
  (( UI_TTY && ! UI_DRY_RUN )) || return 0
  __ui_measure
  (( UI_REAL_COLS >= 74 && UI_ROWS >= 22 )) && UI_MODE=panel
  return 0
}

ui_run_plan() {
  local i j=0
  __ui_index
  __ui_choose_mode
  [[ "$UI_MODE" == panel ]] && __ui_panel_enter
  for i in "${!__PLAN_KIND[@]}"; do
    (( __UI_INTERRUPTED )) && break
    if [[ "${__PLAN_KIND[i]}" == section ]]; then
      [[ "$UI_MODE" == panel ]] || __ui_section_line "${__PLAN_LABEL[i]}"
    else
      __ui_run_step "$j" "${__PLAN_LABEL[i]}" "${__PLAN_CMD[i]}" "${__PLAN_CHECK[i]}"
      j=$((j + 1))
    fi
  done
  [[ "$UI_MODE" == panel ]] && __ui_panel_leave
  return 0
}

# ───────────────────────────── painel (tela cheia) ──────────────────────────
# Layout (mín. 74×22):
#   título em destaque ·························································· mm:ss
#   SEÇÕES (30 col.)                AGORA / A SEGUIR / FALHAS
#   barra geral · n/N · %   |   decorrido · restante ~        Ctrl+C interrompe

__ui_panel_enter() {
  __UI_ALT=1
  printf '\033[?1049h\033[?25l\033[H\033[2J'   # tela alternativa (como htop), sem cursor
  trap '__ui_measure; printf "\033[2J"' WINCH
}

__ui_panel_leave() {
  trap - WINCH
  printf '\033[?1049l\033[?25h'
  __UI_ALT=0
}

__ui_section_state() {  # var seção índice_atual -> done | fail | run | todo
  local -n __ss_out=$1
  local k=$2 j=$3 y
  if (( j >= __SEC_TO[k] )); then
    __ss_out=done
    for ((y = __SEC_FROM[k]; y < __SEC_TO[k]; y++)); do [[ "${__ST_STATUS[y]}" == fail ]] && __ss_out=fail; done
  elif (( j >= __SEC_FROM[k] )); then __ss_out=run
  else __ss_out=todo; fi
}

__ui_panel_draw() {  # quadro_do_spinner segundos_na_etapa
  local spin=$1 el=$2 W=$UI_COLS j=$((UI_CURRENT - 1)) t=$((SECONDS - __UI_START))
  local RW=$((UI_COLS - 34)) k y n d st x z clk cur_sec=${__ST_SEC[$((UI_CURRENT - 1))]:-0}
  local -a L=() left=() right=()

  printf -v clk '%02d:%02d ' $((t / 60)) $((t % 60))
  __ui_fitv x " $UI_TITLE  ·  $__UI_OS  ·  tema $UI_THEME" $((W - ${#clk}))
  L+=("$C_BAR$x$clk$C_RESET" "")

  # Coluna esquerda: seções (janela que acompanha a seção atual se houver mais de 13)
  __ui_fitv x "  SEÇÕES" 30; left+=("$C_MUTED$C_BOLD$x$C_RESET")
  local first=0; (( cur_sec > 12 )) && first=$((cur_sec - 12))
  for ((k = first; k < ${#__SEC_NAME[@]} && ${#left[@]} < 14; k++)); do
    n=$((__SEC_TO[k] - __SEC_FROM[k])); d=$((j - __SEC_FROM[k]))
    (( d < 0 )) && d=0; (( d > n )) && d=$n
    __ui_section_state st "$k" "$j"
    __ui_fitv x "${__SEC_NAME[k]}" 20; __ui_rfitv z "$d/$n" 5
    case $st in
      done) left+=("  $C_OK$T_ICON_OK$C_RESET $x$C_MUTED$z$C_RESET ") ;;
      fail) left+=("  $C_ERR$T_ICON_FAIL$C_RESET $x$C_ERR$z$C_RESET ") ;;
      run)  left+=("  $C_ACCENT$C_BOLD$T_ICON_INFO $x$z$C_RESET ") ;;
      *)    left+=("  $C_MUTED$T_ICON_PENDING $x$z$C_RESET ") ;;
    esac
  done

  # Coluna direita: agora, a seguir, falhas
  right+=("$C_MUTED${C_BOLD}AGORA$C_RESET")
  __ui_fitv x "${__ST_LABEL[j]}" $((RW - 2)); right+=("$C_ACCENT$spin$C_RESET $C_BOLD$x$C_RESET")
  __ui_durv z "$el"
  __ui_fitv x "${__SEC_NAME[cur_sec]} · etapa $UI_CURRENT de $UI_TOTAL · $z" "$RW"; right+=("$C_MUTED$x$C_RESET")
  right+=("" "$C_MUTED${C_BOLD}A SEGUIR$C_RESET")
  for y in 1 2 3; do
    if (( j + y < UI_TOTAL )); then __ui_fitv x "${__ST_LABEL[j + y]}" $((RW - 2)); right+=("$C_MUTED· $x$C_RESET"); else right+=(""); fi
  done
  right+=("")
  local nf=${#UI_FAIL[@]}
  if (( nf )); then
    right+=("$C_MUTED${C_BOLD}FALHAS $C_ERR$nf$C_RESET")
    for ((y = (nf > 4 ? nf - 4 : 0); y < nf; y++)); do
      __ui_fitv x "${UI_FAIL[y]}" 22; __ui_fitv z "${UI_FAIL_REASON[y]}" $((RW - 25))
      right+=("$C_ERR$T_ICON_FAIL $x$C_RESET $C_MUTED$z$C_RESET")
    done
  else
    right+=("$C_MUTED${C_BOLD}FALHAS ${C_RESET}${C_MUTED}0$C_RESET" "${C_MUTED}nenhuma até agora$C_RESET")
  fi

  for ((y = 0; y < 14; y++)); do
    x=${left[y]:-}; [[ -z "$x" ]] && printf -v x '%30s' ''
    L+=("$x  ${right[y]:-}")
  done
  L+=("" "")

  # Barra geral e tempos (estimativa: média das etapas concluídas × restantes)
  local bw=$((W - 24)) filled full empty pct rem
  filled=$((bw * j / UI_TOTAL)); pct=$((j * 100 / UI_TOTAL))
  __ui_repv full "$T_BAR_FULL" "$filled"; __ui_repv empty "$T_BAR_EMPTY" $((bw - filled))
  printf -v x '%2d/%d · %2d%%' "$j" "$UI_TOTAL" "$pct"
  L+=("  $C_ACCENT$full$C_MUTED$empty$C_RESET  $C_INFO$x$C_RESET")
  __ui_durv z "$t"
  if (( j > 0 )); then rem=$((t * (UI_TOTAL - j) / j)); __ui_durv rem "$rem"; rem="~$rem"; else rem="calculando"; fi
  __ui_fitv x "decorrido $z · restante $rem" $((W - 21)); __ui_rfitv z "Ctrl+C interrompe" 17
  L+=("  $C_MUTED$x$z$C_RESET")

  local out=$'\033[H'
  for ((y = 0; y < ${#L[@]}; y++)); do
    out+="${L[y]}"$'\033[K'
    (( y < ${#L[@]} - 1 )) && out+=$'\n'
  done
  printf '%s\033[J' "$out"
}

# ───────────────────────────── resumo ───────────────────────────────────────

# Resumo do painel: placar em cartões + falhas com motivo + tempo por seção.
# Impresso no terminal normal (depois de sair da tela do painel), então fica no histórico.
__ui_panel_summary() {
  local t=$((SECONDS - __UI_START)) dur x y z k st c i bw=15 line
  local -a vals labels cols
  __ui_durv dur "$t"
  printf '\n  %s%s Resumo%s %s%s%s\n' "$C_ACCENT$C_BOLD" "$T_ICON_SECTION" "$C_RESET" "$C_MUTED" \
    "$( (( __UI_INTERRUPTED )) && echo "· interrompido em $dur" || echo "· concluído em $dur")" "$C_RESET"

  vals=("${#UI_OK[@]}" "${#UI_SKIP[@]}" "${#UI_FAIL[@]}" "$dur")
  labels=("instalados" "já estavam ok" "falharam" "duração")
  cols=("$C_OK" "$C_MUTED" "$C_ERR" "$C_INFO")
  __ui_repv line "${T_BOX[5]}" "$bw"
  x=" "; for i in 0 1 2 3; do x+="${cols[i]}${T_BOX[0]}$line${T_BOX[1]}$C_RESET "; done; printf '%s\n' "$x"
  x=" "; for i in 0 1 2 3; do __ui_centerv z "${vals[i]}" "$bw"; x+="${cols[i]}${T_BOX[4]}$C_BOLD$z$C_RESET${cols[i]}${T_BOX[4]}$C_RESET "; done; printf '%s\n' "$x"
  x=" "; for i in 0 1 2 3; do __ui_centerv z "${labels[i]}" "$bw"; x+="${cols[i]}${T_BOX[4]}$C_RESET$C_MUTED$z$C_RESET${cols[i]}${T_BOX[4]}$C_RESET "; done; printf '%s\n' "$x"
  x=" "; for i in 0 1 2 3; do x+="${cols[i]}${T_BOX[2]}$line${T_BOX[3]}$C_RESET "; done; printf '%s\n' "$x"

  if (( ${#UI_FAIL[@]} )); then
    __ui_fitv x "FALHAS" 29
    printf '\n  %s%sMOTIVO%s\n' "$C_MUTED$C_BOLD" "$x" "$C_RESET"
    for i in "${!UI_FAIL[@]}"; do
      __ui_fitv x "${UI_FAIL[i]}" 26; __ui_fitv y "${UI_FAIL_REASON[i]}" $((UI_COLS - 33))
      printf '  %s%s %s%s %s\n' "$C_ERR" "$T_ICON_FAIL" "$x" "$C_RESET" "$y"
      __ui_fitv y "$(basename "${UI_FAIL_LOG[i]}")" $((UI_COLS - 8))
      printf '    %s↳ %s%s\n' "$C_MUTED" "$y" "$C_RESET"
    done
  fi

  printf '\n  %sPOR SEÇÃO%s\n' "$C_MUTED$C_BOLD" "$C_RESET"
  local nsec=${#__SEC_NAME[@]} half=$(( (${#__SEC_NAME[@]} + 1) / 2 )) last=$((UI_CURRENT - 1))
  (( __UI_INTERRUPTED )) || last=$UI_TOTAL
  for ((k = 0; k < half; k++)); do
    x="  "
    for c in "$k" $((k + half)); do
      (( c < nsec )) || continue
      __ui_section_state st "$c" "$last"
      z=0; for ((i = __SEC_FROM[c]; i < __SEC_TO[c]; i++)); do z=$((z + ${__ST_DUR[i]:-0})); done
      __ui_durv z "$z"; __ui_fitv y "${__SEC_NAME[c]}" 22; __ui_rfitv z "$z" 7
      case $st in
        done) x+="$C_OK$T_ICON_OK$C_RESET $y$C_MUTED$z$C_RESET    " ;;
        fail) x+="$C_ERR$T_ICON_FAIL$C_RESET $y$C_MUTED$z$C_RESET    " ;;
        *)    x+="$C_MUTED$T_ICON_PENDING $y$z$C_RESET    " ;;
      esac
    done
    printf '%s\n' "$x"
  done

  if (( ${#UI_FAIL[@]} )); then
    __ui_write_summary_file
    printf '\n  %sLogs desta execução:%s %s\n' "$C_MUTED" "$C_RESET" "$(__ui_tilde "$UI_LOG_DIR")"
  fi
  if (( __UI_INTERRUPTED )); then
    printf '\n  %s! Instalação interrompida — %d etapa(s) não executada(s).%s\n' \
      "$C_WARN" $((UI_TOTAL - UI_CURRENT)) "$C_RESET"
  fi
  printf '\n'
  (( __UI_INTERRUPTED )) && return 130
  (( ${#UI_FAIL[@]} )) && return 1
  return 0
}

ui_summary() {
  [[ "$UI_MODE" == panel ]] && { __ui_panel_summary; return $?; }
  local i total_time w
  total_time=$(__ui_duration $((SECONDS - __UI_START)))
  w=$(( UI_COLS - 14 )); (( w > 50 )) && w=50

  printf '\n  %s%s Resumo %s%s\n' "$C_ACCENT$C_BOLD" "$T_ICON_SECTION" \
    "$C_RESET$C_MUTED$(__ui_repeat "${T_BOX[5]}" "$w")" "$C_RESET"
  if (( UI_DRY_RUN )); then
    printf '  %s%s %d pendentes%s   %s%s %d já ok%s   %s(simulação: nada foi alterado)%s\n' \
      "$C_WARN" "$T_ICON_PENDING" "${#UI_PENDING[@]}" "$C_RESET" \
      "$C_MUTED" "$T_ICON_SKIP" "${#UI_SKIP[@]}" "$C_RESET" "$C_MUTED" "$C_RESET"
  else
    printf '  %s%s %d instalados%s   %s%s %d já ok%s   %s%s %d falharam%s   %s%s%s\n' \
      "$C_OK" "$T_ICON_OK" "${#UI_OK[@]}" "$C_RESET" \
      "$C_MUTED" "$T_ICON_SKIP" "${#UI_SKIP[@]}" "$C_RESET" \
      "$C_ERR" "$T_ICON_FAIL" "${#UI_FAIL[@]}" "$C_RESET" \
      "$C_MUTED" "$total_time" "$C_RESET"
  fi

  local pending=$(( UI_TOTAL - UI_CURRENT ))

  if (( UI_DRY_RUN )); then
    if (( ${#UI_PENDING[@]} )); then
      printf '\n  %sPendentes%s\n' "$C_BOLD" "$C_RESET"
      for i in "${!UI_PENDING[@]}"; do
        printf '    %s%s%s %s\n' "$C_WARN" "$T_ICON_PENDING" "$C_RESET" "${UI_PENDING[i]}"
      done
    fi
  fi

  if (( ${#UI_OK[@]} )); then
    printf '\n  %sInstalados%s\n' "$C_BOLD" "$C_RESET"
    for i in "${!UI_OK[@]}"; do
      printf '    %s%s%s %s\n' "$C_OK" "$T_ICON_OK" "$C_RESET" "${UI_OK[i]}"
    done
  fi
  if (( ${#UI_SKIP[@]} )); then
    printf '\n  %sJá estavam ok%s\n' "$C_BOLD" "$C_RESET"
    for i in "${!UI_SKIP[@]}"; do
      printf '    %s%s %s%s\n' "$C_MUTED" "$T_ICON_SKIP" "${UI_SKIP[i]}" "$C_RESET"
    done
  fi
  if (( ${#UI_FAIL[@]} )); then
    printf '\n  %sFalharam%s\n' "$C_BOLD$C_ERR" "$C_RESET"
    for i in "${!UI_FAIL[@]}"; do
      printf '    %s%s %s%s %s→ %s%s\n' "$C_ERR" "$T_ICON_FAIL" "${UI_FAIL[i]}" "$C_RESET" \
        "$C_MUTED" "$(__ui_tilde "${UI_FAIL_LOG[i]}")" "$C_RESET"
    done
    __ui_write_summary_file
    printf '\n  %sLogs desta execução:%s %s\n' "$C_MUTED" "$C_RESET" "$(__ui_tilde "$UI_LOG_DIR")"
  fi
  if (( __UI_INTERRUPTED )); then
    printf '\n  %s! Instalação interrompida — %d etapa(s) não executada(s).%s\n' \
      "$C_WARN" "$pending" "$C_RESET"
  fi
  printf '\n'

  (( __UI_INTERRUPTED )) && return 130
  (( ${#UI_FAIL[@]} )) && return 1
  return 0
}

__ui_write_summary_file() {
  local i
  {
    printf 'Execução: %s\n\n' "$UI_RUN_ID"
    printf 'Instalados (%d):\n' "${#UI_OK[@]}"; for i in "${!UI_OK[@]}"; do printf '  + %s\n' "${UI_OK[i]}"; done
    printf '\nJá ok (%d):\n' "${#UI_SKIP[@]}"; for i in "${!UI_SKIP[@]}"; do printf '  = %s\n' "${UI_SKIP[i]}"; done
    printf '\nFalharam (%d):\n' "${#UI_FAIL[@]}"
    for i in "${!UI_FAIL[@]}"; do
      printf '  x %s (código %s) -> %s\n' "${UI_FAIL[i]}" "${UI_FAIL_RC[i]}" "$(basename "${UI_FAIL_LOG[i]}")"
    done
  } >"$UI_LOG_DIR/resumo.txt"
}
