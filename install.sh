#!/usr/bin/env bash
# ============================================================
# DoubleEdge — environment bootstrap
#
# requirements.txt を解析し、不足している依存（system / npm / manual）を
# 導入する。さらに .env を .env.example から用意して DeepSeek キー記入を促す。
#
# Usage:
#   ./install.sh            # 依存チェック + 導入 + .env 準備
#   ./install.sh --check    # チェックのみ（導入しない / CI 向け）
#   ./install.sh --yes      # 確認プロンプトをスキップして導入
# ============================================================

set -euo pipefail

# ── config ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQ_FILE="${SCRIPT_DIR}/requirements.txt"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"

CHECK_ONLY=false
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --yes|-y) ASSUME_YES=true ;;
    -h|--help)
      grep -E '^#( |$)' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) ;;
  esac
done

# ── colours ─────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${CYAN}[install]${NC} $*"; }
ok()   { echo -e "${GREEN}[ ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
die()  { echo -e "${RED}[fail]${NC} $*" >&2; exit 1; }

[[ -f "${REQ_FILE}" ]] || die "requirements.txt not found at ${REQ_FILE}"

# ── detect OS package manager ───────────────────────────────
PKG_MGR=""
PKG_INSTALL=""
detect_pkg_mgr() {
  if   command -v apt-get &>/dev/null; then PKG_MGR="apt";    PKG_INSTALL="sudo apt-get install -y"
  elif command -v brew    &>/dev/null; then PKG_MGR="brew";   PKG_INSTALL="brew install"
  elif command -v dnf     &>/dev/null; then PKG_MGR="dnf";    PKG_INSTALL="sudo dnf install -y"
  elif command -v pacman  &>/dev/null; then PKG_MGR="pacman"; PKG_INSTALL="sudo pacman -S --noconfirm"
  else PKG_MGR=""; fi
}
detect_pkg_mgr

# ── version compare (returns 0 if $1 >= $2) ─────────────────
version_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]
}

# ── confirm helper ──────────────────────────────────────────
confirm() {
  $ASSUME_YES && return 0
  local ans
  read -rp "  $1 [Y/n] " ans
  [[ "${ans:-Y}" =~ ^[Yy]$ ]]
}

# ── trackers ────────────────────────────────────────────────
MISSING=()
INSTALLED=()
MANUAL=()
FAILED=()

# ── per-method installers ───────────────────────────────────
install_system() {
  local name="$1" pkg="$2"
  if [[ -z "${PKG_MGR}" ]]; then
    warn "no supported package manager — install '${pkg}' manually"
    MANUAL+=("${name} (system: ${pkg})")
    return
  fi
  if $CHECK_ONLY; then MISSING+=("${name} (${PKG_MGR}: ${pkg})"); return; fi
  if confirm "install ${name} via ${PKG_MGR} (${pkg})?"; then
    if ${PKG_INSTALL} "${pkg}"; then INSTALLED+=("${name}"); else FAILED+=("${name}"); fi
  else
    MANUAL+=("${name} (system: ${pkg})")
  fi
}

install_npm() {
  local name="$1" pkg="$2"
  command -v npm &>/dev/null || { warn "npm not found — install Node.js first (needed for ${name})"; MANUAL+=("${name} (npm: ${pkg}; install Node.js first)"); return; }
  if $CHECK_ONLY; then MISSING+=("${name} (npm: ${pkg})"); return; fi
  if confirm "install ${name} via npm i -g ${pkg}?"; then
    if npm install -g "${pkg}"; then INSTALLED+=("${name}"); else FAILED+=("${name}"); fi
  else
    MANUAL+=("${name} (npm: ${pkg})")
  fi
}

install_manual() {
  local name="$1" hint="$2"
  warn "${name}: manual install required — ${hint}"
  MANUAL+=("${name} (${hint})")
}

# ── parse requirements.txt ──────────────────────────────────
log "Reading requirements from ${REQ_FILE}"
[[ -n "${PKG_MGR}" ]] && log "Package manager: ${PKG_MGR}" || warn "No supported package manager detected (apt/brew/dnf/pacman)"
echo ""

while read -r name method pkg minver _rest || [[ -n "${name:-}" ]]; do
  # strip comments / blank lines
  [[ -z "${name:-}" || "${name:0:1}" == "#" ]] && continue
  # drop inline comment tokens from pkg/minver
  [[ "${pkg:-}" == "#"* ]] && pkg=""
  [[ "${minver:-}" == "#"* ]] && minver=""

  if command -v "${name}" &>/dev/null; then
    if [[ -n "${minver:-}" ]]; then
      have="$("${name}" -V 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1 || true)"
      if [[ -n "${have}" ]] && ! version_ge "${have}" "${minver}"; then
        warn "${name} ${have} < required ${minver}"
        MISSING+=("${name} (have ${have}, need >= ${minver})")
        continue
      fi
      ok "${name} present (${have:-version unknown})"
    else
      ok "${name} present"
    fi
    continue
  fi

  warn "${name} missing"
  case "${method}" in
    system) install_system "${name}" "${pkg}" ;;
    npm)    install_npm    "${name}" "${pkg}" ;;
    manual) install_manual "${name}" "${pkg}" ;;
    *)      warn "unknown method '${method}' for ${name} — skipping" ;;
  esac
done < "${REQ_FILE}"

# ── .env setup ──────────────────────────────────────────────
echo ""
log "Checking .env"
if [[ -f "${ENV_FILE}" ]]; then
  ok ".env already exists"
  if grep -qE '^DEEPSEEK_API_KEY=.+' "${ENV_FILE}"; then
    ok "DEEPSEEK_API_KEY is set"
  else
    warn "DEEPSEEK_API_KEY is empty in .env — DS (cline) will fail to authenticate"
  fi
elif [[ -f "${ENV_EXAMPLE}" ]]; then
  if $CHECK_ONLY; then
    warn ".env not found (run without --check to create it from .env.example)"
  else
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"
    ok "created .env from .env.example"
    warn "edit .env and set DEEPSEEK_API_KEY before running ./setup-doubleedge.sh"
  fi
else
  warn ".env.example not found — cannot scaffold .env"
fi

# ── summary ─────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── summary ──────────────────────────────────${NC}"
[[ ${#INSTALLED[@]} -gt 0 ]] && { echo -e "${GREEN}installed:${NC}"; printf '  - %s\n' "${INSTALLED[@]}"; }
[[ ${#MISSING[@]}   -gt 0 ]] && { echo -e "${YELLOW}missing  :${NC}"; printf '  - %s\n' "${MISSING[@]}"; }
[[ ${#MANUAL[@]}    -gt 0 ]] && { echo -e "${YELLOW}manual   :${NC}"; printf '  - %s\n' "${MANUAL[@]}"; }
[[ ${#FAILED[@]}    -gt 0 ]] && { echo -e "${RED}failed   :${NC}";   printf '  - %s\n' "${FAILED[@]}"; }

if [[ ${#FAILED[@]} -gt 0 ]]; then
  die "some installs failed — see above"
fi
if $CHECK_ONLY && [[ ${#MISSING[@]} -gt 0 ]]; then
  die "missing dependencies (--check mode)"
fi

echo ""
ok "done. next: edit .env, then run ./setup-doubleedge.sh"
