# Registro de decisões

Formato: data · decisão · motivo. As mais novas ficam no fim.

## 001 · 2026-11-21 · Bootstrap em uma linha
Instalação via `curl -fsSL .../install.sh | bash`. O `install.sh` clona o repo em
`~/.local/share/ubuntu-setup` (ou usa o checkout local, se for executado de dentro dele).
**Motivo:** montar o ambiente em qualquer máquina nova com um único comando.

## 002 · 2026-11-21 · Regras para scripts
Os scripts devem ser reprodutíveis em Ubuntu LTS e idempotentes, e nenhum dado pessoal ou sensível
pode ser versionado. Ver [CLAUDE.md](../CLAUDE.md) e [padroes-shell.md](padroes-shell.md).
**Motivo:** o repo será público/portátil e deve poder rodar várias vezes com segurança.

## 003 · 2026-11-21 · Interface com temas e progresso
O instalador mostra cabeçalho, seções, spinner, contador `[n/total]`, barra de progresso e tempo
por etapa, sem exibir logs. Temas disponíveis: `catppuccin` (padrão), `dracula`, `nord`, `tokyonight`,
`gruvbox`, `mono`. Escolha via `--theme` ou `SETUP_THEME`. Fallback automático sem cor (`NO_COLOR`,
saída não-TTY) e sem Unicode (locale não UTF-8).
**Motivo:** acompanhar a instalação de forma clara sem poluir o terminal.

## 004 · 2026-11-21 · Falhas não interrompem a instalação
Cada etapa roda isolada. Se uma falha, a instalação segue. O resumo final lista instalados,
os que já estavam ok e as falhas. Cada falha gera
`~/.local/state/ubuntu-setup/logs/<execução>/NN-etapa.txt` (etapa, comando, código de saída,
sistema e saída completa), e cada execução com falhas gera também um `resumo.txt`.
Código de saída: `0` tudo ok · `1` houve falhas · `130` interrompido (Ctrl+C).
**Motivo:** um item quebrado não deve impedir o resto do setup.

## 005 · 2026-11-21 · Apps principais e origem de cada um

| App | Origem | Atualiza por |
|---|---|---|
| Google Chrome | `.deb` oficial (o pacote cria o repo) | apt |
| VS Code | repo apt da Microsoft (`vscode.sources`, chave em `/usr/share/keyrings/microsoft.gpg`) | apt |
| Obsidian | `.deb` da última release no GitHub | o próprio app |
| Claude Desktop | repo apt oficial, com arquivos idênticos aos que o pacote cria; chave baixada da URL oficial (decisão 013) | apt |
| Claude Code | instalador nativo oficial (`claude.ai/install.sh`), baixado e depois executado | o próprio app |
| btop | apt do Ubuntu | apt |
| Docker Engine + Compose | repo apt oficial da Docker; usuário adicionado ao grupo `docker` | apt |
| Python 3 | apt do Ubuntu (`python3-venv`, `pip`, `pipx`, `dev`) | apt |
| Go | tarball oficial em `/usr/local/go`, com sha256 verificado; o check exige a última versão | rodar o setup |
| nvm | clone git na última tag | rodar o setup |
| Node.js | `nvm install lts/*` como default (`SETUP_NODE_VERSION` muda) | rodar o setup |

PATH e inicializações ficam em `~/.config/ubuntu-setup/shell.d/*.sh`, carregados por uma única linha
no `~/.bashrc`, em vez de espalhar linhas pelo arquivo.
**Motivo:** preferir fontes oficiais que se atualizam com `apt upgrade`, sem conflito de `Signed-By`.

## 006 · 2026-11-21 · `--dry-run` e reparo do dpkg
`./install.sh --dry-run` roda só as verificações e lista o que está pendente. A primeira etapa repara
pacotes com configuração interrompida (`dpkg --configure -a`), porque nesse estado o apt recusa
qualquer instalação e todas as etapas falhariam.
**Motivo:** a máquina atual tinha um upgrade interrompido (107 pacotes) que o dry-run revelou.

## 007 · 2026-11-21 · Mais ferramentas; extensões do VS Code fora do setup

