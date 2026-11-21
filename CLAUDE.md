# Regras do repositório `ubuntu-setup`

Repositório para configurar um Ubuntu do zero com **um comando** (bootstrap em uma linha).
Idioma de código-comentários, docs e mensagens ao usuário: **português (pt-BR)**.

Detalhes e exemplos: [docs/padroes-shell.md](docs/padroes-shell.md).
Histórico de decisões: [docs/decisoes.md](docs/decisoes.md).

## Fluxo de trabalho

- Toda decisão tomada em conversa é registrada em `docs/decisoes.md` (data, decisão, motivo).
- Mudou comportamento ou uso → atualizar o `README.md` no mesmo passo.
- Antes de concluir qualquer mudança, rodar `scripts/check.sh` (sintaxe, shellcheck, varredura de dados sensíveis).

## Regras obrigatórias para scripts `.sh`

1. **Reprodutível em Ubuntu**
   - Alvo: Ubuntu LTS (24.04 e 26.04). Nada de comandos específicos de outra distro.
   - Sempre `#!/usr/bin/env bash`; pode usar recursos do bash 5.
   - Sem caminhos fixos de usuário (`/home/fulano`): use `$HOME`, `$XDG_*`.
   - Tudo não interativo: `DEBIAN_FRONTEND=noninteractive`, `apt-get -y`, stdin vem de `/dev/null`.
   - Fontes externas (repos apt, chaves GPG, binários) com URL oficial e chave em `/etc/apt/keyrings/`.

2. **Idempotente**
   - Rodar duas vezes seguidas deve dar o mesmo resultado; na segunda, tudo aparece como "já ok".
   - Toda etapa tem um `--check` (detecta se já está feito) ou é naturalmente idempotente.
   - Nunca anexar às cegas em arquivo (`>>`): use `ensure_line`. Antes de sobrescrever config, fazer backup.
   - Nunca `rm -rf` em caminho montado a partir de variável sem validar que ela não está vazia.

3. **Sem dados pessoais ou sensíveis**
   - Proibido versionar: nome, e-mail, usuário, hostname, IPs internos, tokens, senhas, chaves SSH/GPG.
   - Valores pessoais (usuário e e-mail do GitHub) são perguntados no início do `install.sh`, antes do plano,
     com `ui_ask` (lê de `/dev/tty`), ou vêm de variáveis de ambiente. Nunca ficam gravados no repo.
   - Logs ficam fora do repo (`~/.local/state/ubuntu-setup/logs/`) e caminhos exibidos usam `~`.

4. **Erros não param a instalação**
   - Cada item é uma etapa registrada com `plan_step`; executa em subshell isolado com `set -Eeuo pipefail`.
   - Falha de uma etapa é registrada e a instalação segue. No fim: resumo de instalado / já ok / falhou.
   - A saída de cada etapa vai para arquivo temporário; se falhar, vira um `.txt` em logs.
   - Etapas **não** escrevem direto no terminal e **não** pedem input. A interface é só `lib/ui.sh`.
   - Root: usar `as_root` (usa `sudo -n`; o sudo é validado uma vez no início).

## Estrutura

```
install.sh            # entrada: bootstrap (clona o repo se necessário) + executa módulos
lib/ui.sh             # interface: temas, progresso, resumo, logs de falha
lib/themes.sh         # paletas de cores e estilos
lib/helpers.sh        # helpers idempotentes (apt_install, pkg_installed, ensure_line, as_root...)
modules/NN-nome.sh    # módulos: definem funções step_* e registram etapas com plan_step
assets/               # arquivos de terceiros com licença que permite redistribuir (sempre com CREDITS.md)
scripts/              # ferramentas do repo (check, demo, preview de temas)
docs/                 # padrões e decisões
```

- Origem de apps: repositório apt oficial > `.deb` oficial > tarball/instalador oficial verificado > apt do Ubuntu.
  Use os mesmos caminhos de chave/arquivo que o fornecedor (evita conflito de `Signed-By`).
- PATH e inicializações de shell: `shell_snippet nome '...'` (vai para `~/.config/ubuntu-setup/shell.d/`).
- Validar sem alterar o sistema: `./install.sh --dry-run`.
