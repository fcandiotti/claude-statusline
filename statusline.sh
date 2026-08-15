#!/usr/bin/env bash
# Statusline adaptativa para Claude Code — macOS, Linux, WSL e Windows (Git Bash).
#
# Mostra em uma linha só quando cabe no terminal; quando não cabe, quebra em
# duas: identidade (conta/modelo/esforço/pasta+branch) na primeira, telemetria
# (contexto, limites, custo) na segunda. Nada é truncado ou escondido.
#
# Variáveis de ambiente opcionais:
#   CLAUDE_STATUSLINE_STYLE=ascii   → desliga emojis (terminais sem suporte)
#   CLAUDE_STATUSLINE_LABEL=nome    → rótulo fixo de conta (sobrescreve a detecção)
#   CLAUDE_STATUSLINE_MARGIN=4      → colunas reservadas na borda direita

input=$(cat)

read_fields() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '
      (.model.display_name // "?"),
      (.effort.level // "-"),
      (.context_window.total_input_tokens // 0),
      (.context_window.used_percentage // 0 | floor),
      (.context_window.remaining_percentage // 0 | floor),
      (.rate_limits.five_hour.used_percentage // 0 | floor),
      (.rate_limits.five_hour.resets_at // 0),
      (.rate_limits.seven_day.used_percentage // 0 | floor),
      (.cost.total_cost_usd // 0),
      (.transcript_path // ""),
      (.workspace.current_dir // .cwd // "")'
    return
  fi

  local py
  for py in python3 python; do
    if command -v "$py" >/dev/null 2>&1; then
      printf '%s' "$input" | "$py" -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
def g(o, k):
    v = (o or {}).get(k)
    return v if v is not None else {}
m, e, c = g(d, "model"), g(d, "effort"), g(d, "context_window")
r = g(d, "rate_limits")
f, s = g(r, "five_hour"), g(r, "seven_day")
w, cost = g(d, "workspace"), g(d, "cost")
def i(o, k):
    try:
        return int(float(o.get(k) or 0))
    except Exception:
        return 0
rows = [
    m.get("display_name") or "?",
    e.get("level") or "-",
    i(c, "total_input_tokens"),
    i(c, "used_percentage"),
    i(c, "remaining_percentage"),
    i(f, "used_percentage"),
    i(f, "resets_at"),
    i(s, "used_percentage"),
    cost.get("total_cost_usd") or 0,
    d.get("transcript_path") or "",
    w.get("current_dir") or d.get("cwd") or "",
]
sys.stdout.write("\n".join(str(x) for x in rows) + "\n")
'
      return
    fi
  done

  printf '%s\n' "?" "-" 0 0 0 0 0 0 0 "" ""
}

{
  IFS= read -r MODEL
  IFS= read -r EFFORT
  IFS= read -r USED
  IFS= read -r CTX_PCT
  IFS= read -r CTX_FREE
  IFS= read -r RL5
  IFS= read -r RL5_RESET
  IFS= read -r RL7
  IFS= read -r COST
  IFS= read -r TRANSCRIPT
  IFS= read -r DIR
} < <(read_fields)

if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
  printf 'statusline: instale jq (ou python3) para exibir os dados da sessão\n'
  exit 0
fi

RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
TEAL=$'\033[38;5;79m'
GREEN=$'\033[38;5;71m'
YELLOW=$'\033[38;5;179m'
RED=$'\033[38;5;167m'
GREY=$'\033[38;5;245m'
DARK=$'\033[38;5;238m'
WHITE=$'\033[38;5;252m'
BLUE=$'\033[38;5;110m'
PALETTE=($'\033[38;5;140m' $'\033[38;5;173m' $'\033[38;5;79m' $'\033[38;5;110m' $'\033[38;5;179m' $'\033[38;5;71m')

if [ "${CLAUDE_STATUSLINE_STYLE:-emoji}" = "ascii" ]; then
  I_DOT="*"; I_BOLT="!"; I_DIR="~"; I_BRANCH="@"; I_CTX="ctx"; I_CLOCK="->"
  BAR_FULL="#"; BAR_EMPTY="-"; SEP_CHAR="|"
  WIDE_CHARS=""
else
  I_DOT="●"; I_BOLT="⚡"; I_DIR="📁"; I_BRANCH="⎇"; I_CTX="🧠"; I_CLOCK="↻"
  BAR_FULL="█"; BAR_EMPTY="░"; SEP_CHAR="│"
  WIDE_CHARS="📁 🧠 ⚡"
fi

# Rótulo de conta: só aparece quando o config dir NÃO é o ~/.claude padrão
# (ex.: ~/.claude-trabalho → "trabalho"). Com uma conta só, o segmento some.
LABEL="${CLAUDE_STATUSLINE_LABEL:-}"
if [ -z "$LABEL" ]; then
  CFG="${CLAUDE_CONFIG_DIR:-}"
  [ -z "$CFG" ] && [ -n "$TRANSCRIPT" ] && case "$TRANSCRIPT" in
    */projects/*) CFG="${TRANSCRIPT%%/projects/*}" ;;
  esac
  if [ -n "$CFG" ]; then
    CFG_BASE="${CFG##*/}"
    CFG_BASE="${CFG_BASE#.}"
    case "$CFG_BASE" in
      claude|"") LABEL="" ;;
      claude-*)  LABEL="${CFG_BASE#claude-}" ;;
      *)         LABEL="$CFG_BASE" ;;
    esac
  fi
fi

label_color() {
  local s=$1 sum=0 i
  for ((i = 0; i < ${#s}; i++)); do
    sum=$((sum + $(printf '%d' "'${s:i:1}")))
  done
  printf '%s' "${PALETTE[$((sum % ${#PALETTE[@]}))]}"
}

color_for() {
  if   [ "$1" -ge 80 ]; then printf '%s' "$RED"
  elif [ "$1" -ge 50 ]; then printf '%s' "$YELLOW"
  else                       printf '%s' "$GREEN"
  fi
}

BAR_WIDTH=10

bar() {
  local pct=$1 color=$2 filled i out=""
  filled=$(((pct * BAR_WIDTH + 99) / 100))
  [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
  [ "$filled" -lt 0 ] && filled=0
  for ((i = 0; i < BAR_WIDTH; i++)); do
    if [ "$i" -lt "$filled" ]; then out="${out}${color}${BAR_FULL}"; else out="${out}${DARK}${BAR_EMPTY}"; fi
  done
  printf '%s%s' "$out" "$RESET"
}

bar_plain() {
  local i out=""
  for ((i = 0; i < BAR_WIDTH; i++)); do out="${out}#"; done
  printf '%s' "$out"
}

fmt_tokens() {
  if [ "$1" -ge 1000 ]; then printf '%dK' $(($1 / 1000)); else printf '%d' "$1"; fi
}

fmt_eta() {
  local secs=$(($1 - $(date +%s)))
  [ "$secs" -le 0 ] && { printf '0m'; return; }
  local h=$((secs / 3600))
  local m=$(((secs % 3600) / 60))
  if [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"; else printf '%dm' "$m"; fi
}

count_of() {
  local s=$1
  local c=$2
  local t=${s//"$c"/}
  printf '%d' $((${#s} - ${#t}))
}

# Largura visível: conta code points e soma 1 por emoji de largura dupla.
vislen() {
  local s=$1
  local n=${#s}
  local c
  for c in $WIDE_CHARS; do
    n=$((n + $(count_of "$s" "$c")))
  done
  printf '%d' "$n"
}

CTX_COLOR=$(color_for "$CTX_PCT")
RL5_COLOR=$(color_for "$RL5")
RL7_COLOR=$(color_for "$RL7")
BARP=$(bar_plain)

P=()
C=()
add() { P+=("$1"); C+=("$2"); }

if [ -n "$LABEL" ]; then
  LABEL_COLOR=$(label_color "$LABEL")
  add "${I_DOT} ${LABEL}" "${BOLD}${LABEL_COLOR}${I_DOT} ${LABEL}${RESET}"
fi

add "${MODEL}" "${BOLD}${TEAL}${MODEL}${RESET}"

add "${EFFORT} ${I_BOLT}" "${GREY}${EFFORT}${RESET} ${YELLOW}${I_BOLT}${RESET}"

PLACE_P="${I_DIR} ${DIR##*/}"
PLACE_C="${GREY}${I_DIR}${RESET} ${WHITE}${DIR##*/}${RESET}"
if [ -n "$DIR" ] && command -v git >/dev/null 2>&1 && git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
  [ -z "$BRANCH" ] && BRANCH=$(git -C "$DIR" rev-parse --short HEAD 2>/dev/null)
  DIRTY_P=""
  DIRTY_C=""
  if [ -n "$(git -C "$DIR" status --porcelain 2>/dev/null)" ]; then
    DIRTY_P="*"
    DIRTY_C="${YELLOW}*${RESET}"
  fi
  PLACE_P="${PLACE_P} ${I_BRANCH} ${BRANCH}${DIRTY_P}"
  PLACE_C="${PLACE_C} ${BLUE}${I_BRANCH} ${BRANCH}${RESET}${DIRTY_C}"
fi
add "$PLACE_P" "$PLACE_C"

IDENTITY_COUNT=${#P[@]}

add "${I_CTX} $(fmt_tokens "$USED") ${BARP} ${CTX_PCT}% (${CTX_FREE}% livre)" \
    "${GREY}${I_CTX}${RESET} ${CTX_COLOR}$(fmt_tokens "$USED")${RESET} $(bar "$CTX_PCT" "$CTX_COLOR") ${CTX_COLOR}${CTX_PCT}%${RESET} ${DIM}${CTX_COLOR}(${CTX_FREE}% livre)${RESET}"

RL5_P="5h ${BARP} ${RL5}%"
RL5_C="${BOLD}${WHITE}5h${RESET} $(bar "$RL5" "$RL5_COLOR") ${RL5_COLOR}${RL5}%${RESET}"
if [ "$RL5_RESET" -gt 0 ]; then
  ETA=$(fmt_eta "$RL5_RESET")
  RL5_P="${RL5_P} ${I_CLOCK} ${ETA}"
  RL5_C="${RL5_C} ${GREY}${I_CLOCK} ${ETA}${RESET}"
fi
add "$RL5_P" "$RL5_C"

add "7d ${RL7}%" "${BOLD}${WHITE}7d${RESET} ${RL7_COLOR}${RL7}%${RESET}"

add "\$$(printf '%.2f' "$COST")" "${GREEN}\$$(printf '%.2f' "$COST")${RESET}"

SEP="${DARK} ${SEP_CHAR} ${RESET}"
SEP_W=3

WIDTH=${COLUMNS:-0}
case "$WIDTH" in
  ''|*[!0-9]*) WIDTH=0 ;;
esac
[ "$WIDTH" -le 0 ] && WIDTH=1000
MARGIN=${CLAUDE_STATUSLINE_MARGIN:-4}
case "$MARGIN" in
  ''|*[!0-9]*) MARGIN=4 ;;
esac
AVAIL=$((WIDTH - MARGIN))
[ "$AVAIL" -lt 20 ] && AVAIL=20

join_line() {
  local out="" first=1 i
  for i in "$@"; do
    if [ "$first" -eq 1 ]; then out="${C[i]}"; first=0; else out="${out}${SEP}${C[i]}"; fi
  done
  printf '%s\n' "$out"
}

# Empacota segmentos em linhas, sem nunca cortar um segmento no meio.
emit_group() {
  local cur=() w=0 i lw
  for i in "$@"; do
    lw=$(vislen "${P[i]}")
    if [ "${#cur[@]}" -eq 0 ]; then
      cur=("$i"); w=$lw
    elif [ $((w + SEP_W + lw)) -le "$AVAIL" ]; then
      cur+=("$i"); w=$((w + SEP_W + lw))
    else
      join_line "${cur[@]}"; cur=("$i"); w=$lw
    fi
  done
  [ "${#cur[@]}" -gt 0 ] && join_line "${cur[@]}"
}

N=${#P[@]}
TOTAL=$((SEP_W * (N - 1)))
for ((i = 0; i < N; i++)); do TOTAL=$((TOTAL + $(vislen "${P[i]}"))); done

if [ "$TOTAL" -le "$AVAIL" ]; then
  ALL=()
  for ((i = 0; i < N; i++)); do ALL+=("$i"); done
  join_line "${ALL[@]}"
else
  GROUP_A=()
  GROUP_B=()
  for ((i = 0; i < N; i++)); do
    if [ "$i" -lt "$IDENTITY_COUNT" ]; then GROUP_A+=("$i"); else GROUP_B+=("$i"); fi
  done
  emit_group "${GROUP_A[@]}"
  emit_group "${GROUP_B[@]}"
fi
