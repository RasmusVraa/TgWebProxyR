#!/usr/bin/env bash
# WebProxyL — terminal colors and UI helpers

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[38;5;203m'
  C_GREEN=$'\033[38;5;114m'
  C_YELLOW=$'\033[38;5;221m'
  C_BLUE=$'\033[38;5;75m'
  C_CYAN=$'\033[38;5;80m'
  C_MAGENTA=$'\033[38;5;176m'
  C_WHITE=$'\033[38;5;255m'
  C_GRAY=$'\033[38;5;245m'
  C_ACCENT=$'\033[38;5;44m'
else
  C_RESET= C_BOLD= C_DIM= C_RED= C_GREEN= C_YELLOW=
  C_BLUE= C_CYAN= C_MAGENTA= C_WHITE= C_GRAY= C_ACCENT=
fi

wpl_banner() {
  echo ""
  echo -e "${C_ACCENT}${C_BOLD}"
  cat <<'EOF'
   ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
   ┃          W e b P r o x y L               ┃
   ┃   Telegram WEB Proxy · one-click setup   ┃
   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
EOF
  echo -e "${C_RESET}${C_DIM}   engine: telegramdesktop/tproxy-server · manager v${WPL_VERSION:-?}${C_RESET}"
  echo ""
}

wpl_ok()   { echo -e "  ${C_GREEN}✓${C_RESET} $*"; }
wpl_info() { echo -e "  ${C_CYAN}•${C_RESET} $*"; }
wpl_warn() { echo -e "  ${C_YELLOW}!${C_RESET} $*"; }
wpl_err()  { echo -e "  ${C_RED}✗${C_RESET} $*" >&2; }
wpl_sec()  { echo -e "\n  ${C_BOLD}${C_ACCENT}$*${C_RESET}\n  ${C_GRAY}$(printf '─%.0s' {1..42})${C_RESET}"; }

wpl_prompt() {
  local prompt="$1" default="${2:-}" reply
  if [[ -n "$default" ]]; then
    read -r -p "  ${prompt} [${default}]: " reply || true
    echo "${reply:-$default}"
  else
    read -r -p "  ${prompt}: " reply || true
    echo "$reply"
  fi
}

wpl_prompt_secret() {
  local prompt="$1" reply
  read -r -s -p "  ${prompt}: " reply || true
  echo "" >&2
  echo "$reply"
}

wpl_confirm() {
  local prompt="$1" default="${2:-Y}" reply
  read -r -p "  ${prompt} [${default}/n]: " reply || true
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy]$ ]]
}

wpl_pause() {
  read -r -p "  ${C_DIM}Enter — продолжить${C_RESET} " _ || true
}
