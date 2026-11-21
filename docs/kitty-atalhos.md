# Kitty: atalhos

Configuração: [config/kitty/ubuntu-setup.conf](../config/kitty/ubuntu-setup.conf), no estilo do Windows Terminal.
Para mudar algo só nesta máquina, edite `~/.config/kitty/kitty.conf` abaixo da linha `include`.
Recarregar a config sem fechar o Kitty: `ctrl+shift+f5`.

## Menu: clique direito (ou `ctrl+shift+m`)
Abre um menu com todas as ações abaixo e o atalho de cada uma. **Um clique executa**; você também
pode digitar para filtrar e dar Enter. Esc fecha. Inclui Copiar e Colar.
Estender a seleção, que era do clique direito, agora fica em `shift+clique direito`.
Em programas que usam o mouse (vim, htop), o clique direito continua indo para o programa.

O Kitty também abre com **`Ctrl+Alt+T`** e no "Abrir no terminal" do gerenciador de arquivos.

## Dividir a janela (splits)
| Atalho | Ação |
|---|---|
| `alt+shift+-` | divide **abaixo** |
| `alt+shift+=` (ou `alt+shift+\`) | divide **à direita** |
| `ctrl+shift+enter` | divide no lado mais comprido |
| `alt+←↑→↓` | muda o foco entre divisões |
| `alt+shift+←↑→↓` | redimensiona a divisão |
| `ctrl+shift+alt+←↑→↓` | troca divisões de lugar |
| `alt+z` | zoom: a divisão atual em tela cheia (repita para voltar) |
| `alt+r` | gira a divisão (horizontal ↔ vertical) |
| `ctrl+shift+w` | fecha a divisão |

## Tabs
| Atalho | Ação |
|---|---|
| `ctrl+shift+t` | nova tab (na pasta atual) |
| `ctrl+tab` / `ctrl+shift+tab` | próxima / anterior |
| `alt+1` … `alt+9` | vai para a tab N |
| `ctrl+shift+alt+t` | renomeia a tab |
| `ctrl+shift+.` / `ctrl+shift+,` | move a tab para a direita / esquerda |
| `ctrl+shift+q` | fecha a tab |

## Grupos de tabs (sessões)
Um grupo é um conjunto de tabs e divisões salvo em `~/.config/kitty/sessions/<nome>.kitty-session`
(ex.: um grupo "api" com três tabs: editor, servidor e logs).

| Atalho | Ação |
|---|---|
| `alt+shift+a` | salva as tabs atuais como grupo (pergunta o nome) |
| `alt+shift+s` | lista os grupos e troca; abre o grupo se ainda não estiver aberto |
| `alt+shift+p` | volta para o grupo anterior |

## Aparência
| Atalho | Ação |
|---|---|
| `ctrl+shift+a` e depois `m` / `l` | mais / menos opaco (padrão: 85%) |
| `ctrl+shift+a` e depois `1` / `d` | 100% opaco / volta ao padrão |
| `ctrl+shift+=` / `ctrl+shift+-` | aumenta / diminui a fonte |

> Os atalhos `alt+←/→` ficam com o Kitty. No terminal, use `ctrl+←/→` para pular palavras.