| App | Origem | Atualiza por |
|---|---|---|
| GitHub CLI | repo apt oficial (`cli.github.com`), substitui a versão do Ubuntu | apt |
| Rust | `rustup` oficial em `~/.cargo`, sem alterar o `.bashrc` (`--no-modify-path`) | `rustup update` |
| Bun | binário da última release no GitHub, com sha256 verificado, em `~/.bun` (usa `baseline` se a CPU não tiver AVX2) | `bun upgrade` |
| Terraform | repo apt oficial da HashiCorp | apt |
| kubectl | repo `pkgs.k8s.io` da minor estável; rodar o setup de novo migra para uma minor nova | apt + setup |

As extensões do VS Code **não** entram no setup: você as instala pelo Settings Sync ao entrar com o GitHub.
**Motivo:** versões oficiais e atuais; o Settings Sync já resolve as extensões.

## 008 · 2026-11-21 · Cursor Windows 11 Concept (jepriCreations)
O pacote original do Windows (`.cur`/`.ani`) fica versionado em `assets/cursors/`, sem alterações e
com créditos em `CREDITS.md`. A licença do autor permite redistribuir sem cobrança, desde que ele
seja creditado. Na instalação, o `win2xcur` (fixado na 0.2.1, num venv próprio, com o `imagemagick`
do apt) converte as variantes **light** e **dark** para `~/.local/share/icons/W11-Cursors-jepriCreations-*`.
A variante aplicada no GNOME é a `dark`, por escolha sua (`SETUP_CURSOR_VARIANT=light` troca). O tema é refeito
apenas se o sha256 do zip mudar. Testado em containers limpos de Ubuntu 24.04 e 26.04.
**Motivo:** o download exige login no DeviantArt e o autor não oferece versão para Linux.

## 009 · 2026-11-21 · Extensões do GNOME e ícones Papirus
- **Extensões** (de extensions.gnome.org, pela versão do Shell instalado): Blur my Shell, Vitals, Caffeine,
  Lilypad, Bluetooth Battery Meter e Open Bar. As que vêm com o Ubuntu (dock, ding, tiling-assistant...)
  só recebem configuração.
- **Open Bar** não tem versão para o GNOME 50. O setup instala a última versão (49) e mantém
  `disable-extension-version-validation=true`, como você já usa (`SETUP_GNOME_DISABLE_VERSION_VALIDATION=false`
  desliga). Risco: uma extensão incompatível pode quebrar o painel.
- **Configs** em `config/gnome/extensions.ini` e `shell.ini` (formato `dconf load /`). Ficam fora:
  MAC/nome de dispositivos Bluetooth, caminho do wallpaper e chaves de estado interno. Para atualizar:
  `scripts/export-gnome.sh` (filtra essas chaves e falha se encontrar caminho de home, e-mail ou MAC).
- **Papirus**: PPA `papirus/papirus` via `add-apt-repository`, como na documentação oficial, porque o
  arquivo gerado tem a chave embutida e outro arquivo para o mesmo PPA causaria conflito de `Signed-By`.
  O tema aplicado é `Papirus-Dark` (`SETUP_ICON_THEME` troca).
- `scripts/check.sh` aceita exceções explícitas em `.check-allow` (ex.: UUIDs de extensões, que parecem
  e-mails). Só o trecho permitido é removido, então o resto da linha continua sendo verificado.
**Motivo:** reproduzir o desktop atual sem levar dados da máquina para o repo.

## 010 · 2026-11-21 · fastfetch e conversor de cursor temporário
- **fastfetch**: `.deb` oficial da última release no GitHub. O apt do 24.04 não tem o pacote e o do
  26.04 é antigo (2.57 contra 2.71). O check compara com a última release, então rodar o setup de novo atualiza.
- **Conversor de cursor** (substitui parte da 008): `python3-venv`, `imagemagick` e `win2xcur` existem
  só durante a conversão. A etapa compara os pacotes instalados antes e depois e, no fim (mesmo se
  falhar), remove **apenas** os que ela adicionou, junto com o venv temporário. O que já estava
  instalado antes não é tocado. Testado em Ubuntu 24.04 e 26.04, inclusive com o ImageMagick já instalado.
**Motivo:** o ImageMagick só é necessário para converter o cursor, não para usá-lo.

## 011 · 2026-11-21 · Terminal: Kitty + zsh + Oh My Zsh + Oh My Posh
- **Pacotes apt:** kitty, zsh, fzf, wl-clipboard (para o copypath/copyfile no Wayland), fontconfig.
- **Oh My Zsh** só para plugins, instalado sem interação (`RUNZSH=no CHSH=no KEEP_ZSHRC=yes --unattended`).
  Plugins: git, kubectl, docker, docker-compose, terraform, azure, aws, sudo, extract, copypath,
  copyfile, z, web-search, mais fzf-tab, zsh-autosuggestions e zsh-syntax-highlighting (clonados em
  `$ZSH_CUSTOM/plugins`). O fzf-tab vem antes dos dois últimos.
