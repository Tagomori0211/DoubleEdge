#!/usr/bin/env bash
# ============================================================
# DoubleEdge — tmux-based multi-agent orchestration loop
#
# Architecture:
#   pane 0 : DS    — DeepSeek V4 Pro (Cline CLI / .clinerules)
#   pane 1 : BLADE — Claude Code (interactive, subscription quota)
#   pane 2 : AG-1  — agy subagent  ROLE: Implementer (speed-first)
#   pane 3 : AG-2  — agy subagent  ROLE: Auditor    (GOZEN adversarial)
#   pane 4 : AG-3  — agy subagent  ROLE: Alternative (different approach)
#   pane 5 : WATCH — watchdog (quota grep, no token cost)
#
# Usage:
#   ./setup-doubleedge.sh [session_name]   # default: doubleedge
#   ./setup-doubleedge.sh --kill           # destroy session
# ============================================================

set -euo pipefail

# ── config ──────────────────────────────────────────────────
SESSION="${1:-doubleedge}"
WORKDIR="${DOUBLEEDGE_WORKDIR:-$(pwd)}"
WATCH_INTERVAL=30   # quota grep interval (seconds)
LOG_DIR="${WORKDIR}/.doubleedge/logs"
SIGNAL_FILE="${WORKDIR}/.doubleedge/stop_signal"

# quota / session-limit error patterns (exact strings from each CLI)
QUOTA_PATTERNS=(
  "Individual quota reached"        # agy Pro
  "quota reached"                   # agy generic
  "You've hit your session limit"   # claude code
  "You've hit your weekly limit"    # claude code
  "You've hit your Opus limit"      # claude code
)

# ── colours ─────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${CYAN}[DoubleEdge]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── kill flag ────────────────────────────────────────────────
if [[ "${1:-}" == "--kill" ]]; then
  log "Destroying session '${SESSION}'..."
  tmux kill-session -t "${SESSION}" 2>/dev/null && log "Done." || warn "Session not found."
  exit 0
fi

# ── preflight checks ─────────────────────────────────────────
command -v tmux  &>/dev/null || die "tmux not found"
command -v cline &>/dev/null || die "cline CLI not found (npm i -g cline)"
command -v agy   &>/dev/null || die "agy not found (install Antigravity CLI)"
command -v claude &>/dev/null || die "claude not found (install Claude Code)"

if tmux has-session -t "${SESSION}" 2>/dev/null; then
  warn "Session '${SESSION}' already exists."
  read -rp "  Attach to existing session? [Y/n] " ans
  if [[ "${ans:-Y}" =~ ^[Yy]$ ]]; then
    tmux attach-session -t "${SESSION}"
    exit 0
  else
    tmux kill-session -t "${SESSION}"
    log "Old session destroyed. Recreating..."
  fi
fi

# ── directory setup ──────────────────────────────────────────
mkdir -p "${LOG_DIR}"
rm -f "${SIGNAL_FILE}"

# ── watchdog script (written to disk, runs in pane 5) ────────
WATCHDOG_SCRIPT="${WORKDIR}/.doubleedge/watchdog.sh"
mkdir -p "$(dirname "${WATCHDOG_SCRIPT}")"
cat > "${WATCHDOG_SCRIPT}" << 'WATCHDOG_EOF'
#!/usr/bin/env bash
# DoubleEdge watchdog — quota sentinel
# Runs in pane 5. No LLM calls, no token cost.

SESSION="$1"
INTERVAL="$2"
SIGNAL_FILE="$3"
LOG_DIR="$4"

QUOTA_PATTERNS=(
  "Individual quota reached"
  "quota reached"
  "You've hit your session limit"
  "You've hit your weekly limit"
  "You've hit your Opus limit"
)

# pane index → friendly name
declare -A PANE_NAME=([1]="BLADE(Claude)" [2]="AG-1" [3]="AG-2" [4]="AG-3")

ts() { date '+%H:%M:%S'; }

echo "[watchdog] $(ts) started — interval ${INTERVAL}s, watching panes 1-4"

while true; do
  sleep "${INTERVAL}"

  for idx in 1 2 3 4; do
    output=$(tmux capture-pane -t "${SESSION}:0.${idx}" -p 2>/dev/null) || continue
    [[ -z "$output" ]] && continue

    for pattern in "${QUOTA_PATTERNS[@]}"; do
      if echo "$output" | grep -qF "$pattern"; then
        name="${PANE_NAME[$idx]:-pane${idx}}"
        reset_hint=$(echo "$output" | grep -oP 'Resets in [^\n]+' | head -1 || \
                     echo "$output" | grep -oP 'resets [^\n]+' | head -1 || \
                     echo "reset time unknown")

        msg="STOP_SIGNAL:QUOTA pane=${idx} tool=${name} pattern='${pattern}' ${reset_hint}"

        # write to signal file
        echo "$(ts) ${msg}" >> "${SIGNAL_FILE}"
        echo "$(ts) ${msg}" >> "${LOG_DIR}/watchdog.log"

        # notify DS pane (pane 0) via send-keys
        tmux send-keys -t "${SESSION}:0.0" "" ""   # wake cursor
        tmux send-keys -t "${SESSION}:0.0" \
          "[DoubleEdge watchdog] ${msg}" Enter

        echo "[watchdog] $(ts) STOP_SIGNAL sent for ${name}"
        break
      fi
    done
  done
