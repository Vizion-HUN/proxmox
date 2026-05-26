#!/usr/bin/env bash

# felkiáltójeles mappák kezelése, előzmény-kiterjesztés kikapcsolása
set +H
set -uo pipefail

# Konfiguráció
# a forrás meghajtó csatolási pontja (ellenőrzéshez)
source_mount="/mnt/ssd"
# forrás mappa, amiben a menteni kívánt mappák vannak
source="/mnt/ssd/"
# mappanevek, amiket almappákkal, fájlokkal menteni szeretnénk
folders=("Tomi" "Viki" "Apa")
# ebbe a mappába mentünk majd (cél)
backup="/mnt/ssd_backup/NAS_backup/"
# a cél meghajtó csatolási pontja (ellenőrzéshez)
target_mount="/mnt/ssd_backup"
# log fájl helye
log_dir="/root/log"
# log fájlnév eleje
log_prefix="${log_dir}/backup2_"
start_time=$(date "+%Y-%m-%d %H:%M:%S")
# Log mappa létrehozása, ha nem létezik
mkdir -p "$log_dir"

# --- 1. HDD csatolás és mappa ellenőrzése (Forrás és Cél) ---
# Ha a forrás nincs csatolva, akkor leáll, nehogy az rsync --delete törölje a backupot!
if ! mountpoint -q "$source_mount"; then
    error_msg="HIBA: A forrás meghAajtó ($source_mount) nincs csatolva! A mentés megszakítva."
    echo -e "Subject: Backup KRITIKUS HIBA - Forrás nincs csatolva\n\n$error_msg" | /usr/libexec/proxmox-mail-forward
    exit 1
fi

if ! mountpoint -q "$target_mount" || [ ! -d "$backup" ]; then
    error_msg="HIBA: A backup drive nincs csatolva, vagy a $backup könyvtár nem érhető el!"
    echo -e "Subject: Backup HIBA \n\n$error_msg" | /usr/libexec/proxmox-mail-forward
    exit 1
fi

# --- Cél meghajtó tárhely ellenőrzése ---
# foglalt méretet GB-ban, ~500 GB a meghajtó, 450 GB foglaltság felett ne kezdjen menteni
current_usage=$(df -m "$target_mount" | awk 'NR==2 {print int($3/1024)}')
limit=450

if [ "$current_usage" -ge "$limit" ]; then
    error_msg="HIBA: A backup tárhely megtelt! Jelenleg: ${current_usage}GB. Limit: ${limit}GB. A mentés elmaradt!"
    echo -e "Subject: Backup KRITIKUS HIBA - Tárhely hiba\n\n$error_msg" | /usr/libexec/proxmox-mail-forward
    exit 1
fi

# --- 2-4. Ciklus a mappák mentésére ---
all_stats=""
error_occurred=0

for name in "${folders[@]}"; do
    link="${backup}${name}"
    sources="${source}${name}"

    # Ha a forrás mappa nem létezik, lépés a következőre, nem áll le a mentés
     if [ ! -d "$sources" ]; then
     all_stats="${all_stats}\n--- ${name} ---\nHIBA: A forrás mappa ($sources) nem létezik!\n"
     error_occurred=1
     continue
    fi

    # Régi mentések forgatása (Hardlink-alapú inkrementális logika)
    rm -rf "${link}.2"
    [ -d "${link}.1" ] && mv "${link}.1" "${link}.2"
    [ -d "$link" ] && mv "$link" "${link}.1"

    # Log kezelés
    cp -f "${log_prefix}${name}.log" "${log_prefix}${name}.1.log" 2>/dev/null || true

    # Mentés (rsync)
    # A --max-delete=500 megakadályozza, hogy egy véletlenül kiürített forrás mappa letörölje a teljes backupot.
    if [ -d "${link}.1" ]; then
        rsync -avh --delete --max-delete=500 \
          --exclude='*.tmp' --exclude='~$*' --exclude='.trash*' \
          --exclude='.thumb*' --exclude='Thumbs.db' --exclude='**/.kuka/' \
          --link-dest="${link}.1" \
          "$sources/" "$link/" > "${log_prefix}${name}.log" 2>&1
    else
        # Ha még nem volt mentés (ez az első futás), akkor nincs mihez linkelni, sokáig fut...
        rsync -avh --delete --max-delete=500 \
          --exclude='*.tmp' --exclude='~$*' --exclude='.trash*' \
          --exclude='.thumb*' --exclude='Thumbs.db' --exclude='**/.kuka/' \
          "$sources/" "$link/" > "${log_prefix}${name}.log" 2>&1
    fi

    rsync_exit=$?

    # Hibakezelés: ha az rsync hibakóddal lép ki (pl. I/O hiba, vagy elérte a max-delete limitet)
    if [ $rsync_exit -ne 0 ]; then
        all_stats="${all_stats}\n--- ${name} ---\nFIGYELEM: Az rsync hibával zárult (kód: $rsync_exit)! Nézd meg a logot.\n$(tail -n 10 "${log_prefix}${name}.log")\n"
        error_occurred=1
    else
        all_stats="${all_stats}\n--- ${name} ---\n"
        all_stats="${all_stats}$(tail -n 3 "${log_prefix}${name}.log")\n"
    fi
done

# --- 5. Statisztikák összegyűjtése az összes mappáról és levél összeállítása ---
end_time=$(date "+%Y-%m-%d %H:%M:%S")

# Újra lemezméret, hogy lássuk mennyit változott
final_usage=$(df -m "$target_mount" | awk 'NR==2 {print int($3/1024)}')

# Levél státuszának beállítása hiba esetén
if [ $error_occurred -eq 1 ]; then
    subject="Backup FIGYELEM - Részleges hiba"
    status_msg="A mentés során hiba lépett fel (lásd a statisztikát)."
else
    subject="Backup kész"
    status_msg="Mentés sikeresen lefutott."
fi

mail_body="Mentés kezdete: $start_time
Mentés vége: $end_time
$status_msg

--- Tárhely ---
A backup SSD-n jelenleg: ${final_usage} GB foglalt.

Összesített statisztika:
$all_stats"

echo -e "Subject: $subject\n\n$mail_body" | /usr/libexec/proxmox-mail-forward
