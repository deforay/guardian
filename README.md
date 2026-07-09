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

## Requirements

- **Linux with systemd** — guardian runs from a systemd timer and path unit.
- **bash** (4+) and **root** — it restarts services, writes under `/etc`, and can
  drop caches, so the timer runs as root.
- Standard tools that ship with a server install: `df`, `free`, `find`,
  `timeout`, `flock`, `logger`, and `journalctl` (for `guardian logs`). `curl` or
  `wget` is used for the optional HTTP probe; `git` for the one-line install.
- **No language runtimes or packages to install** — it's one bash script.

Developed and tested on **Ubuntu 22.04**. Both service-name families are
auto-detected, so Debian/Ubuntu (`apache2`, `mysql`) and RHEL-family —
CentOS/Rocky/Alma (`httpd`, `mariadb`) — are handled without configuration.

## Install

One line — clones to `/opt/guardian`, installs, and enables the timer. Re-run the
same line anytime to update (it pulls latest; only changed files are touched):

```bash
sudo bash -c 'git clone https://github.com/deforay/guardian.git /opt/guardian 2>/dev/null || git -C /opt/guardian pull -q; /opt/guardian/install.sh'
```

Optional: also let systemd instantly bounce a crashed Apache/MySQL between ticks —
append `--harden`:

```bash
sudo /opt/guardian/install.sh --harden
```

Remove it:

```bash
sudo /opt/guardian/install.sh --uninstall
```

## Use

```bash
guardian version           # installed version
guardian status            # what's guarded, what's off (exits non-zero if a
                           #   guarded service is down and not deliberately off)
guardian logs              # recent guardian log lines  (guardian logs -f to follow)
guardian run               # run one pass now (the timer does this for you)

guardian off               # turn guardian off entirely
guardian off mysql         # leave the DB alone (e.g. you stopped it on purpose)
guardian off apache2 2h    # ...for 2 hours, then auto-resume
guardian on  mysql         # guard it again
guardian on                # turn everything back on
```

Durations: `90` or `90s`, `30m`, `2h`, `1d`. No duration = until you turn it back on.

Service names are matched to what's actually on the box: `guardian off mysql`
works whether the unit is `mysql` or `mariadb`, and `off apache2` works on an
`httpd` box. Give a name it doesn't guard and it says so instead of silently
doing nothing. `guardian status` shows when a timed pause expires.

Logs go to the journal; `guardian logs` is a shortcut for:

```bash
journalctl -t guardian -n 50
```

## Configuration

guardian works out of the box with no config. To change a default, create
`/etc/guardian/guardian.conf` (it's sourced as bash — `KEY=value`, no spaces
around `=`). Copy [`examples/guardian.conf.example`](examples/guardian.conf.example)
for a fully-commented starting point.

| Setting          | Default              | What it does |
|------------------|----------------------|--------------|
| `DISK_WARN`      | `85`                 | warn when a mount is this % full |
| `DISK_CRIT`      | `95`                 | critical: reclaim space, and don't restart services until it clears |
| `MEM_WARN`       | `80`                 | warn at this memory % |
| `MEM_CRIT`       | `90`                 | critical: drop reclaimable caches |
| `DISK_MOUNTS`    | `"/ /var"`           | mounts to watch (space-separated) |
| `MAX_RESTARTS`   | `3`                  | give up on a service after this many restarts... |
| `RESTART_WINDOW` | `1800`               | ...within this many seconds, then leave it for a human |
| `HTTP_PROBE_URL` | `http://127.0.0.1/`  | URL the web probe fetches to prove Apache is answering |
| `HOOK_TIMEOUT`   | `60`                 | seconds before a stuck app hook is killed |
| `ALERT_CMD`      | `""` (off)           | command to run on can't-self-heal events (see below) |

After editing, `guardian run` (or wait for the next tick) picks it up — no
restart needed.

### Alerting (optional)

