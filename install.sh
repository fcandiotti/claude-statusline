#!/usr/bin/env bash
# Instalador da statusline adaptativa do Claude Code.
# Funciona em macOS, Linux, WSL e Windows com Git Bash.
#
# Uso:  bash install.sh
#
# O que faz:
#   1. copia statusline.sh para o seu config dir do Claude Code
#   2. registra o bloco "statusLine" no settings.json, preservando o resto
#   3. faz backup de qualquer arquivo que sobrescreva

set -e

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_SRC="$SRC_DIR/statusline.sh"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPT_DEST="$CONFIG_DIR/statusline.sh"
SETTINGS="$CONFIG_DIR/settings.json"
STAMP=$(date +%Y%m%d-%H%M%S)

say()  { printf '%s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
ok()   { printf '  + %s\n' "$*"; }

say ""
say "Statusline adaptativa para Claude Code"
say "======================================"
say ""

[ -f "$SCRIPT_SRC" ] || { say "erro: statusline.sh não encontrado em $SRC_DIR"; exit 1; }

say "Verificando dependências:"
if command -v jq >/dev/null 2>&1; then
  ok "jq encontrado"
elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
  ok "python encontrado (será usado no lugar do jq)"
else
  warn "nem jq nem python3 encontrados — a statusline não conseguirá ler os dados"
  warn "instale um deles:  macOS: brew install jq | Debian/Ubuntu/WSL: sudo apt install jq"
  warn "                   Fedora: sudo dnf install jq | Arch: sudo pacman -S jq"
fi
if command -v git >/dev/null 2>&1; then
  ok "git encontrado"
else
  warn "git não encontrado — a statusline funciona, mas sem pasta/branch"
fi
say ""

mkdir -p "$CONFIG_DIR"

if [ -f "$SCRIPT_DEST" ] && ! cmp -s "$SCRIPT_SRC" "$SCRIPT_DEST"; then
  cp "$SCRIPT_DEST" "$SCRIPT_DEST.bak-$STAMP"
  ok "backup da statusline anterior: $SCRIPT_DEST.bak-$STAMP"
fi
cp "$SCRIPT_SRC" "$SCRIPT_DEST"
chmod +x "$SCRIPT_DEST"
ok "script instalado em $SCRIPT_DEST"

case "$CONFIG_DIR" in
  "$HOME"/*) CMD="bash \"\$HOME/${CONFIG_DIR#"$HOME"/}/statusline.sh\"" ;;
  *)         CMD="bash \"$CONFIG_DIR/statusline.sh\"" ;;
esac

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-$STAMP"
  ok "backup do settings.json: $SETTINGS.bak-$STAMP"
else
  printf '{}\n' > "$SETTINGS"
  ok "settings.json criado"
fi

merge_done=0
if command -v jq >/dev/null 2>&1; then
  if jq --arg cmd "$CMD" '.statusLine = {type: "command", command: $cmd, padding: 0}' \
       "$SETTINGS" > "$SETTINGS.tmp" 2>/dev/null; then
    mv "$SETTINGS.tmp" "$SETTINGS"
    merge_done=1
  else
    rm -f "$SETTINGS.tmp"
  fi
fi

if [ "$merge_done" -eq 0 ]; then
  for py in python3 python; do
    if command -v "$py" >/dev/null 2>&1; then
      if "$py" - "$SETTINGS" "$CMD" <<'PYEOF'
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
data["statusLine"] = {"type": "command", "command": cmd, "padding": 0}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PYEOF
      then
        merge_done=1
      fi
      break
    fi
  done
fi

if [ "$merge_done" -eq 1 ]; then
  ok "settings.json atualizado"
else
  warn "não consegui editar o settings.json automaticamente"
  warn "adicione este bloco manualmente em $SETTINGS:"
  say ""
  say "  \"statusLine\": { \"type\": \"command\", \"command\": \"$CMD\", \"padding\": 0 }"
  say ""
fi

say ""
say "Prévia (largura atual do terminal: ${COLUMNS:-desconhecida}):"
say ""
PREVIEW='{"model":{"display_name":"Opus 5"},"effort":{"level":"high"},"context_window":{"total_input_tokens":47000,"used_percentage":31,"remaining_percentage":69},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":0},"seven_day":{"used_percentage":28}},"cost":{"total_cost_usd":0.87},"transcript_path":"","workspace":{"current_dir":"'"$PWD"'"}}'
COLUMNS=${COLUMNS:-$(tput cols 2>/dev/null || echo 100)} bash "$SCRIPT_DEST" <<< "$PREVIEW" || true
say ""
say "Pronto. Abra o Claude Code (ou volte para a sessão aberta) e a barra já aparece."
say "Dicas:"
say "  - sem emojis:        export CLAUDE_STATUSLINE_STYLE=ascii"
say "  - rótulo de conta:   export CLAUDE_STATUSLINE_LABEL=trabalho"
say "  - margem da borda:   export CLAUDE_STATUSLINE_MARGIN=6"
say ""
