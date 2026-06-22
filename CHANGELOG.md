# Changelog

All notable changes to guardian are recorded here. The version lives in the
`guardian` script (`VERSION=`); run `guardian version` to see what's installed.

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
