#!/bin/bash
# ==============================================================================
# SMART Idősoros Trendriport (Havi futásra tervezve)
# ==============================================================================
# Funkció: Beolvassa a lemezenkénti különálló CSV fájlokat, és minden egyes
#          attribútumnál kirajzolja az utolsó 4 mérés alakulását (kb. 1 hónap).
# ==============================================================================

set +H

# --- Konfiguráció ---
LOG_DIR="/root/log"
start_time=$(date "+%Y-%m-%d %H:%M:%S")
report=""

# Biztonságos fájlkeresés
shopt -s nullglob
csv_files=("$LOG_DIR"/smart_*.csv)
shopt -u nullglob

if [ ${#csv_files[@]} -eq 0 ]; then
    echo -e "Subject: SMART Havi Riport HIBA\n\nNem találhatóak SMART CSV fájlok a(z) $LOG_DIR mappában!" \
        | /usr/libexec/proxmox-mail-forward
    exit 1
fi

# Végigmegyünk az összes talált lemez CSV fájlján
for csv_file in "${csv_files[@]}"; do
    # Meghajtó fix ID-jának kinyerése a fájlnévből
    drive_id=$(basename "$csv_file" | sed 's/^smart_//;s/\.csv$//')

    report="$report\n--- $drive_id ---\n"

    # Attribútumok kigyűjtése a fájlból
    attrs=$(cut -d',' -f2 "$csv_file" | grep -v "attributum" | sort -u)

    for attr in $attrs; do
        # Kigyűjtjük az utolsó 4 értéket a 4. oszlopból (RAW értékek vagy NVMe százalék)
        # Az awk gyönyörűen összefűzi őket egy "érték1 -> érték2 -> érték3" lánccá
        trend=$(grep ",${attr}," "$csv_file" | tail -n 4 | cut -d',' -f4 | awk '{printf "%s%s", (NR==1?"":" -> "), $0} END {print ""}')

        # Legfrissebb (aktuális) érték
        current=$(grep ",${attr}," "$csv_file" | tail -n 1 | cut -d',' -f4)

        if [ -n "$current" ]; then
            report="$report  $attr: $current   (Múltbeli trend: $trend)\n"
        fi
    done
done

# Email törzs összeállítása
mail_body="SMART Idősoros Trendriport
Generálva: $start_time
Magyarázat: A zárójeles trend az utolsó 4 mérést mutatja az időben előrehaladva (balról jobbra).

$report"

# Küldés
echo -e "Subject: SMART Havi Riport – Trendelemzés\n\n$mail_body" \
    | /usr/libexec/proxmox-mail-forward
