#!/usr/bin/env bash
#
# install.sh — set up (or remove) guardian on this machine. Idempotent: safe to
# re-run; only changed files are touched.
#
#   sudo ./install.sh              install + enable the timer
#   sudo ./install.sh --harden     also add systemd Restart=always to apache/mysql
#   sudo ./install.sh --uninstall  remove everything guardian installed
#
set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SBIN=/usr/local/sbin/guardian
ETC_DIR=/etc/guardian
UNIT_DIR=/etc/systemd/system
TMPFILES=/etc/tmpfiles.d/guardian.conf

need_root() { if [[ $EUID -ne 0 ]]; then echo "Re-running with sudo..."; exec sudo -E bash "$0" "$@"; fi; }

# write_if_different <target> [mode] ; content on stdin. Echoes "changed" lines.
write_if_different() {
  local target="$1" mode="${2:-0644}" tmp; tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then rm -f "$tmp"; return 1; fi
  install -D -m "$mode" "$tmp" "$target"; rm -f "$tmp"
  echo "  updated $target"; return 0
}

detect_web() { systemctl list-unit-files apache2.service >/dev/null 2>&1 && echo apache2 || { systemctl list-unit-files httpd.service >/dev/null 2>&1 && echo httpd; }; }
detect_db()  { systemctl list-unit-files mysql.service  >/dev/null 2>&1 && echo mysql   || { systemctl list-unit-files mariadb.service >/dev/null 2>&1 && echo mariadb; }; }

remove_legacy() {
  # guardian supersedes the older service-guard / resource-monitor scripts.
  local u
  for u in service-guard resource-monitor; do
    if systemctl list-unit-files "${u}.timer" >/dev/null 2>&1; then
      echo "  removing legacy ${u}"
      systemctl disable --now "${u}.timer" 2>/dev/null || true
      rm -f "${UNIT_DIR}/${u}.timer" "${UNIT_DIR}/${u}.service" "/usr/local/sbin/${u}.sh"
    fi
  done
}

install_overrides() {
  local svc="$1" changed=0
  [[ -z "$svc" ]] && return 0
  if write_if_different "${UNIT_DIR}/${svc}.service.d/override.conf" <<EOF
[Service]
Restart=always
RestartSec=5s
StartLimitIntervalSec=120
StartLimitBurst=10
EOF
  then changed=1; fi
  return $changed
}

uninstall() {
  need_root "$@"
  echo "Removing guardian..."
  systemctl disable --now guardian.timer guardian-trigger.path 2>/dev/null || true
  rm -f "${UNIT_DIR}/guardian.service" "${UNIT_DIR}/guardian.timer" "${UNIT_DIR}/guardian-trigger.path"
  rm -f "$SBIN" "$TMPFILES"
  rm -rf /run/guardian
  echo "  (kept ${ETC_DIR} and /var/lib/guardian — delete by hand if you want them gone)"
  systemctl daemon-reload
  echo "Done."
}

main() {
  local harden=0
  case "${1:-}" in
    --uninstall) uninstall "$@"; exit 0 ;;
    --harden)    harden=1 ;;
    "" )         ;;
    *) echo "usage: $0 [--harden|--uninstall]" >&2; exit 2 ;;
  esac
  need_root "$@"

  echo "Installing guardian..."
  install -d -m 0755 "${ETC_DIR}/apps.d" /var/lib/guardian /usr/local/sbin

  local changed=0
  write_if_different "$SBIN" 0755 < "${SRC_DIR}/guardian" && changed=1
  write_if_different "${UNIT_DIR}/guardian.service"      < "${SRC_DIR}/systemd/guardian.service"      && changed=1
  write_if_different "${UNIT_DIR}/guardian.timer"        < "${SRC_DIR}/systemd/guardian.timer"        && changed=1
  write_if_different "${UNIT_DIR}/guardian-trigger.path" < "${SRC_DIR}/systemd/guardian-trigger.path" && changed=1
  write_if_different "$TMPFILES"                         < "${SRC_DIR}/systemd/tmpfiles.conf"          && changed=1

  remove_legacy

  if (( harden )); then
    echo "Adding Restart=always overrides..."
    install_overrides "$(detect_web)" || true
    install_overrides "$(detect_db)"  || true
  fi

  systemd-tmpfiles --create "$TMPFILES" >/dev/null 2>&1 || true
  systemctl daemon-reload
  systemctl enable --now guardian.timer >/dev/null 2>&1 || true
  systemctl enable --now guardian-trigger.path >/dev/null 2>&1 || true

  local ver; ver="$(grep -m1 '^VERSION=' "${SRC_DIR}/guardian" | cut -d'"' -f2)"
  echo "Done (guardian ${ver:-?})."
  echo "  status: guardian status   (or: systemctl status guardian.timer)"
  echo "  logs:   journalctl -t guardian -n 50"
}
main "$@"
