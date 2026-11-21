# ubuntu-setup

Configura um Ubuntu (24.04 / 26.04 LTS) do zero com um comando, de forma **idempotente**, sem
dados pessoais no repositório e com uma interface que mostra o progresso sem despejar logs.

## Instalação em uma linha

```bash
curl -fsSL https://raw.githubusercontent.com/JulioC354R/ubuntu-setup/main/install.sh | bash
```

Com tema:

```bash
curl -fsSL .../install.sh | bash -s -- --theme nord
```

Ou a partir de um clone: `./install.sh --theme dracula`.

Para ver o que já está ok e o que falta, sem alterar nada: `./install.sh --dry-run`.

## O que é instalado

| Seção | Itens |
|---|---|
| Base | teclado US Internacional com cedilha + ABNT2 (Super+Espaço alterna), reparo do dpkg, índice do apt, curl/wget/jq, git, build-essential, zip, `~/.local/bin` no PATH |
| Git e SSH | identidade do Git (usuário e e-mail do GitHub, perguntados no início), branch padrão `main`, chave SSH ed25519 |
| Terminal | btop, GitHub CLI, Kitty ([atalhos](docs/kitty-atalhos.md): splits, tabs, grupos, opacidade 85%) + zsh + Oh My Zsh (plugins) + Oh My Posh (tema if_tea), fonte Meslo Nerd Font |
| Desenvolvimento | Python 3 (venv, pip, pipx), Go, nvm + Node LTS, Bun, Rust, Docker + Compose (logs limitados a 10m × 3 por container), Claude Code |
| Infraestrutura | Terraform, tflint, kubectl, Helm, kustomize, kind, Azure CLI, AWS CLI |
| Aplicativos | Google Chrome, VS Code, Obsidian, Claude Desktop, OBS Studio, RustDesk, GParted, DBeaver |
| Extensões do GNOME | Ajustes (Tweaks), Gerenciador de Extensões, dconf-editor; Blur my Shell, Vitals, Caffeine, Lilypad, Bluetooth Battery Meter, Open Bar + configs |
| Aparência | fastfetch, ícones Papirus-Dark, cursor [Windows 11 Concept](assets/cursors/CREDITS.md) by jepriCreations (dark) |

Mudou algo nas extensões? `scripts/export-gnome.sh` atualiza `config/gnome/extensions.ini` (revise o diff).

Detalhes de origem e atualização: [docs/decisoes.md](docs/decisoes.md) (decisões 005 e 007).

## Painel

Durante a instalação, o terminal mostra um **painel em tela cheia**, no estilo do btop: seções à esquerda,
etapa atual, as próximas e as falhas à direita, barra geral e tempo restante embaixo. No fim, o painel fecha
e um resumo em cartões fica impresso no terminal (instalados, já ok, falhas com o motivo, tempo por seção).

O modo clássico, com uma linha por etapa, é usado automaticamente fora de um terminal interativo, em janelas
menores que 74×22 e no `--dry-run`. Para forçar: `SETUP_UI=classic ./install.sh`.

## Temas

`catppuccin` (padrão) · `dracula` · `nord` · `tokyonight` · `gruvbox` · `mono`

```bash
./install.sh --list-themes      # prévia de todos
scripts/demo.sh gruvbox         # simulação completa (não instala nada)
```

Sem cor: `NO_COLOR=1`. Saída simples, uma linha por etapa: `SETUP_PLAIN=1` (automático quando não é terminal).

## Erros

Uma etapa que falha **não para** a instalação. No final aparece um resumo com o que foi
instalado, o que já estava ok e o que falhou. Cada falha gera um `.txt` com a saída completa em:

```
~/.local/state/ubuntu-setup/logs/<AAAAMMDD-HHMMSS>/NN-etapa.txt
~/.local/state/ubuntu-setup/logs/<AAAAMMDD-HHMMSS>/resumo.txt
```

Código de saída: `0` tudo ok · `1` houve falhas · `130` interrompido.

## Dados pessoais

Nada pessoal é versionado. No início, o instalador pergunta o **usuário e o e-mail do GitHub**, usados na
identidade do Git e no comentário da chave SSH. Enter aceita o valor sugerido: o que o Git já tiver ou, numa
máquina nova, o e-mail anônimo do GitHub (`<id>+<usuário>@users.noreply.github.com`), que não expõe o seu
e-mail real em repositórios públicos. Sem perguntar (automação):

```bash
GIT_USER_NAME=seu-usuario GIT_USER_EMAIL=voce@example.com ./install.sh
```

A chave SSH (`~/.ssh/id_ed25519`) é criada **sem senha**, porque a instalação não pode parar no meio. Depois:

```bash
ssh-keygen -p -f ~/.ssh/id_ed25519                       # pôr uma senha (opcional)
gh auth refresh -s admin:public_key                       # permissão para enviar chaves
gh ssh-key add ~/.ssh/id_ed25519.pub -t "$(hostname)"     # cadastrar no GitHub
```

## Desenvolvimento

```bash
git config core.hooksPath .githooks   # roda scripts/check.sh antes de cada commit
scripts/check.sh                      # sintaxe, shellcheck e varredura de dados sensíveis
```

Regras: [CLAUDE.md](CLAUDE.md) · Padrões: [docs/padroes-shell.md](docs/padroes-shell.md) ·
Decisões: [docs/decisoes.md](docs/decisoes.md)
