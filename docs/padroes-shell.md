# Padrões para scripts shell

Resumo obrigatório em [CLAUDE.md](../CLAUDE.md). Aqui ficam o porquê e os exemplos.

## 1. Cabeçalho e modo estrito

```bash
#!/usr/bin/env bash
# modules/20-exemplo.sh — o que este arquivo faz, em uma linha.
```

- **Entrypoints** (`install.sh`, `scripts/*.sh`): `set -uo pipefail`. Não usamos `set -e` no nível
  de cima, porque uma falha não pode derrubar a instalação inteira.
- **Etapas**: o `lib/ui.sh` executa cada etapa em um subshell com `set -Eeuo pipefail`.
  Qualquer comando que falhe dentro da etapa falha **só aquela etapa**.
- Módulos e libs são carregados com `source` e não têm efeito colateral ao serem carregados:
  só definem funções e registram etapas.

## 2. Anatomia de um módulo

```bash
# modules/20-dev.sh

step_install_ripgrep() { apt_install ripgrep; }

plan_section "Ferramentas de desenvolvimento"
plan_step --check "has_cmd rg" "ripgrep" step_install_ripgrep
plan_step --check "pkg_installed jq" "jq" apt_install jq
```

- `plan_section "Título"` agrupa etapas visualmente.
- `plan_step [--check "cmd args"] "Rótulo" comando args...`
  - `--check`: se retornar 0, a etapa é marcada como **já ok** e pulada.
  - O comando pode ser uma função `step_*` ou um helper com argumentos.
- Nomes: `step_*` para etapas, `check_*` para verificações customizadas.

## 3. Idempotência na prática

| Em vez de | Use |
|---|---|
| `echo "x" >> ~/.bashrc` | `ensure_line 'x' "$HOME/.bashrc"` |
| `apt-get install -y pacote` sem checar | `apt_install pacote` (só instala o que falta) |
| `git clone url dir` | `git_sync url dir` (clona ou faz `pull --ff-only`) |
| `cp config ~/.config/app` | `install_file origem destino` (backup `.bak-AAAAMMDD-HHMMSS` se diferente) |
| `mkdir dir` | `mkdir -p dir` |
| `ln -s a b` | `ln -sfn a b` |

Teste de idempotência: rodar `./install.sh` duas vezes; a segunda execução deve mostrar só **já ok**.
Para ver o estado sem alterar nada: `./install.sh --dry-run` (roda só os `--check`).

**Armadilha:** com `pipefail`, `comando | grep -q x` pode dar falso negativo. O `grep -q` sai na primeira
linha, o comando recebe SIGPIPE e o pipe "falha". Compare a saída capturada:
`[[ "$(comando)" == ... ]]`.

## 3.1 Origem de cada app

Prefira, nesta ordem: repositório apt oficial do fornecedor (atualiza com `apt upgrade`) →
`.deb` oficial que cria o próprio repo → tarball/instalador oficial com verificação → apt do Ubuntu.
Ao criar um repo, use **os mesmos caminhos de chave e de arquivo** que o fornecedor documenta (ou
que o pacote cria). `Signed-By` diferente para a mesma URL quebra o `apt update` inteiro.
Chaves sempre pela URL oficial do fornecedor; nada de chave versionada no repo.

## 4. Reprodutibilidade

- Testar em container limpo: `docker run --rm -it -v "$PWD":/repo ubuntu:24.04 bash /repo/install.sh`.
- `apt-get` com `-o DPkg::Lock::Timeout=120` para não falhar se outro apt estiver rodando.
- Repositórios de terceiros: chave em `/etc/apt/keyrings/<nome>.gpg`, source em
  `/etc/apt/sources.list.d/<nome>.sources` com `Signed-By`.
- Nada de `curl ... | sudo bash` de terceiros dentro de etapas. Baixar, verificar, executar.
- Detectar a arquitetura com `dpkg --print-architecture` e a versão com `/etc/os-release`.

## 5. Privacidade

- Nada pessoal no repo. Dados como nome e e-mail do git ficam em:
  `~/.config/ubuntu-setup/local.env` (modelo em `config/local.env.example`).
- Uma etapa que precisa de um dado pessoal ausente **pula com aviso** (falha com mensagem clara),
  sem perguntar interativamente.
- `scripts/check.sh` procura e-mails, chaves privadas, tokens conhecidos e caminhos `/home/<usuario>`.
  O hook `.githooks/pre-commit` roda o check antes de cada commit.
- Logs de falha podem conter caminhos locais e ficam **somente** fora do repo.

## 6. Bootstrap em uma linha

```bash
curl -fsSL https://raw.githubusercontent.com/JulioC354R/ubuntu-setup/main/install.sh | bash
```

- Todo o `install.sh` fica dentro de `main() { ...; }; main "$@"`. O bash só executa depois de
  baixar o arquivo inteiro, o que protege contra download parcial.
- Como o stdin é o próprio script no `curl | bash`, **todas as etapas recebem `</dev/null`**.
  Assim, nenhum comando "come" o resto do script.
- O sudo pede a senha uma vez via `/dev/tty` e fica mantido em segundo plano até o fim.
