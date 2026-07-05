#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -t 1 || -t 2 ]] && [[ "${NO_COLOR:-0}" != "1" ]]; then
  C_RESET=$'\033[0m'
  C_RED=$'\033[31m'
  C_YELLOW=$'\033[33m'
  C_GREEN=$'\033[32m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_RED=""
  C_YELLOW=""
  C_GREEN=""
  C_CYAN=""
fi

info() { printf '%b[INFO]%b %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok() { printf '%b[OK]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
error() { printf '%b[ERROR]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

on_error() {
  local exit_code="$?"
  local line_no="${BASH_LINENO[0]:-unknown}"
  error "${BASH_SOURCE[1]}:${line_no}: '${BASH_COMMAND}' exited with status ${exit_code}"
}
trap on_error ERR

# Ubuntu 25.10+ can select a coreutils implementation with coreutils-from-*
# packages. Debian and older Ubuntu releases use the GNU implementation in the
# regular coreutils package.
UBUNTU_GNU_COREUTILS_PACKAGES=(
  coreutils
  coreutils-from-gnu
  gnu-coreutils
)

LEGACY_GNU_COREUTILS_PACKAGES=(
  coreutils
)

NON_GNU_COREUTILS_PACKAGES=(
  coreutils-from-uutils
  coreutils-from-busybox
  coreutils-from-toybox
  rust-coreutils
)

GNU_COREUTILS_CHECKS=(
  ls
  cp
  sort
  date
)

FAILURES=()

record_failure() {
  local item=$1
  FAILURES+=("$item")
  error "FAILED: $item"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  local command_name=$1
  local message=$2

  if ! need_cmd "$command_name"; then
    error "$message"
    exit 1
  fi
}

as_root() {
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

is_installed() {
  local package=$1
  dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"
}

apt_has_candidate() {
  local package=$1
  local candidate

  candidate="$(apt-cache policy "$package" | sed -n 's/^[[:space:]]*Candidate: //p' | head -n 1)"
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

non_gnu_removal_targets() {
  local package
  for package in "${NON_GNU_COREUTILS_PACKAGES[@]}"; do
    if is_installed "$package"; then
      printf '%s-\n' "$package"
    fi
  done
}

install_gnu_coreutils() {
  as_root apt-get update || {
    record_failure "apt-get update"
    return 1
  }

  if apt_has_candidate coreutils-from-gnu && apt_has_candidate gnu-coreutils; then
    local removal_targets=()
    local target

    while IFS= read -r target; do
      removal_targets+=("$target")
    done < <(non_gnu_removal_targets)

    info "Switching Ubuntu coreutils selector to GNU"
    # Ubuntu marks the selected coreutils implementation Essential. Allow this
    # only for the selector swap that installs the GNU replacement in the same
    # transaction.
    as_root apt-get install -y --allow-remove-essential "${UBUNTU_GNU_COREUTILS_PACKAGES[@]}" "${removal_targets[@]}" || {
      record_failure "install Ubuntu GNU coreutils packages"
      return 1
    }
    return
  fi

  warn "Ubuntu coreutils selector packages are unavailable; reinstalling the standard GNU coreutils package."
  as_root apt-get install -y --reinstall "${LEGACY_GNU_COREUTILS_PACKAGES[@]}" || {
    record_failure "install standard GNU coreutils package"
    return 1
  }
}

purge_non_gnu_coreutils() {
  local package
  local purge_packages=()

  for package in "${NON_GNU_COREUTILS_PACKAGES[@]}"; do
    if is_installed "$package"; then
      purge_packages+=("$package")
    fi
  done

  if ((${#purge_packages[@]} == 0)); then
    return
  fi

  info "Purging non-GNU coreutils packages: ${purge_packages[*]}"
  as_root apt-get purge -y "${purge_packages[@]}" || record_failure "purge non-GNU coreutils packages"
}

verify_gnu_coreutils() {
  info "Verifying GNU coreutils commands"

  local command_name
  local version_line
  for command_name in "${GNU_COREUTILS_CHECKS[@]}"; do
    if ! need_cmd "$command_name"; then
      record_failure "verify $command_name: command missing"
      continue
    fi

    if ! version_line="$(command "$command_name" --version 2>&1)"; then
      record_failure "verify $command_name --version"
      continue
    fi
    version_line="${version_line%%$'\n'*}"

    if [[ "$version_line" != *"GNU coreutils"* ]]; then
      record_failure "verify $command_name uses GNU coreutils: $version_line"
    fi
  done
}

print_failure_summary() {
  if ((${#FAILURES[@]} == 0)); then
    return 0
  fi

  printf '\nFAILED GNU COREUTILS ITEMS:\n' >&2
  local item
  for item in "${FAILURES[@]}"; do
    printf '  - %s\n' "$item" >&2
  done
  return 1
}

main() {
  require_cmd apt-get "This script expects apt-get and is intended for Debian-based systems."
  require_cmd apt-cache "apt-cache is required to detect available coreutils packages."
  require_cmd dpkg-query "dpkg-query is required to inspect installed coreutils packages."
  if [[ ${EUID} -ne 0 ]]; then
    require_cmd sudo "sudo is required when this script is not run as root."
  fi

  if install_gnu_coreutils; then
    purge_non_gnu_coreutils
  else
    warn "Skipping non-GNU coreutils purge because GNU coreutils installation failed."
  fi
  verify_gnu_coreutils

  if ! print_failure_summary; then
    exit 1
  fi

  ok "GNU core utilities are installed and selected"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