done
WATCHDOG_EOF
chmod +x "${WATCHDOG_SCRIPT}"

# ── build tmux session ────────────────────────────────────────
log "Creating tmux session '${SESSION}' in ${WORKDIR}..."

# pane 0: DS / Cline — main window
tmux new-session -d -s "${SESSION}" -n "main" -c "${WORKDIR}"

# pane 1: BLADE — Claude Code (interactive, subscription quota)
tmux split-window -t "${SESSION}:0" -v -c "${WORKDIR}"

# pane 2: AG-1 Implementer
tmux split-window -t "${SESSION}:0" -h -c "${WORKDIR}"

# pane 3: AG-2 Auditor
tmux select-pane -t "${SESSION}:0.0"
tmux split-window -t "${SESSION}:0" -h -c "${WORKDIR}"

# pane 4: AG-3 Alternative  ─ split from pane 1
tmux select-pane -t "${SESSION}:0.1"
tmux split-window -t "${SESSION}:0.1" -h -c "${WORKDIR}"

# pane 5: watchdog ─ small strip at the bottom
tmux select-pane -t "${SESSION}:0.0"
tmux split-window -t "${SESSION}:0" -v -l 4 -c "${WORKDIR}"

# ── layout tidy-up ────────────────────────────────────────────
tmux select-layout -t "${SESSION}:0" tiled

# ── pane titles ──────────────────────────────────────────────
tmux select-pane -t "${SESSION}:0.0" -T "DS | DeepSeek V4 Pro"
tmux select-pane -t "${SESSION}:0.1" -T "BLADE | Claude Code"
tmux select-pane -t "${SESSION}:0.2" -T "AG-1 | Implementer"
tmux select-pane -t "${SESSION}:0.3" -T "AG-2 | Auditor (GOZEN)"
tmux select-pane -t "${SESSION}:0.4" -T "AG-3 | Alternative"
tmux select-pane -t "${SESSION}:0.5" -T "WATCH | quota watchdog"

# ── start agents ─────────────────────────────────────────────

# pane 0: DS — Cline CLI with .clinerules
log "Starting DS (Cline) in pane 0..."
tmux send-keys -t "${SESSION}:0.0" \
  "echo '[DS] DeepSeek V4 Pro — control plane ready'; cline" Enter

# pane 1: BLADE — Claude Code interactive (subscription quota)
log "Starting Claude Code (interactive) in pane 1..."
tmux send-keys -t "${SESSION}:0.1" \
  "echo '[BLADE] Claude Code — integration layer ready'; claude" Enter

# pane 2: AG-1 Implementer (agy — waits for DS prompt)
log "Starting agy AG-1 (Implementer) in pane 2..."
tmux send-keys -t "${SESSION}:0.2" \
  "echo '[AG-1] agy Implementer — standby'; agy" Enter

# pane 3: AG-2 Auditor (agy — GOZEN adversarial role)
log "Starting agy AG-2 (Auditor) in pane 3..."
tmux send-keys -t "${SESSION}:0.3" \
  "echo '[AG-2] agy Auditor (GOZEN) — standby'; agy" Enter

# pane 4: AG-3 Alternative (agy — different approach)
log "Starting agy AG-3 (Alternative) in pane 4..."
tmux send-keys -t "${SESSION}:0.4" \
  "echo '[AG-3] agy Alternative — standby'; agy" Enter

# pane 5: watchdog
log "Starting quota watchdog in pane 5..."
tmux send-keys -t "${SESSION}:0.5" \
  "bash '${WATCHDOG_SCRIPT}' '${SESSION}' '${WATCH_INTERVAL}' '${SIGNAL_FILE}' '${LOG_DIR}'" Enter

# ── focus back to DS pane ────────────────────────────────────
tmux select-pane -t "${SESSION}:0.0"

# ── print session map ────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}DoubleEdge session '${SESSION}' ready.${NC}"
echo -e "  ${CYAN}pane 0${NC}  DS      DeepSeek V4 Pro  (Cline / .clinerules)"
echo -e "  ${CYAN}pane 1${NC}  BLADE   Claude Code      (interactive, subscription quota)"
echo -e "  ${CYAN}pane 2${NC}  AG-1    agy Implementer  (speed-first)"
echo -e "  ${CYAN}pane 3${NC}  AG-2    agy Auditor       (GOZEN adversarial)"
echo -e "  ${CYAN}pane 4${NC}  AG-3    agy Alternative  (different approach)"
echo -e "  ${CYAN}pane 5${NC}  WATCH   quota watchdog   (no token cost)"
echo ""
echo -e "  ${YELLOW}Quota patterns monitored:${NC}"
for p in "${QUOTA_PATTERNS[@]}"; do
  echo -e "    grep: '${p}'"
done
echo ""
echo -e "  ${GREEN}Attach:${NC}  tmux attach-session -t ${SESSION}"
echo -e "  ${RED}Kill:${NC}    ./setup-doubleedge.sh --kill"
echo ""

# ── attach ───────────────────────────────────────────────────
tmux attach-session -t "${SESSION}"
