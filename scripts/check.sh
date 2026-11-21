#!/usr/bin/env bash
# scripts/check.sh — valida o repo: sintaxe bash, shellcheck (se instalado) e dados sensíveis.
# Usado manualmente e pelo hook .githooks/pre-commit. Sai com 1 se encontrar problema.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
fail=0

mapfile -t sh_files < <(git ls-files --cached --others --exclude-standard -- '*.sh' .githooks/ 2>/dev/null)

echo "› Sintaxe bash"
for f in "${sh_files[@]}"; do
  bash -n "$f" || { echo "  ✘ $f"; fail=1; }
done

echo "› shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -S warning "${sh_files[@]}" || fail=1
else
  echo "  (não instalado — sudo apt install shellcheck)"
fi

echo "› Dados pessoais/sensíveis"
patterns=(
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'   # e-mails
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'               # chaves privadas
  'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}'  # tokens GitHub
  'sk-[A-Za-z0-9_-]{20,}'                            # tokens estilo OpenAI/Anthropic
  'AKIA[0-9A-Z]{16}'                                 # AWS access key
  'xox[baprs]-[A-Za-z0-9-]{10,}'                     # Slack
  '/home/[a-z_][a-z0-9_-]*/'                         # caminhos com nome de usuário
  '(password|passwd|senha|secret|token)[[:space:]]*[:=][[:space:]]*[^[:space:]$"{]+'
)
allow='[A-Za-z0-9._%+-]*@?(example\.(com|org)|exemplo\.com)|noreply@[A-Za-z0-9.-]+|[A-Za-z0-9._%+-]+@users\.noreply\.github\.com'
# Exceções do projeto (uma regex por linha, comentários com #)
if [[ -f .check-allow ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] || allow+="|$line"
  done <.check-allow
fi

mapfile -t all_files < <(git ls-files --cached --others --exclude-standard 2>/dev/null | grep -vxE 'scripts/check.sh|\.check-allow')
for p in "${patterns[@]}"; do
  # Remove só os trechos permitidos e testa de novo o que sobrou da linha
  hits=$(grep -nIEH -e "$p" -- "${all_files[@]}" 2>/dev/null | while IFS= read -r hit; do
    rest=$(sed -E "s/$allow//g" <<<"${hit#*:*:}")
    grep -qE -e "$p" <<<"$rest" && printf '%s\n' "$hit"
  done)
  if [[ -n "$hits" ]]; then
    echo "$hits" | sed 's/^/  ✘ /'
    fail=1
  fi
done

if (( fail )); then echo "✘ Problemas encontrados."; else echo "✔ Tudo certo."; fi
exit "$fail"
