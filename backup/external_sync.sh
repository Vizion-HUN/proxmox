#!/usr/bin/env bash
# felkiáltójeles mappák kezelése, előzmény-kiterjesztés kikapcsolása
set +H
set -uo pipefail

# Konfiguráció
external_mount="/mnt/external_hdd"
source_backup="/mnt/ssd_backup/NAS_backup/"
dest_backup="/mnt/external_hdd/NAS_backup/"
start_time=$(date "+%Y-%m-%d %H:%M:%S")
# log fájl helye
log_dir="/root/log"
log_file="${log_dir}/external_sync.log"
# Log mappa létrehozása, ha nem létezik
mkdir -p "$log_dir"

# HDD csatolás - ha nincs bedugva, csendben kilép
mount "$external_mount" 2>/dev/null
if ! mountpoint -q "$external_mount"; then
    exit 0
fi

# Szinkronizálás
rsync -avh --hard-links --delete \
  "$source_backup" "$dest_backup" \
  > "$log_file" 2>&1
exit_code=$?

end_time=$(date "+%Y-%m-%d %H:%M:%S")
ext_usage=$(du -sh "$external_mount" 2>/dev/null | awk '{print $1}')

if [ $exit_code -eq 0 ]; then
    subject="External Backup kész"
    status="Szinkronizálás sikeresen lefutott."
else
    subject="External Backup HIBA"
    status="HIBA: rsync hibakóddal zárult: $exit_code"
fi

log_tail=$(tail -n 5 "$log_file")

mail_body="Mentés kezdete: $start_time
Mentés vége: $end_time
$status
--- Tárhely ---
Külső HDD foglalt: $ext_usage
--- Összefoglaló ---
$log_tail"

echo -e "Subject: $subject\n\n$mail_body" | /usr/libexec/proxmox-mail-forward

# HDD leválasztás (biztonságos eltávolításhoz)
umount "$external_mount"
