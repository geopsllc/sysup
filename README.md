# System Upgrade Script

## Installation

```sh
git clone https://github.com/geopsllc/sysup
cd sysup
./sysup.sh
```

The first run adds a `sysup` alias to `~/.bashrc`. After that, run `sysup` from anywhere.

You are asked for your sudo password at most once, at the start. After that the run needs no input:
package lists are refreshed, everything is upgraded with `full-upgrade`, your existing config files are
kept, and unused packages and cached downloads are cleaned up. If a reboot is needed, the script says so
at the end.

Supports current Debian (11+) and Ubuntu (20.04+) releases.

## Changelog

### 0.2
- add `apt-get update` before upgrading
- elevate once with sudo up front, so the run can't stall on a password prompt later
- fully non-interactive: debconf, ucf, needrestart and apt-listchanges prompts suppressed; existing config files kept
- wait up to 10 minutes for the dpkg lock (e.g. unattended-upgrades) instead of failing
- recover interrupted dpkg runs before upgrading
- keep needrestart installed instead of purging it; it is silenced for the run
- alias points to the script's real location, not the current directory
- report when a reboot is required

### 0.1
- initial release

## Security

If you discover a security vulnerability within this package, please open an issue. All security vulnerabilities will be promptly addressed.

## Credits

- [All Contributors](../../contributors)
- [Georgi Stoyanov](https://github.com/geopsllc)

## License

[MIT](LICENSE) © [geopsllc](https://github.com/geopsllc)

