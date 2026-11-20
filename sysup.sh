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
  -y -q
  -o Dpkg::Options::=--force-confdef     # take the default action for conffiles...
  -o Dpkg::Options::=--force-confold     # ...and otherwise keep the installed version
  -o DPkg::Lock::Timeout=600             # wait for unattended-upgrades instead of failing
  -o APT::Get::Assume-Yes=true
)

apt_get() {
  apt-get "${APT_OPTS[@]}" "$@" </dev/null
}

step() {
  printf '\n==> %s\n' "$*"
}

# --- Run -----------------------------------------------------------------------
step "Recovering any interrupted package operations"
dpkg --configure -a --force-confdef --force-confold </dev/null
apt_get -f install

step "Updating package lists"
apt_get --allow-releaseinfo-change update

step "Upgrading packages"
apt_get full-upgrade

step "Removing unused packages"
apt_get autoremove

step "Cleaning package cache"
apt_get autoclean

if [ -f /var/run/reboot-required ]; then
  step "A reboot is required to finish the upgrade"
  if [ -f /var/run/reboot-required.pkgs ]; then
    sort -u /var/run/reboot-required.pkgs | sed 's/^/    /'
  fi
fi

step "Done"