- **Oh My Posh** pelo script oficial em `~/.local/bin` (o step confere o binário no fim, porque o
  instalador pode sair com 0 mesmo falhando), com a fonte Meslo (`oh-my-posh font install meslo`).
- **Tema `if_tea`** baixado da tag da mesma versão do Oh My Posh instalado, com duas mudanças, verificadas
  com diff contra o original:
  1. `path.style`: de `agnoster_full` para `folder` (em `options` ou `properties`, a que existir);
  2. um segmento `terraform` (workspace atual) logo após o path, com os mesmos separadores e fundo
     roxo `#7b42bc`. Só aparece em pastas com projeto Terraform (`.terraform` ou `*.tf`) e depende do binário `terraform`.
- **Completion com fzf-tab:** `zstyle ':completion:*' menu no` em vez de `menu select`, porque o menu nativo
  competia com o fzf-tab e às vezes aparecia no lugar dele (você preferiu o fzf).
- **`~/.zshrc` versionado** em `config/zsh/zshrc`, instalado com backup se diferente. Personalizações
  vão em `~/.zshrc.local`. Ele carrega o mesmo `shell.d/` do bash (Go, nvm, Bun, Rust, `~/.local/bin`).
- **kitty.conf:** `font_family MesloLGM Nerd Font`, `font_size 12`, `shell /usr/bin/zsh`, alterando só
  essas chaves (o resto do arquivo é preservado, com backup).
- **Shell padrão:** `chsh` executado como root, para não pedir senha no meio da instalação.
- **Azure CLI** pelo repo apt oficial e **AWS CLI** pelo snap oficial da AWS, para que os plugins
  azure/aws tenham completions.
**Motivo:** terminal reproduzível; o prompt mostra só a pasta atual.

## 012 · 2026-11-21 · Kitty: splits, tabs, grupos e opacidade
- A config fica versionada em `config/kitty/ubuntu-setup.conf` e é incluída no **topo** do `kitty.conf`
  (`include ubuntu-setup.conf`). O `kitty.conf` continua seu: linhas abaixo do include têm prioridade.
  Isso substitui a edição de chaves soltas da decisão 011.
- **Splits**: layouts `splits` e `stack` (para o zoom). **Tabs** na barra superior, estilo powerline.
- **Grupos de tabs** = sessões nativas do kitty 0.45 (`save_as_session` / `goto_session`), salvas em
  `~/.config/kitty/sessions/`.
- Atalhos no estilo do Windows Terminal, sem sobrescrever os padrões do Kitty que você já usa
  (verificado contra os padrões da 0.45). Colinha em [kitty-atalhos.md](kitty-atalhos.md).
- `background_opacity 0.85`, ajustável na hora (`dynamic_background_opacity`).
- Config validada com o parser do próprio Kitty (zero erros).
- **Menu de clique direito** (e `ctrl+shift+m`): kitten `config/kitty/ubuntu-setup-menu.py`, que lista as
  ações com seus atalhos em fzf (um clique executa) e as executa com `boss.combine()` dentro do Kitty,
  **sem** ligar o controle remoto e sem abrir socket. Estender a seleção foi para `shift+clique direito`.
  Testado: as 20 ações passam no parser do Kitty, e o menu foi testado num terminal emulado (filtro + Enter, clique, Esc).
  A ação é executada com `add_timer(..., 0)`, porque o Kitty chama `handle_result` enquanto a janela do menu
  ainda está sendo removida, e ações relativas à janela ativa (splits) falhavam com "Key action failed".
  Reproduzido e corrigido num Kitty real sob Xvfb (splits, zoom, girar, tabs, fechar, fonte).
- **Kitty como terminal padrão** (`Ctrl+Alt+T`): no 25.10+, `kitty.desktop` vai para o topo de
  `~/.config/xdg-terminals.list` (os itens anteriores, como o Warp, viram reserva); no 24.04, vai para
  `org.gnome.desktop.default-applications.terminal`.
**Motivo:** recursos de multiplexador sem precisar de tmux, e acessíveis também pelo mouse.