guardian heals what it can, but some things need a human — a service that keeps
crashing, a disk still full after cleanup, memory pinned. By default it just logs
those. Set `ALERT_CMD` and guardian runs it on exactly those can't-self-heal
events (throttled per kind, so a stuck box doesn't page you every minute). The
subject arrives as `$1`, the host as `$GUARDIAN_HOST`, a description on stdin:

```sh
# /etc/guardian/guardian.conf
# ntfy.sh (no mail server needed — just outbound HTTPS, pushes to your phone):
ALERT_CMD='curl -fsS -H "Title: guardian: $GUARDIAN_HOST" -d "$(cat)" https://ntfy.sh/your-secret-topic'

# or email — note `mail` needs a working local MTA/relay to actually deliver:
ALERT_CMD='mail -s "[guardian:$GUARDIAN_HOST] $1" you@example.com'
```

See [`examples/guardian.conf.example`](examples/guardian.conf.example) for the
Slack one-liner and the `ALERT_TIMEOUT` / `ALERT_THROTTLE` knobs.

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

Copy-pasteable starting points for all four live in
[`examples/hooks/`](examples/hooks/). The shape of a `check` and a `heal`:

```bash
# <APP_ROOT>/guardian/check — probe only; exit non-zero + print why if unhealthy
#!/usr/bin/env bash
curl -fsS --max-time 5 http://127.0.0.1/health.php >/dev/null 2>&1 \
  || { echo "health endpoint not responding"; exit 1; }
```

```bash
# <APP_ROOT>/guardian/heal — repair; runs after check fails or a dep restarted
#!/usr/bin/env bash
cd "$GUARDIAN_APP_ROOT" || exit 0
echo "healing after: $GUARDIAN_EVENT ($GUARDIAN_REASON)"
rm -rf var/cache/* 2>/dev/null || true          # clear a cache wedged by a DB bounce
systemctl try-restart myapp-worker 2>/dev/null || true
```

Keep `check` fast and side-effect-free (it runs every pass); put the actual
repair in `heal`, and make `heal` idempotent — it may run again next tick if the
app is still sick.

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

## Troubleshooting / FAQ

**Is guardian actually running?**

```bash
guardian status                       # what it's guarding right now
systemctl list-timers guardian.timer  # when it last ran / runs next
guardian logs -f                      # watch it work live
```

**How is this different from systemd `Restart=always`?**
`Restart=always` only reacts when a process *exits*. guardian also catches the
"up but not answering" cases — Apache running but returning errors, MySQL up but
not accepting connections — and it handles causes systemd can't: it frees a full
disk, and it refuses to restart-loop a service whose real problem is elsewhere.
The two compose well: `install.sh --harden` adds `Restart=always` so systemd
bounces a hard crash in ~5s, while guardian's timer covers everything else. Use
both.

**guardian keeps restarting a service — why?**
Its health probe is failing (Apache config test, the HTTP probe, or `mysqladmin
ping`). Check `guardian logs` for the reason. If the service is down on purpose,
`guardian off <svc>` (optionally with a duration) tells guardian to leave it
alone. After `MAX_RESTARTS` in `RESTART_WINDOW` it gives up on its own and logs
that a human is needed.

**It restarted something I was working on.**
`guardian off <svc> 2h` pauses guarding for that service (auto-resumes), or
`guardian off` pauses everything. `guardian on` when you're done.

**Does it email me?** Only if you set `ALERT_CMD` — see
[Configuration](#configuration). Otherwise everything goes to the journal.

**A note on trust:** app hooks and `ALERT_CMD` run **as root**. Only register
apps and commands you control — treat `/etc/guardian/apps.d/` like any other
root-owned config.

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
examples/guardian.conf.example optional config (thresholds, alerting) to copy
examples/hooks/                sample check/heal/reclaim/notify hooks to copy
tests/test.sh                  tests for the pure helpers
```

## License

MIT — see [LICENSE](LICENSE).
