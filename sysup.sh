#!/usr/bin/env bash
#
# sysup - unattended full system upgrade for Debian / Ubuntu.
#
# Runs start to finish with no prompts: refreshes package lists, upgrades
# everything (including kernel and dependency changes), keeps your existing
# config files, then cleans up.

set -Eeuo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

# Install the `sysup` alias for the invoking user (done before elevating so it
# lands in the right ~/.bashrc).
if [ "${EUID}" -ne 0 ] || [ -z "${SUDO_USER:-}" ]; then
  bashrc="${HOME}/.bashrc"
  if ! grep -qs '^alias sysup=' "${bashrc}"; then
    echo "alias sysup='${SCRIPT_PATH}'" >> "${bashrc}"
    echo "Added 'sysup' alias to ${bashrc} (open a new shell to use it)."
  fi
fi

# Elevate once up front so the run is never interrupted by a sudo password
# prompt or a sudo timeout partway through a long upgrade.
if [ "${EUID}" -ne 0 ]; then
  exec sudo -- "${SCRIPT_PATH}" "$@"
fi

FORCE_UPDATE=0
for arg in "$@"; do
  case "${arg}" in
    -f|--force) FORCE_UPDATE=1 ;;
    -h|--help)
      echo "Usage: sysup [-f|--force]"
      echo "  -f, --force   run apt update even if it ran in the last 6 hours"
      exit 0 ;;
    *) echo "sysup: unknown option: ${arg}" >&2; exit 2 ;;
  esac
done

if ! command -v apt-get >/dev/null 2>&1; then
  echo "sysup: apt-get not found; this script supports Debian/Ubuntu only." >&2
  exit 1
fi

# --- Non-interactive environment ---------------------------------------------
export DEBIAN_FRONTEND=noninteractive    # debconf: never ask questions
export DEBCONF_NONINTERACTIVE_SEEN=true
export UCF_FORCE_CONFFOLD=1              # ucf-managed configs (sshd, grub...): keep old
export NEEDRESTART_SUSPEND=1             # needrestart (Ubuntu 22.04+): no service prompt
export NEEDRESTART_MODE=l                # ...and if it runs anyway, only list
export APT_LISTCHANGES_FRONTEND=none     # no changelog pager
export LC_ALL=C.UTF-8                    # avoid locale warnings on minimal systems

APT_OPTS=(
  -y
  -o Dpkg::Options::=--force-confdef     # take the default action for conffiles...
  -o Dpkg::Options::=--force-confold     # ...and otherwise keep the installed version
  -o DPkg::Lock::Timeout=600             # wait for unattended-upgrades instead of failing
  -o APT::Get::Assume-Yes=true
)

# On a terminal, use `apt` with its colors and progress bar, as when run by
# hand. Otherwise (cron, pipes, logs) use quiet, script-stable `apt-get`.
if [ -t 1 ]; then
  APT_BIN=apt
  APT_OPTS+=(
    -o APT::Color=1
    -o Dpkg::Progress-Fancy=1
  )
else
  APT_BIN=apt-get
  APT_OPTS+=(-q)
fi

apt_get() {
  "${APT_BIN}" "${APT_OPTS[@]}" "$@" </dev/null
}

step() {
  printf '\n==> %s\n' "$*"
}

# --- Run -----------------------------------------------------------------------
step "Recovering any interrupted package operations"
dpkg --configure -a --force-confdef --force-confold </dev/null
apt_get -f install

SYSUP_STAMP=/var/lib/sysup/update-stamp
APT_STAMP=/var/lib/apt/periodic/update-success-stamp   # touched by any apt update on Ubuntu

UPDATE_MAX_AGE_HOURS=6   # skip apt update if lists were refreshed more recently than this

# Succeeds if either stamp is newer than UPDATE_MAX_AGE_HOURS; sets UPDATE_AGE.
updated_recently() {
  local now f age
  now="$(date +%s)"
  for f in "${SYSUP_STAMP}" "${APT_STAMP}"; do
    [ -f "${f}" ] || continue
    age=$(( now - $(stat -c %Y "${f}") ))
    if [ "${age}" -ge 0 ] && [ "${age}" -lt $(( UPDATE_MAX_AGE_HOURS * 3600 )) ]; then
      UPDATE_AGE="$(( age / 3600 ))h $(( age % 3600 / 60 ))m"
      return 0
    fi
  done
  return 1
}

if [ "${FORCE_UPDATE}" -eq 0 ] && updated_recently; then
  step "Package lists updated ${UPDATE_AGE} ago (under ${UPDATE_MAX_AGE_HOURS}h), skipping (use -f to force)"
else
  step "Updating package lists"
  apt_get --allow-releaseinfo-change update
  mkdir -p "$(dirname "${SYSUP_STAMP}")"
  touch "${SYSUP_STAMP}"
fi

step "Upgrading packages"
apt_get full-upgrade

step "Removing unused packages"
apt_get autoremove

step "Cleaning package cache"
apt_get autoclean

if [ -f /var/run/reboot-required ]; then
  if [ -s /var/run/reboot-required.pkgs ]; then
    step "A reboot is required to finish the upgrade for:"
    sort -u /var/run/reboot-required.pkgs | sed 's/^/    - /'
  else
    step "A reboot is required to finish the upgrade"
  fi
fi

step "Done"