## 013 · 2026-11-21 · Itens trazidos do repo antigo (`~/ubuntu-setup`)
- **Teclado** (`modules/15-keyboard.sh`): layout `us+intl` (dead keys) com cedilha. O `~/.XCompose`
  começa com `include "%L"` e recebe um bloco marcado `# >>> ubuntu-setup: cedilha >>>`, com os mesmos
  marcadores do repo antigo (o bloco que já existe é reconhecido). O resto do arquivo é preservado.
  Novo helper `ensure_block`/`has_block` para blocos marcados em arquivos do usuário.
- **Chave do Claude Desktop** baixada da URL oficial `https://downloads.claude.ai/claude-desktop/key.asc`
  (encontrada no repo antigo; idêntica à que estava versionada). A pasta `keys/` foi removida.
- **Fora:** GRUB, dual boot e ordem de boot UEFI, porque nem toda máquina tem GRUB e dual boot. Também ficou
  fora o tema BLACKICE, cuja imagem de fundo não tem licença clara.
- Do histórico antigo: fundo azul no Ptyxis foi testado e rejeitado (não aplicar).
**Motivo:** manter o que vale em qualquer máquina e consolidar tudo num repo só.

## 014 · 2026-11-21 · Mais ferramentas de infra e DBeaver

| Ferramenta | Origem | Atualiza por |
|---|---|---|
| Helm | repo apt oficial (Buildkite, indicado na documentação do Helm) | apt |
| kind | binário da última release no GitHub, sha256 conferido, em `~/.local/bin` | rodar o setup |
| kustomize | tarball da última release (`kustomize/vX`), sha256 conferido, em `~/.local/bin` | rodar o setup |
| tflint | zip da última release, sha256 conferido, em `~/.local/bin` | rodar o setup |
| DBeaver CE | repo apt oficial `dbeaver.io/debs/dbeaver-ce` (só amd64) | apt |

O Terraform já estava no setup (decisão 007). Novo helper `verify_sha256`; um checksum adulterado é recusado.
Testado em Ubuntu 26.04 limpo: a primeira execução instala e a segunda passa nos checks.
**Motivo:** completar o kit de Kubernetes/Terraform e ter um cliente de banco de dados.

## 015 · 2026-11-21 · Painel como interface do instalador
Escolhido entre as alternativas do artefato "Telas do ubuntu-setup".
- **Durante a instalação:** tela alternativa (como htop), redesenhada 10 vezes por segundo (~1,4 ms por quadro
  com 57 etapas, sem subshells). Mostra seções com contagem, etapa atual com spinner, as 3 próximas,
  falhas com o motivo, barra geral, tempo decorrido e estimativa do restante.
- **No fim:** o painel fecha e um resumo em cartões fica no terminal (instalados, já ok, falharam, duração),
  com falhas e motivo, log de cada falha e tempo por seção. Não espera Enter, para não travar o `curl | bash`.
- **Motivo da falha:** última linha com cara de erro da saída; senão, o comando que falhou; senão, a última linha.
- **Modo clássico** (uma linha por etapa), automático fora de TTY, em janela menor que 74×22 e no `--dry-run`;
  pode ser forçado com `SETUP_UI=classic`. Ctrl+C e redimensionamento da janela são tratados.
- Testado num terminal emulado (90×30 e 74×22): quadros, resumo, Ctrl+C (código 130) e modo clássico.
**Motivo:** ver o todo da instalação de relance, com estimativa de tempo.

## 016 · 2026-11-21 · ABNT2 como segundo layout
Layouts `[us+intl, br]`: US Internacional continua sendo o principal (1º da lista) e o ABNT2 (`br` no xkb) é o
segundo. **Super+Espaço** alterna (padrão do GNOME; Shift+Super+Espaço volta). A etapa garante o atalho
acrescentando-o aos atalhos que já existirem, sem apagar nenhum. A cedilha do `~/.XCompose` continua
valendo para o US Internacional; no ABNT2, o ç tem tecla própria.
**Motivo:** alternar para o teclado brasileiro quando for usar um teclado físico ABNT2.

## 017 · 2026-11-21 · Config atual do Open Bar salva
Exportada a config do Open Bar desta máquina: barra **Mainland**, opacidade 0,9, fonte `Sans 12` e barra
cheia com janela maximizada (`wmaxbar`). Ficam fora, além dos `*bguri`, as chaves que a extensão grava
sozinha: `pause-reload`, `reloadstyle` e `monitor-width/height` (tamanho da tela de cada máquina).
As outras extensões não foram reexportadas nesse passo.
**Motivo:** levar o visual da barra para outras máquinas sem fixar resolução nem estado interno.

