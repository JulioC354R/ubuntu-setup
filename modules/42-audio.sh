#!/usr/bin/env bash
# modules/42-audio.sh — correções de áudio: fone Fuxi-H3 (receptor USB 2.4 GHz).
# Sintomas: sem som (mixer interno "PCM" em 0%) ou só um lado ao mudar o volume (perfil analógico).
# Correção: perfil "Digital Stereo (IEC958) + Mono Input", mixer interno fixo em 100% e a
# "Saída analógica" escondida (conjunto de perfis próprio, só com a saída digital e o microfone).

FUXI_PROFILE="output:iec958-stereo+input:mono-fallback"
FUXI_ALSA_ID=FuxiH3   # id da placa no ALSA (aplay -l)
FUXI_WP_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d/51-fuxi-h3.conf"
FUXI_UDEV_RULE=/etc/udev/rules.d/91-fuxi-h3.rules
FUXI_PROFILE_SET=/etc/alsa-card-profile/mixer/profile-sets/fuxi-h3.conf

fuxi_connected() { [[ -e /proc/asound/$FUXI_ALSA_ID ]]; }

# Dispositivo do fone no PipeWire (sem `| head`: com pipefail, o SIGPIPE daria falso negativo)
FUXI_JQ_DEVICE='first(.[] | select(.type == "PipeWire:Interface:Device")
  | select((.info.props["device.name"] // "") | test("Fuxi-H3")))'

fuxi_device_id()       { pw-dump | jq -r "$FUXI_JQ_DEVICE | .id"; }
fuxi_current_profile() { pw-dump | jq -r "$FUXI_JQ_DEVICE | .info.params.Profile[0].name // empty"; }

fuxi_has_analog() {  # 0 se o PipeWire ainda oferece a saída analógica do fone
  [[ -n "$(pw-dump | jq -r "$FUXI_JQ_DEVICE | .info.params.EnumRoute[]? | select(.name == \"analog-output\") | .name")" ]]
}

fuxi_pcm_full() {  # 0 se os dois lados do mixer PCM estão em 100%
  local out; out=$(amixer -c "$FUXI_ALSA_ID" sget PCM,0 2>/dev/null)
  [[ "$out" == *"Front Left: Playback 100 [100%]"* && "$out" == *"Front Right: Playback 100 [100%]"* ]]
}

check_fuxi_h3() {
  cmp -s "$SETUP_ROOT/config/audio/51-fuxi-h3.conf" "$FUXI_WP_CONF" || return 1
  cmp -s "$SETUP_ROOT/config/audio/91-fuxi-h3.rules" "$FUXI_UDEV_RULE" || return 1
  cmp -s "$SETUP_ROOT/config/audio/fuxi-h3-profile-set.conf" "$FUXI_PROFILE_SET" || return 1
  fuxi_connected || return 0
  [[ "$(fuxi_current_profile)" == "$FUXI_PROFILE" ]] && fuxi_pcm_full && ! fuxi_has_analog
}

step_fuxi_h3() {
  local id idx changed=0 card
  apt_install alsa-utils
  # Perfil padrão (WirePlumber 0.5+; no 0.4 vale a aplicação ao vivo abaixo, que o WirePlumber memoriza)
  install_file "$SETUP_ROOT/config/audio/51-fuxi-h3.conf" "$FUXI_WP_CONF"
  # Conjunto de perfis só com a saída digital (esconde a analógica)
  write_root_file "$FUXI_PROFILE_SET" "$(cat "$SETUP_ROOT/config/audio/fuxi-h3-profile-set.conf")" && changed=1
  # udev: mixer interno em 100% ao conectar (depois do alsactl restore) e o conjunto de perfis acima
  write_root_file "$FUXI_UDEV_RULE" "$(cat "$SETUP_ROOT/config/audio/91-fuxi-h3.rules")" && changed=1
  (( changed )) && as_root udevadm control --reload
  fuxi_connected || return 0
  # Fone conectado e ainda com a saída analógica: reaplica o udev e recarrega o WirePlumber
  # (o áudio para por ~2 s). Sem o fone, vale na próxima conexão.
  if has_cmd pw-dump && fuxi_has_analog; then
    card=$(readlink -f "/proc/asound/$FUXI_ALSA_ID"); card=${card##*/}   # ex.: card4
    as_root udevadm trigger --action=change "/sys/class/sound/$card"
    as_root udevadm settle
    systemctl --user restart wireplumber
    sleep 3
  fi
  # Fone conectado agora: aplica sem precisar reconectar
  if has_cmd wpctl && has_cmd pw-dump && id=$(fuxi_device_id) && [[ -n "$id" ]]; then
    if [[ "$(fuxi_current_profile)" != "$FUXI_PROFILE" ]]; then
      idx=$(pw-dump | jq -r --argjson id "$id" --arg p "$FUXI_PROFILE" \
        '.[] | select(.id == $id) | .info.params.EnumProfile[] | select(.name == $p) | .index')
      [[ -n "$idx" ]] || { echo "Perfil $FUXI_PROFILE não existe no Fuxi-H3." >&2; return 1; }
      wpctl set-profile "$id" "$idx"
      sleep 1   # o mixer só deve ser ajustado depois que o perfil novo abre o dispositivo
    fi
  fi
  amixer -q -c "$FUXI_ALSA_ID" sset PCM,0 100% unmute
  amixer -q -c "$FUXI_ALSA_ID" sset PCM,1 100% unmute
}

plan_section "Áudio"
plan_step --check check_fuxi_h3 "Fone Fuxi-H3 (perfil IEC958 + volume interno)" step_fuxi_h3
