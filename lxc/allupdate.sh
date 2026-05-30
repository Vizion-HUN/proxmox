#!/usr/bin/env bash
set -eEuo pipefail

# Színek
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
CL="\033[m"

mkdir -p /root/log
LOGFILE="/root/log/allupdate.log"
touch "$LOGFILE"
chmod 600 "$LOGFILE"

log() {
  local msg="$1"
  echo -e "$msg"
  echo -e "$msg" | sed 's/\033\[[0-9;]*m//g' >> "$LOGFILE"
}

log "\n===== $(date '+%Y-%m-%d %H:%M:%S') | Allupdate | Host: $(hostname) ====="

function clean_lxc() {
  local container=$1
  local name=$2
  local os=$3

  log "\n${BL}[Info]${GN} === Container $container ($name | $os) ===${CL}"

  if [ "$os" == "alpine" ]; then
    pct exec "$container" -- ash -c '
      echo "--- Update ---"
      apk update

      echo "--- Upgrade ---"
      apk upgrade

      echo "--- Cache clean ---"
      apk cache clean

      echo "--- nerdctl/containerd cache clean ---"
      if command -v nerdctl &>/dev/null; then
        nerdctl image prune -f
      else
        echo "nerdctl not found, skipping"
      fi

      echo "--- Old logs (>7 days) ---"
      find /var/log -type f -mtime +7 -delete 2>/dev/null && echo "Done" || echo "Nothing to delete"

      echo "--- Temp clean ---"
      find /tmp -mindepth 1 -delete 2>/dev/null && echo "Done" || echo "Nothing to delete"

      echo "--- Failed services ---"
      rc-status 2>/dev/null | grep -i "failed" || echo "None"
    ' 2>&1 | while IFS= read -r line; do log "  $line"; done

  elif [ "$os" == "debian" ] || [ "$os" == "ubuntu" ]; then
    pct exec "$container" -- bash -c '
      echo "--- Update ---"
      apt-get update -qq

      echo "--- Upgrade ---"
      DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

      echo "--- Autoremove ---"
      apt-get autoremove -y -qq

      echo "--- Autoclean ---"
      apt-get autoclean -y -qq

      echo "--- APT cache clean ---"
      find /var/cache/apt -type f -delete 2>/dev/null && echo "Done" || echo "Nothing to delete"

      echo "--- Old logs (>7 days) ---"
      find /var/log -type f -mtime +7 -delete 2>/dev/null && echo "Done" || echo "Nothing to delete"

      echo "--- Temp clean ---"
      find /tmp -mindepth 1 -delete 2>/dev/null && echo "Done" || echo "Nothing to delete"

      echo "--- Docker cleanup ---"
      if command -v docker &>/dev/null; then
        docker image prune -f
        docker builder prune -f
      else
        echo "Docker not found, skipping"
      fi

      echo "--- Failed services ---"
      systemctl --failed --no-legend 2>/dev/null | grep -v "^$" || echo "None"
    ' 2>&1 | while IFS= read -r line; do log "  $line"; done
  fi

  # fstrim
  log "${BL}[Info]${CL} Running fstrim..."
  local fstrim_out
  fstrim_out=$(pct fstrim "$container" 2>&1)
  if echo "$fstrim_out" | grep -qi "not supported"; then
    log "  ${RD}fstrim not supported on this storage${CL}"
  else
    log "  ${GN}fstrim: $fstrim_out${CL}"
  fi

  log "${GN}[Done]${CL} $container ($name) finished."
}

# Main loop
while read -r LINE; do
  CTID=$(awk '{print $1}' <<<"$LINE")
  STATUS=$(awk '{print $2}' <<<"$LINE")
  NAME=$(awk '{print $3}' <<<"$LINE")

  # Skip templates
  if pct config "$CTID" 2>/dev/null | grep -q "template:"; then
    log "${BL}[Info]${GN} Skipping $CTID ($NAME) - template${CL}"
    continue
  fi

  # Skip stopped
  if [ "$STATUS" != "running" ]; then
    log "${BL}[Info]${GN} Skipping $CTID ($NAME) - stopped${CL}"
    continue
  fi

  OS=$(pct config "$CTID" | awk '/^ostype/ {print $2}')

  if [[ "$OS" != "debian" && "$OS" != "ubuntu" && "$OS" != "alpine" ]]; then
    log "${BL}[Info]${RD} Skipping $CTID ($NAME) - unsupported OS: $OS${CL}"
    continue
  fi

  clean_lxc "$CTID" "$NAME" "$OS"

done < <(pct list | awk 'NR>1')

log "\n${GN}===== Allupdate complete: $(date '+%Y-%m-%d %H:%M:%S') =====${CL}"

# PVE Host update
log "\n${BL}[Info]${GN} === Proxmox Host Update ===${CL}"

log "${BL}[Info]${CL} apt update + upgrade + autoremove..."
apt-get update -y 2>&1 | while IFS= read -r line; do log "  $line"; done
apt-get upgrade -y 2>&1 | while IFS= read -r line; do log "  $line"; done
apt-get autoremove -y 2>&1 | while IFS= read -r line; do log "  $line"; done

log "${BL}[Info]${CL} pveam update..."
pveam update 2>&1 | while IFS= read -r line; do log "  $line"; done

log "${BL}[Info]${CL} update-grub..."
update-grub 2>&1 | while IFS= read -r line; do log "  $line"; done

log "${BL}[Info]${CL} proxmox-boot-tool refresh..."
proxmox-boot-tool refresh 2>&1 | while IFS= read -r line; do log "  $line"; done

log "${BL}[Info]${CL} proxmox-boot-tool status..."
proxmox-boot-tool status 2>&1 | while IFS= read -r line; do log "  $line"; done

log "${BL}[Info]${CL} Journal disk usage..."
journalctl --disk-usage 2>&1 | while IFS= read -r line; do log "  $line"; done

log "${BL}[Info]${CL} Kernel: $(uname -r)"
log "${BL}[Info]${CL} PVE version: $(pveversion)"

# Reboot szükségességének ellenőrzése
if [ -f /var/run/reboot-required ]; then
  log "\n${RD}╔═══════════════════════════════════════════════════════════╗${CL}"
  log   "${RD}║  FIGYELEM: Kernel frissítés történt!                      ║${CL}"
  log   "${RD}║  A Proxmox újraindítása szükséges az életbe lépéséhez.    ║${CL}"
  log   "${RD}╚═══════════════════════════════════════════════════════════╝${CL}"
fi

log "\n${GN}===== All done: $(date '+%Y-%m-%d %H:%M:%S') =====${CL}"
echo -e "${BL}Log: cat $LOGFILE${CL}\n"

# Email értesítés
REBOOT_NOTE=""
if [ -f /var/run/reboot-required ]; then
  REBOOT_NOTE="\n⚠️  FIGYELEM: Kernel frissítés történt, a Proxmox VE újraindítása szükséges!"
fi

echo -e "Subject: Allupdate frissítések elvégezve - $(hostname)\n\nA karbantartás sikeresen lefutott $(date '+%Y-%m-%d %H:%M:%S')-kor.\n${REBOOT_NOTE}\nRészletek: $LOGFILE" \
  | /usr/libexec/proxmox-mail-forward

exit 0
