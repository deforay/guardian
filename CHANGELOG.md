# Changelog

All notable changes to guardian are recorded here. The version lives in the
`guardian` script (`VERSION=`); run `guardian version` to see what's installed.

## 0.2.0

- **Service-name aliases.** `guardian off mysql` / `on mysql` now resolve to the
  DB unit the box actually runs (`mysql` **or** `mariadb`), and `apache2`↔`httpd`
  likewise. Previously, on a box whose unit was `mariadb`/`httpd`, `off mysql`
  silently created a marker guardian never checked and kept restarting the
  service anyway. A name the box doesn't guard now prints a warning listing what
  it does guard. `on` also cleans up any stale marker left under the old alias.
- **Alerting.** New optional `ALERT_CMD` (set in `guardian.conf`) fires when
  guardian hits something it can't self-heal: a service that exhausted its
  restart budget, a disk still critical after reclaim, or memory critically high.
  Throttled per-kind (`ALERT_THROTTLE`, default 1h) so a stuck box doesn't page
  every tick. Email/ntfy/Slack one-liners in `examples/guardian.conf.example`.
- **`guardian logs [-f] [-n N]`** — shortcut for `journalctl -t guardian`.
- **`guardian status`** now shows when a timed pause expires (`off until 15:04,
  1h20m`) and exits non-zero when a guarded service is down and not deliberately
  off — so it drops straight into a monitoring check.
- Docs: added Requirements, Configuration (all tunables + defaults) and a
  Troubleshooting/FAQ section to the README, plus runnable sample hooks under
  `examples/hooks/`.

## 0.1.1

- `guardian help` now prints a clean, portable usage block (the old version
  leaked raw `#` comment lines and spilled past the header on BSD/macOS sed).

## 0.1.0

Initial release.

- Root systemd timer guards Apache, MySQL/MariaDB, and PHP-FPM (only if present;
  mod_php boxes are covered by Apache).
- Disk and memory pressure checks; frees space before giving up, and never
  restart-loops services while a disk is the cause.
- Per-service restart backoff.
- Global and per-service on/off with optional timed auto-resume
  (`guardian off mysql 2h`).
- Optional per-app hooks (`check`/`heal`/`reclaim`/`notify`) via
  `/etc/guardian/apps.d/` registration.
- On-demand app→hub trigger via the `/run/guardian/req` drop-box + systemd path unit.
- Idempotent `install.sh` (`--harden`, `--uninstall`); supersedes the older
  `service-guard.sh` / `resource-monitor.sh`.
