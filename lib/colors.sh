#!/usr/bin/env bash
# TgWebProxyR — UI helpers

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[38;5;203m'
  C_GREEN=$'\033[38;5;114m'
  C_YELLOW=$'\033[38;5;221m'
  C_CYAN=$'\033[38;5;80m'
  C_GRAY=$'\033[38;5;245m'
  C_ACCENT=$'\033[38;5;44m'
else
  C_RESET= C_BOLD= C_DIM= C_RED= C_GREEN= C_YELLOW=
  C_CYAN= C_GRAY= C_ACCENT=
fi

TWPR_banner() {
  echo ""
  echo -e "${C_ACCENT}${C_BOLD}  TgWebProxyR${C_RESET}  ${C_DIM}v${TWPR_VERSION:-?} · Telegram WEB Proxy${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
}

TWPR_ok()   { echo -e "  ${C_GREEN}OK${C_RESET}  $*"; }
TWPR_info() { echo -e "  ${C_CYAN}>>${C_RESET} $*"; }
TWPR_warn() { echo -e "  ${C_YELLOW}!!${C_RESET} $*"; }
TWPR_err()  { echo -e "  ${C_RED}XX${C_RESET} $*" >&2; }

TWPR_step() {
  local n="$1" total="$2" title="$3"
  echo ""
  echo -e "  ${C_BOLD}${C_ACCENT}Шаг ${n}/${total}${C_RESET}  ${C_BOLD}${title}${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
}

# curl|bash closes stdin — always read prompts from the real TTY
TWPR_stdin() {
  if [[ -r /dev/tty ]]; then
    echo /dev/tty
  else
    echo /dev/stdin
  fi
}

TWPR_ask() {
  # Usage: TWPR_ask VAR "prompt" ["default"]
  local __var="$1" __prompt="$2" __default="${3-}" __reply="" __in __tries=0
  __in="$(TWPR_stdin)"
  while true; do
    __tries=$((__tries + 1))
    if [[ -n "$__default" ]]; then
      if ! read -r -p "  ${__prompt} [${__default}]: " __reply <"$__in"; then
        __reply="$__default"
      else
        __reply="${__reply:-$__default}"
      fi
    else
      if ! read -r -p "  ${__prompt}: " __reply <"$__in"; then
        TWPR_err "Нет ввода с терминала (EOF)."
        TWPR_err "Не используйте: curl … | bash"
        TWPR_err "Запускайте: wget -qO /tmp/i.sh URL && sudo bash /tmp/i.sh"
        exit 1
      fi
    fi
    # trim spaces without forking sed
    __reply="${__reply#"${__reply%%[![:space:]]*}"}"
    __reply="${__reply%"${__reply##*[![:space:]]}"}"
    if [[ -n "$__reply" ]]; then
      printf -v "$__var" '%s' "$__reply"
      return 0
    fi
    if [[ "$__tries" -ge 5 ]]; then
      TWPR_err "Слишком много пустых ответов — выход"
      exit 1
    fi
    TWPR_warn "Пустое значение — введите ещё раз"
  done
}

TWPR_ask_yn() {
  # Usage: TWPR_ask_yn VAR "prompt" ["Y"|"n"]
  local __var="$1" __prompt="$2" __default="${3:-Y}" __reply="" __in __hint
  __in="$(TWPR_stdin)"
  [[ "$__default" =~ ^[Yy]$ ]] && __hint="Y/n" || __hint="y/N"
  if ! read -r -p "  ${__prompt} [${__hint}]: " __reply <"$__in"; then
    __reply="$__default"
  else
    __reply="${__reply:-$__default}"
  fi
  if [[ "$__reply" =~ ^[Yy]$ ]]; then
    printf -v "$__var" '%s' "yes"
  else
    printf -v "$__var" '%s' "no"
  fi
}

TWPR_pause() {
  echo ""
  local __in
  __in="$(TWPR_stdin)"
  read -r -p "  ${C_DIM}Enter — продолжить${C_RESET} " _ <"$__in" || true
}
