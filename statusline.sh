#!/bin/bash
# Claude Code statusline — extended Powerlevel10k-style layout
# Ref: https://jackle.pro/articles/claude-code-status-line
# Reads the session JSON payload from stdin.

input=$(cat)

# keep the latest payload around for debugging / field discovery
mkdir -p "$HOME/.claude/cache" 2>/dev/null
printf '%s' "$input" > "$HOME/.claude/cache/last_payload.json" 2>/dev/null

# ---------- one batched jq call for the simple stdin fields ----------
# \x1f (unit separator) instead of \t: tab is IFS whitespace, so empty fields
# would collapse and shift every later field.
IFS=$'\x1f' read -r MODEL_NAME EFFORT_LEVEL PROJECT_DIR SESSION_ID TRANSCRIPT_PATH \
  COST_USD CTX_TOTAL CTX_SIZE CTX_PCT RL_5H RL_7D RL_5H_RESET <<< "$(
  printf '%s' "$input" | jq -r '
    [
      (.model.display_name // ""),
      (.effort.level // ""),
      (.workspace.current_dir // .cwd // ""),
      (.session_id // ""),
      (.transcript_path // ""),
      (.cost.total_cost_usd // ""),
      (.context_window.total_input_tokens // ""),
      (.context_window.context_window_size // ""),
      (.context_window.used_percentage // ""),
      (.rate_limits.five_hour.used_percentage // ""),
      (.rate_limits.seven_day.used_percentage // ""),
      (.rate_limits.five_hour.resets_at // "")
    ] | map(tostring) | join("\u001f")
  ' 2>/dev/null
)"

# ---------- palette (truecolor) ----------
RESET=$'\033[0m'
COL_GREEN=$'\033[38;2;152;195;121m'   # message green / git clean / ctx <60%
COL_GOLD=$'\033[38;2;188;155;83m'     # git dirty / ctx 60-80%
COL_RED=$'\033[38;2;185;102;82m'      # ctx >80%
COL_GRAY=$'\033[38;2;64;64;64m'       # bar filler / separators
COL_MUTED=$'\033[38;2;150;150;150m'   # secondary text (reset countdown, labels); COL_GRAY is too dark on dark themes
COL_BLUE=$'\033[38;2;97;175;239m'     # project name
COL_PURPLE=$'\033[38;2;198;120;221m'  # daily usage
COL_CYAN=$'\033[38;2;86;182;194m'     # model text
COL_ORANGE=$'\033[38;2;209;154;102m'  # cost

SEP=" ${COL_GRAY}│${RESET} "

line1=""
add1() { if [ -z "$line1" ]; then line1="$1"; else line1="${line1}${SEP}$1"; fi; }

pct_color() {
  if [ "$1" -ge 80 ]; then printf '%s' "$COL_RED"
  elif [ "$1" -ge 60 ]; then printf '%s' "$COL_GOLD"
  else printf '%s' "$COL_GREEN"; fi
}

HOME_DIR="${HOME:-$(cd; pwd)}"

# ================= 1. model + reasoning effort =================
if [ -n "$MODEL_NAME" ]; then
  model_lc=$(printf '%s' "$MODEL_NAME" | tr '[:upper:]' '[:lower:]')
  icon="🔷"
  case "$model_lc" in
    *opus*)   icon="💛" ;;
    *sonnet*) icon="💠" ;;
    *haiku*)  icon="🌸" ;;
    *fable*)  icon="💜" ;;
  esac
  effort="$EFFORT_LEVEL"
  if [ -z "$effort" ]; then
    effort=$(jq -r '.effortLevel // empty' "$HOME_DIR/.claude/settings.json" 2>/dev/null)
  fi
  if [ -n "$effort" ] && [ "$effort" != "null" ]; then
    add1 "${COL_CYAN}${icon} ${MODEL_NAME} · ${effort}${RESET}"
  else
    add1 "${COL_CYAN}${icon} ${MODEL_NAME}${RESET}"
  fi
fi

# ================= 2. project name =================
if [ -n "$PROJECT_DIR" ]; then
  project_name=$(basename "$PROJECT_DIR")
  add1 "${COL_BLUE}📁 ${project_name}${RESET}"
fi

# ================= 3. git branch (5s TTL cache, keyed by dir) =================
if [ -n "$PROJECT_DIR" ]; then
  cache_dir="$HOME_DIR/.claude/cache"
  mkdir -p "$cache_dir" 2>/dev/null
  cache_file="$cache_dir/git_branch_counts"
  now_ts=$(date +%s)

  cached_ts="" ; cached_dir="" ; cached_branch="" ; cached_dirty=""
  if [ -f "$cache_file" ]; then
    cached_ts=$(sed -n '1p' "$cache_file" 2>/dev/null)
    cached_dir=$(sed -n '2p' "$cache_file" 2>/dev/null)
    cached_branch=$(sed -n '3p' "$cache_file" 2>/dev/null)
    cached_dirty=$(sed -n '4p' "$cache_file" 2>/dev/null)
  fi
  case "$cached_ts" in ''|*[!0-9]*) cached_ts=0 ;; esac

  fresh=0
  if [ "$cached_dir" = "$PROJECT_DIR" ]; then
    age=$(( now_ts - cached_ts ))
    if [ "$age" -ge 0 ] && [ "$age" -lt 5 ]; then
      fresh=1
    fi
  fi

  if [ "$fresh" -eq 1 ]; then
    branch="$cached_branch"
    dirty="$cached_dirty"
  else
    branch=""
    dirty=""
    if git --no-optional-locks -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      branch=$(git --no-optional-locks -C "$PROJECT_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null)
      if [ -z "$branch" ]; then
        branch=$(git --no-optional-locks -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null)
      fi
      # raw per-file counts from porcelain XY codes ("added modified deleted untracked"),
      # formatted at display time so the cache stays colour-agnostic
      dirty=$(git --no-optional-locks -C "$PROJECT_DIR" status --porcelain 2>/dev/null | awk '
        { xy = substr($0, 1, 2); x = substr(xy, 1, 1); y = substr(xy, 2, 1)
          if (xy == "??") u++
          else if (x == "D" || y == "D") d++
          else if (x == "A") a++
          else m++ }
        END { printf "%d %d %d %d", a, m, d, u }')
      # "behind ahead" vs upstream; empty when no upstream is configured
      sync=$(git --no-optional-locks -C "$PROJECT_DIR" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null | tr '\t' ' ')
      dirty="${dirty} ${sync:-0 0}"
    fi
    printf '%s\n%s\n%s\n%s\n' "$now_ts" "$PROJECT_DIR" "$branch" "$dirty" > "$cache_file" 2>/dev/null
  fi

  if [ -n "$branch" ]; then
    # p10k-style: each change type keeps its own colour so the state reads at a glance
    read -r g_add g_mod g_del g_unt g_behind g_ahead <<< "$dirty"
    g_stat=""
    g_seg() { [ "${1:-0}" -gt 0 ] 2>/dev/null && g_stat="${g_stat} ${2}${3}${1}${RESET}"; }
    g_seg "$g_ahead"  "$COL_CYAN"  "⇡"
    g_seg "$g_behind" "$COL_CYAN"  "⇣"
    g_seg "$g_add"    "$COL_GREEN" "+"
    g_seg "$g_mod"    "$COL_GOLD"  "~"
    g_seg "$g_del"    "$COL_RED"   "-"
    g_seg "$g_unt"    "$COL_BLUE"  "?"
    if [ $(( ${g_add:-0} + ${g_mod:-0} + ${g_del:-0} + ${g_unt:-0} )) -gt 0 ]; then
      add1 "${COL_GOLD}⚡ ${branch}${RESET}${g_stat}"
    else
      add1 "${COL_GREEN}⚡ ${branch}${RESET}${g_stat}"
    fi
  fi
fi

# ================= 4. context window usage =================
tokens="$CTX_TOTAL"
window="$CTX_SIZE"
pct="$CTX_PCT"

if [ -z "$tokens" ] || [ -z "$window" ]; then
  # fallback: derive from the transcript JSONL (last ~100 lines)
  if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    usage_json=$(tail -n 100 "$TRANSCRIPT_PATH" 2>/dev/null | jq -c --arg sid "$SESSION_ID" '
      select((.isSidechain // false) == false and .sessionId == $sid and (.message.usage != null))
    ' 2>/dev/null | tail -n 1)
    if [ -n "$usage_json" ]; then
      tokens=$(printf '%s' "$usage_json" | jq -r '
        (.message.usage.input_tokens // 0) + (.message.usage.cache_read_input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0)
      ' 2>/dev/null)
      window=200000
    fi
  fi
fi

case "$tokens" in ''|*[!0-9]*) tokens="" ;; esac
case "$window" in ''|*[!0-9.]*) window="" ;; esac

if [ -n "$tokens" ] && [ -n "$window" ] && [ "${window%.*}" != "0" ]; then
  if [ -z "$pct" ] || [ "$pct" = "null" ]; then
    pct=$(( tokens * 100 / ${window%.*} ))
  else
    pct=$(printf '%.0f' "$pct" 2>/dev/null)
  fi
  case "$pct" in ''|*[!0-9]*) pct=0 ;; esac
  [ "$pct" -gt 100 ] && pct=100

  if [ "$pct" -ge 80 ]; then
    ctx_color="$COL_RED"
  elif [ "$pct" -ge 60 ]; then
    ctx_color="$COL_GOLD"
  else
    ctx_color="$COL_GREEN"
  fi

  fmt_tokens() {
    local n="$1"
    if [ "$n" -ge 1000000 ]; then
      awk -v n="$n" 'BEGIN{printf "%.1fM", n/1000000}'
    elif [ "$n" -ge 1000 ]; then
      awk -v n="$n" 'BEGIN{printf "%.1fk", n/1000}'
    else
      printf '%s' "$n"
    fi
  }
  tok_disp=$(fmt_tokens "$tokens")
  win_disp=$(fmt_tokens "${window%.*}")

  bar_len=10
  filled=$(( pct * bar_len / 100 ))
  [ "$filled" -gt "$bar_len" ] && filled=$bar_len
  [ "$filled" -lt 0 ] && filled=0
  empty=$(( bar_len - filled ))

  bar="${ctx_color}"
  i=0; while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i+1)); done
  bar="${bar}${COL_GRAY}"
  i=0; while [ "$i" -lt "$empty" ]; do bar="${bar}░"; i=$((i+1)); done
  bar="${bar}${RESET}"

  add1 "${ctx_color}🧠${RESET} ${bar} ${ctx_color}${pct}% (${tok_disp}/${win_disp})${RESET}"
fi

# ================= 5. session cost =================
if [ -n "$COST_USD" ] && [ "$COST_USD" != "null" ]; then
  cost_fmt=$(printf '$%.2f' "$COST_USD" 2>/dev/null)
  [ -n "$cost_fmt" ] && add1 "${COL_ORANGE}💰 ${cost_fmt}${RESET}"
fi

# ================= 5b. rate limits: 5h + weekly, model-aware =================
# 5h / weekly-all come free from the stdin payload. The model-scoped weekly
# bucket (e.g. Fable) only exists in the OAuth usage API, so that is fetched
# through a 60s-TTL cache with a 2s curl timeout; every failure degrades to
# the generic payload numbers, never an error on the line.
usage_cache="$HOME_DIR/.claude/cache/oauth_usage.json"
attempt_marker="$HOME_DIR/.claude/cache/oauth_usage.attempt"

file_age() {
  local m
  m=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null)
  case "$m" in ''|*[!0-9]*) printf '%s' 999999; return ;; esac
  printf '%s' $(( $(date +%s) - m ))
}

if [ ! -f "$attempt_marker" ] || [ "$(file_age "$attempt_marker")" -ge 60 ]; then
  touch "$attempt_marker" 2>/dev/null
  # keychain first (macOS default), .credentials.json as fallback; alarm guards
  # against a keychain GUI prompt hanging the statusline
  token=$(perl -e 'alarm 2; exec @ARGV' security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  if [ -z "$token" ] && [ -f "$HOME_DIR/.claude/.credentials.json" ]; then
    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME_DIR/.claude/.credentials.json" 2>/dev/null)
  fi
  if [ -n "$token" ]; then
    if curl -sS -m 2 https://api.anthropic.com/api/oauth/usage \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -o "${usage_cache}.tmp" 2>/dev/null \
       && jq -e '.limits' "${usage_cache}.tmp" >/dev/null 2>&1; then
      mv "${usage_cache}.tmp" "$usage_cache" 2>/dev/null
    else
      rm -f "${usage_cache}.tmp" 2>/dev/null
    fi
  fi
  token=""
fi

five_pct=$(printf '%.0f' "$RL_5H" 2>/dev/null)
weekly_pct=$(printf '%.0f' "$RL_7D" 2>/dev/null)
weekly_label="1w"

if [ -f "$usage_cache" ]; then
  if [ -z "$five_pct" ]; then
    five_pct=$(jq -r '[.limits[]? | select(.kind == "session")] | first | .percent // empty' "$usage_cache" 2>/dev/null)
  fi
  if [ -z "$weekly_pct" ]; then
    weekly_pct=$(jq -r '[.limits[]? | select(.kind == "weekly_all")] | first | .percent // empty' "$usage_cache" 2>/dev/null)
  fi
  # smart switch: a weekly bucket scoped to the current model wins over weekly-all
  if [ -n "$MODEL_NAME" ]; then
    scoped=$(jq -r --arg model "$MODEL_NAME" '
      ($model | ascii_downcase) as $m
      | [.limits[]?
         | select(.kind == "weekly_scoped")
         | ((.scope.model.display_name // "") | tostring) as $n
         | ($n | ascii_downcase) as $nl
         | select($n != "" and (($m | contains($nl)) or ($nl | contains($m))))]
      | first
      | if . == null then empty else "\(.scope.model.display_name)\(.percent)" end
    ' "$usage_cache" 2>/dev/null)
    if [ -n "$scoped" ]; then
      IFS=$'\x1f' read -r s_name s_pct <<< "$scoped"
      s_pct=$(printf '%.0f' "$s_pct" 2>/dev/null)
      case "$s_pct" in ''|*[!0-9]*) : ;; *) weekly_pct="$s_pct" ;; esac
    fi
  fi
fi

# countdown until the 5h window resets (payload resets_at is epoch seconds)
reset_str=""
rl_reset=$(printf '%.0f' "$RL_5H_RESET" 2>/dev/null)
case "$rl_reset" in ''|*[!0-9]*) : ;; *)
  left=$(( rl_reset - $(date +%s) ))
  if [ "$left" -gt 0 ]; then
    lh=$(( left / 3600 )); lm=$(( (left % 3600) / 60 ))
    if [ "$lh" -gt 0 ]; then reset_str="${lh}h${lm}m"; else reset_str="${lm}m"; fi
  fi
;; esac

# the API reports used %, but remaining is what matters when pacing a window
to_remaining() {
  case "$1" in ''|*[!0-9]*) return ;; esac
  local r=$(( 100 - $1 ))
  [ "$r" -lt 0 ] && r=0
  printf '%s' "$r"
}
five_pct=$(to_remaining "$five_pct")
weekly_pct=$(to_remaining "$weekly_pct")

# same thresholds as pct_color, mirrored: <=20% left red, <=40% left gold
rem_color() { pct_color $(( 100 - $1 )); }

rl_seg=""
case "$five_pct" in ''|*[!0-9]*) : ;; *)
  rl_seg="$(rem_color "$five_pct")5h ${five_pct}%${RESET}"
  [ -n "$reset_str" ] && rl_seg="${rl_seg} ${COL_MUTED}(${reset_str})${RESET}"
;; esac
case "$weekly_pct" in ''|*[!0-9]*) : ;; *)
  w_seg="$(rem_color "$weekly_pct")${weekly_label} ${weekly_pct}%${RESET}"
  if [ -n "$rl_seg" ]; then rl_seg="${rl_seg} ${COL_MUTED}·${RESET} ${w_seg}"; else rl_seg="$w_seg"; fi
;; esac
[ -n "$rl_seg" ] && add1 "🔋 ${rl_seg} ${COL_MUTED}left${RESET}"

output="$line1"

# ================= 6. last prompt duration + last user instruction (up to 3 lines) =================
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # Slurp the tail once: find the last real prompt, then look after it for the
  # turn_duration record (finished) or an interrupt marker (aborted). Neither
  # means the turn is still running, so the clock keeps ticking from the prompt.
  last_prompt_json=$(tail -n 400 "$TRANSCRIPT_PATH" 2>/dev/null | jq -c -s --arg sid "$SESSION_ID" '
    def ts: (.timestamp // "") | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch null);
    def text: .message.content as $c
      | if ($c | type) == "string" then $c
        elif ($c | type) == "array" then ([$c[]? | select(.type == "text") | .text] | join("\n"))
        else "" end;
    [.[] | select((.isSidechain // false) == false) | select(($sid == "") or (.sessionId == $sid))] as $e
    | ([range(0; $e | length) as $i
        | $e[$i]
        | select(.type == "user" and ((.isMeta // false) == false))
        | text as $t
        | select($t != "")
        | select(($t | test("^\\s*<[A-Za-z-]+>[\\s\\S]*</[A-Za-z-]+>\\s*$")) | not)
        | select(($t | test("^\\s*[\\[{]")) | not)
        | $i] | last) as $pi
    | if $pi == null then empty else
        $e[$pi] as $p
        | $e[$pi + 1:] as $after
        | {
            msg: ($p | text),
            start: ($p | ts),
            dur_ms: ([$after[] | select(.type == "system" and .subtype == "turn_duration") | .durationMs] | first),
            intr: ([$after[] | select(.type == "user") | select(text | test("^\\[Request interrupted")) | ts] | first)
          }
      end
  ' 2>/dev/null)

  last_user_msg="" ; p_start="" ; p_dur_ms="" ; p_intr=""
  if [ -n "$last_prompt_json" ]; then
    IFS=$'\x1f' read -r p_start p_dur_ms p_intr <<< "$(printf '%s' "$last_prompt_json" | jq -r '
      [(.start // ""), (.dur_ms // ""), (.intr // "")] | map(tostring) | join("\u001f")' 2>/dev/null)"
    last_user_msg=$(printf '%s' "$last_prompt_json" | jq -r '.msg // empty' 2>/dev/null)
  fi

  fmt_dur() {
    local s="$1"
    if [ "$s" -ge 3600 ]; then printf '%dh%02dm' $(( s / 3600 )) $(( (s % 3600) / 60 ))
    elif [ "$s" -ge 60 ]; then printf '%dm%02ds' $(( s / 60 )) $(( s % 60 ))
    else printf '%ds' "$s"; fi
  }

  timer=""
  p_start=${p_start%.*}; p_intr=${p_intr%.*}
  case "$p_start" in ''|*[!0-9]*) : ;; *)
    running=0
    case "$p_dur_ms" in
      ''|*[!0-9.]*)
        case "$p_intr" in
          ''|*[!0-9]*) elapsed=$(( $(date +%s) - p_start )); running=1 ;;
          *) elapsed=$(( p_intr - p_start )) ;;
        esac ;;
      *) elapsed=$(( ${p_dur_ms%.*} / 1000 )) ;;
    esac
    [ "$elapsed" -lt 0 ] && elapsed=0
    if [ "$running" -eq 1 ]; then
      # hourglass flips every second; relies on statusLine.refreshInterval
      glasses=(⏳ ⌛)
      timer="${COL_GOLD}${glasses[$(( $(date +%s) % 2 ))]} $(fmt_dur "$elapsed")…${RESET} "
    else
      timer="${COL_PURPLE}🏁 $(fmt_dur "$elapsed")${RESET} "
    fi
  ;; esac

  if [ -n "$last_user_msg" ]; then
    msg_lines=""
    n=0
    while IFS= read -r uline && [ "$n" -lt 3 ]; do
      n=$((n+1))
      trimmed=$(printf '%s' "$uline" | cut -c1-80)
      if [ "${#uline}" -gt 80 ]; then trimmed="${trimmed}…"; fi
      if [ -z "$msg_lines" ]; then
        msg_lines="${timer}${COL_GRAY}｜${COL_GREEN}${trimmed}${RESET}"
      else
        msg_lines="${msg_lines}"$'\n'"${COL_GRAY}｜${COL_GREEN}${trimmed}${RESET}"
      fi
    done <<__CC_STATUSLINE_EOF__
$last_user_msg
__CC_STATUSLINE_EOF__
    if [ -n "$msg_lines" ]; then
      output="${output}"$'\n'"${msg_lines}"
    fi
  fi
fi

printf '%s' "$output"
