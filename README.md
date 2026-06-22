# guardian

A small self-healing service for single-box LAMP-style servers.

It runs as root from a systemd timer (about every minute) and:

- keeps **Apache**, **MySQL/MariaDB**, and **PHP-FPM** (only if you use it) running,
- watches **disk** and **memory**, and frees space when a disk fills up,
- optionally calls **per-app hooks** so an app can do its own recovery.

It is plain bash + systemd with **no application dependencies**, so it keeps
working even when an app is broken (dead database, full disk, half-finished
deploy). It also works perfectly well with **no apps registered** — just guarding
the box's services.

> PHP-FPM vs mod_php: guardian only guards PHP-FPM if a `php*-fpm` service exists.
> On a mod_php box there's nothing to guard separately — PHP runs inside Apache,
> so guarding Apache already covers it. Nothing to configure either way.

## Install

```bash
git clone git@github.com:deforay/guardian.git
cd guardian
sudo ./install.sh
```

Optional: also let systemd instantly bounce a crashed Apache/MySQL between ticks:

```bash
sudo ./install.sh --harden
```

Remove it:

```bash
sudo ./install.sh --uninstall
```

## Use

```bash
guardian status            # what's guarded, what's off
guardian run               # run one pass now (the timer does this for you)

guardian off               # turn guardian off entirely
guardian off mysql         # leave MySQL alone (e.g. you stopped it on purpose)
guardian off apache2 2h    # ...for 2 hours, then auto-resume
guardian on  mysql         # guard it again
guardian on                # turn everything back on
```

Durations: `90` or `90s`, `30m`, `2h`, `1d`. No duration = until you turn it back on.

Logs go to the journal:

```bash
journalctl -t guardian -n 50
```

## How it decides

Each pass:

1. If guardian is **off**, stop.
2. Check **disk/memory**. If a disk is critical, free space first (and ask each
   app to free its own). A full disk is treated as a *cause* — guardian will not
   restart services while the disk is critical, because that won't help.
3. For each service that's **off** → start it; **up but not answering** → restart
   it. A service that keeps failing is left alone after a few tries (logged) so it
   doesn't restart-loop forever.
4. For each registered app, run its hooks (below).

## Hooking up an app (optional)

An app contributes recovery steps by shipping a few small scripts and registering
itself. Both halves are optional.

### 1. Register

Copy [`examples/app.conf.example`](examples/app.conf.example) to
`/etc/guardian/apps.d/<name>.conf`:

```sh
APP_NAME=myapp
APP_ROOT=/var/www/myapp
SERVICES="apache2 mysql"      # services this app needs
ENABLED=1
```

(Your app's installer can drop this file automatically.)

### 2. Add hooks

Put any of these executable scripts in `<APP_ROOT>/guardian/` (default) — each is
optional, can be any language, runs as root, and is time-boxed. A broken hook is
logged and ignored; it never affects the box or other apps.

| Hook      | When guardian runs it                    | What it should do |
|-----------|------------------------------------------|-------------------|
| `check`   | every pass                               | exit non-zero if the app is unhealthy; print a short reason |
| `heal`    | after `check` fails, or after a service the app needs was restarted | app-specific recovery (clear cache, fix permissions, nudge workers) |
| `reclaim` | when a disk is critical                  | delete the app's own throwaway files (old logs, temp, caches) |
| `notify`  | after a heal                             | record an alert somewhere the app can surface it |

guardian passes context to each hook as environment variables:

```
GUARDIAN_APP        app name
GUARDIAN_APP_ROOT   app root path
GUARDIAN_DIR        the guardian/ hook dir
GUARDIAN_SERVICES   the app's SERVICES
GUARDIAN_EVENT      check_failed | service_restarted | disk_critical
GUARDIAN_REASON     short human reason
```

### An app turning healing off for itself

Useful during the app's own maintenance — writable by the app (no root needed):

- `<APP_ROOT>/var/guardian.off` — like `guardian off` but just for this app.
  Same format: empty/`0` = until removed, or an expiry epoch for a timed pause.
- `<APP_ROOT>/var/guardian.enabled` — `no` disables the app's hooks (handy for a
  UI toggle).

### An app asking for help right now (optional)

Instead of waiting for the next tick, an app can summon guardian immediately by
creating a file in the drop-box:

```bash
echo "db unreachable" > /run/guardian/req/myapp
```

A systemd path unit notices and runs guardian within moments.

## Tests

```bash
bash tests/test.sh
```

## Layout

```
guardian                       the runtime (installed to /usr/local/sbin/guardian)
install.sh                     idempotent installer / uninstaller
systemd/                       service, timer, on-demand path unit, tmpfiles
examples/app.conf.example      a registration file to copy
tests/test.sh                  tests for the pure helpers
```

## License

MIT — see [LICENSE](LICENSE).
