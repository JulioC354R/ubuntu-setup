# ~/.config/kitty/ubuntu-setup-menu.py — gerenciado pelo ubuntu-setup (config/kitty/ubuntu-setup-menu.py).
# Menu do clique direito (e de ctrl+shift+m) no Kitty: lista as ações e executa a escolhida.
#
# Como funciona (kitten do kitty):
#   main()          roda numa janela sobreposta e mostra o menu com fzf (clique ou Enter)
#   handle_result() roda dentro do kitty e executa a ação com boss.combine(), sem controle remoto
#                   e sem abrir socket
#
# Para adicionar um item: uma linha em ITEMS com (rótulo, atalho, ação do kitty).

import subprocess

ITEMS = [
    # rótulo                       atalho                  ação do kitty
    ("Copiar",                     "ctrl+shift+c",         "copy_to_clipboard"),
    ("Colar",                      "ctrl+shift+v",         "paste_from_clipboard"),
    ("Dividir à direita",          "alt+shift+=",          "launch --location=vsplit --cwd=current"),
    ("Dividir abaixo",             "alt+shift+-",          "launch --location=hsplit --cwd=current"),
    ("Zoom na divisão",            "alt+z",                "toggle_layout stack"),
    ("Girar divisão",              "alt+r",                "layout_action rotate"),
    ("Fechar divisão",             "ctrl+shift+w",         "close_window"),
    ("Nova tab",                   "ctrl+shift+t",         "new_tab_with_cwd"),
    ("Renomear tab",               "ctrl+shift+alt+t",     "set_tab_title"),
    ("Fechar tab",                 "ctrl+shift+q",         "close_tab"),
    ("Salvar tabs como grupo",     "alt+shift+a",          "save_as_session --save-only --base-dir ~/.config/kitty/sessions"),
    ("Trocar de grupo",            "alt+shift+s",          "goto_session --sort-by=recent sessions"),
    ("Voltar ao grupo anterior",   "alt+shift+p",          "goto_session -1"),
    ("Mais opaco",                 "ctrl+shift+a  m",      "set_background_opacity +0.05"),
    ("Menos opaco",                "ctrl+shift+a  l",      "set_background_opacity -0.05"),
    ("Opacidade padrão (85%)",     "ctrl+shift+a  d",      "set_background_opacity default"),
    ("Aumentar fonte",             "ctrl+shift+=",         "change_font_size all +1.0"),
    ("Diminuir fonte",             "ctrl+shift+-",         "change_font_size all -1.0"),
    ("Editar configuração",        "ctrl+shift+f2",        "edit_config_file"),
    ("Recarregar configuração",    "ctrl+shift+f5",        "load_config_file"),
]


def main(args: list[str]) -> str:
    # Uma linha por item: "índice<TAB>rótulo   atalho". O fzf mostra só da 2ª coluna em diante.
    width = max(len(label) for label, _, _ in ITEMS) + 3
    lines = "\n".join(f"{i}\t{label.ljust(width)}{keys}" for i, (label, keys, _) in enumerate(ITEMS))
    proc = subprocess.run(
        [
            "fzf",
            "--delimiter=\t", "--with-nth=2..",
            "--layout=reverse", "--no-sort", "--cycle",
            "--prompt=  ", "--pointer=▸", "--info=hidden",
            "--border=rounded", "--border-label= Kitty ", "--margin=1,2",
            "--header=clique ou Enter para executar · digite para filtrar · Esc fecha",
            "--bind=left-click:accept",   # um clique já executa
        ],
        input=lines, stdout=subprocess.PIPE, text=True,
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        return ""
    return proc.stdout.split("\t", 1)[0].strip()


def handle_result(args: list[str], answer: str, target_window_id: int, boss) -> None:
    if not answer.isdigit() or int(answer) >= len(ITEMS):
        return
    action = ITEMS[int(answer)][2]

    # O kitty chama handle_result enquanto a janela do menu ainda está sendo removida: ela já saiu
    # do window_id_map, mas ainda é a janela ativa da tab. Ações como "launch --location=hsplit"
    # usam a janela ativa e falham ("Key action failed" com o id da janela do menu).
    # Solução: executar no próximo ciclo do kitty (add_timer com 0 s, padrão usado pelo próprio
    # kitty), quando o menu já foi removido e a janela original voltou a ser a ativa.
    from kitty.fast_data_types import add_timer

    def run(timer_id: int | None = None) -> None:
        window = boss.window_id_map.get(target_window_id)
        if window is None:
            return
        boss.combine(action, window)

    add_timer(run, 0, False)