## 018 · 2026-11-21 · Ferramentas do GNOME, OBS, GParted, Git/SSH e logs do Docker
- **GNOME:** Ajustes (`gnome-tweaks`), Gerenciador de Extensões e `dconf-editor`, do apt do Ubuntu.
- **OBS Studio:** PPA oficial `ppa:obsproject/obs-studio` (tem 24.04 e 26.04; versão mais nova que a do Ubuntu).
- **GParted:** apt do Ubuntu.
- **Identidade do Git** (módulo `22-git.sh`): nome e e-mail do `local.env`; `init.defaultBranch=main`. Sem as
  variáveis, a etapa aceita a identidade que já existir; se não houver nenhuma, falha com aviso claro.
- **Chave SSH:** ed25519 em `~/.ssh/id_ed25519`, sem senha (a instalação não pede input), comentário com o
  e-mail do `local.env`. Nunca sobrescreve chave existente. O envio ao GitHub fica manual (`gh ssh-key add`),
  porque exige a permissão `admin:public_key`, que o login padrão do `gh` não dá.
- **Logs do Docker:** `json-file` com `max-size=10m` e `max-file=3` em `/etc/docker/daemon.json`, juntando com o
  que já houver no arquivo (backup antes). O Docker só é reiniciado se não houver containers rodando.
  Vale para containers criados depois. Ajustável por `SETUP_DOCKER_LOG_MAX_SIZE` e `SETUP_DOCKER_LOG_MAX_FILE`.
**Motivo:** pedidos do usuário; o limite de logs evita que containers antigos lotem o disco.

## 019 · 2026-11-21 · RustDesk
`.deb` oficial da última release no GitHub (`rustdesk-<versão>-x86_64.deb` / `aarch64.deb`). Não há repo apt
oficial, então a checagem compara a versão instalada com a última release e atualiza quando o setup roda.
**Motivo:** acesso remoto, já usado nesta máquina.

## 020 · 2026-11-21 · URL do repositório
Repo público `github.com/JulioC354R/ubuntu-setup`. O usuário do GitHub entra no comando de bootstrap e no
`SETUP_REPO_URL` padrão: é o endereço público do próprio repo, sem ele não há como baixar. Continua proibido
versionar e-mail, nome real, hostname etc. Fork: `SETUP_REPO_URL=https://github.com/<outro>/ubuntu-setup.git`.
**Motivo:** o bootstrap em uma linha precisa de uma URL fixa.

## 021 · 2026-11-21 · Bootstrap idempotente com pasta já existente
Se `~/.local/share/ubuntu-setup` existir sem ser um clone (ex.: sobra de testes), o bootstrap clona numa pasta
temporária ao lado, guarda a antiga como `ubuntu-setup.bak-AAAAMMDD-HHMMSS` e põe o clone no lugar. Nada é
apagado. Já sendo um clone, só faz `git pull --ff-only`. Clone com `GIT_TERMINAL_PROMPT=0`, para nunca pedir
usuário/senha no meio do `curl | bash`; se falhar, a pasta temporária é removida.
**Motivo:** o `curl | bash` falhava com "destination path already exists" (relatado pelo usuário).

## 022 · 2026-11-21 · Fim do local.env: perguntas no início
Removidos `config/local.env.example`, `load_local_env` e `require_var`. O `install.sh` pergunta, logo depois do
cabeçalho e antes do sudo, o **usuário** e o **e-mail do GitHub** (`ui_ask`, lendo de `/dev/tty`, então funciona
no `curl | bash`). Enter aceita o sugerido: o valor atual do Git ou, numa máquina nova, o e-mail anônimo
`<id>+<usuário>@users.noreply.github.com` (o id vem da API pública do GitHub). O usuário do GitHub vira o
`user.name`. Valida formato e tenta de novo até 3 vezes. Sem terminal, no `--dry-run` ou com
`GIT_USER_NAME`/`GIT_USER_EMAIL` já definidos, não pergunta. Sem resposta e sem identidade prévia, a etapa falha
com aviso. Substitui a parte do `local.env` das decisões 001 e 018.
**Motivo:** pedido do usuário: um arquivo a menos para preparar antes de rodar o setup.

---

## Em aberto
- Gerenciador de dotfiles (chezmoi, Stow ou só `install_file`)?
- Shell (bash/zsh), editor e perfis (`minimal`, `dev`, `desktop`)?
