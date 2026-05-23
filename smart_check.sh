#!/bin/bash
# ==============================================================================
# SMART Monitor & Élettartam Követő Script Proxmox VE / Debian rendszerekhez
# ==============================================================================
# Funkciók:
#   - Automatikus lemezfelismerés stabil, fix /dev/disk/by-id/ linkek alapján
#   - Meghajtónként külön külön CSV statisztika (AI/Excel elemzésre felkészítve)
#   - Intelligens várakozás a rövid tesztek lefutására (nincs fix hosszú sleep)
#   - Optimalizált erőforrás-használat (egy smartctl hívás / NVMe lemez)
#   - Egyedi riasztási küszöbök gyártóspecifikus SATA és NVMe attribútumokra
# ==============================================================================

set +H

# --- Konfiguráció ---
LOG_DIR="/root/log"
DATE=$(date "+%Y-%m-%d")
ALERT=""

mkdir -p "$LOG_DIR"

# --- 1. Automatikus Lemezfelismerés (Deduplikált disk-by-id alapú mapping) ---
declare -A DISK_IDS      # kernel_nev -> fix_id (pl: sda -> ata-Samsung...)
declare -A DRIVE_TYPE    # kernel_nev -> NVME/SSD/HDD
declare -A DRIVE_MODEL   # kernel_nev -> Gyári modell név

for link in /dev/disk/by-id/ata-* /dev/disk/by-id/nvme-*; do
    # Kiszűrjük a partíciókat, a klónozott linkeket és a redundáns WWN/EUI azonosítókat
    [[ "$link" == *"-part"* ]] && continue
    [[ "$link" == *"_1" ]] && continue
    [[ "$link" == *"_2" ]] && continue
    [[ "$link" == *"nvme-eui."* ]] && continue
    [[ "$link" == *"nvme-nvme."* ]] && continue
    [ ! -e "$link" ] && continue

    real_dev=$(readlink -f "$link")
    dev_name=$(basename "$real_dev") # pl: sda vagy nvme0n1
    id_name=$(basename "$link")      # pl: ata-Samsung_SSD_850...

    # Csak a valós fizikai lemezeket mentjük el
    DISK_IDS[$dev_name]="$id_name"

    # Típus és modell meghatározása
    if [[ "$dev_name" =~ ^nvme ]]; then
        DRIVE_TYPE[$dev_name]="NVME"
        DRIVE_MODEL[$dev_name]=$(smartctl -i "$link" | awk -F': ' '/Model Number/{gsub(/^ +| +$/,"",$2); print $2}')
    else
        DRIVE_MODEL[$dev_name]=$(cat /sys/block/$dev_name/device/model 2>/dev/null | xargs)
        rota=$(cat /sys/block/$dev_name/queue/rotational 2>/dev/null)
        if [[ "$rota" -eq 1 ]]; then
            DRIVE_TYPE[$dev_name]="HDD"
        else
            DRIVE_TYPE[$dev_name]="SSD"
        fi
    fi
done

# Ha nem talált lemezt (biztonsági háló)
if [ ${#DISK_IDS[@]} -eq 0 ]; then
    echo "Hiba: Nem található monitorozható fizikai meghajtó!"
    exit 1
fi

# --- 2. Napi Guard és CSV Inicializálás ---
# Végigmegyünk a talált lemezeken és előkészítjük a saját CSV fájljaikat
for dev in "${!DISK_IDS[@]}"; do
    id="${DISK_IDS[$dev]}"
    CSV_FILE="$LOG_DIR/smart_${id}.csv"

    if [ ! -f "$CSV_FILE" ]; then
        echo "datum,attributum,ertek,raw" > "$CSV_FILE"
    fi

    # Ha a mai napon már futott a script legalább egy lemezre, akkor globálisan kilépünk
    if grep -q "^$DATE," "$CSV_FILE" 2>/dev/null; then
        echo "[$DATE] Ma már lefutott a SMART ellenőrzés. Kilépés."
        exit 0
    fi
done

# --- 3. Rövid SMART Tesztek Indítása ---
echo "Rövid SMART tesztek indítása a meghajtókon..."
for dev in "${!DISK_IDS[@]}"; do
    smartctl -t short "/dev/$dev" > /dev/null 2>&1
done

# --- 4. Intelligens Várakozás (Max 3 perc polling) ---
echo "Várakozás a tesztek befejeződésére..."
for i in {1..36}; do
    testing=false
    for dev in "${!DISK_IDS[@]}"; do
        if smartctl -a "/dev/$dev" 2>/dev/null | grep -qE "Self-test routine in progress|Self-test in progress"; then
            testing=true
            break
        fi
    done
    if [ "$testing" = false ]; then
        echo "Minden háttérteszt sikeresen lefutott."
        break
    fi
    sleep 5
done

# --- 5. SATA Attribútum Helper (Robusztus oszlop-kezeléssel) ---
save_sata() {
    local dev=$1 id=$2 attr_name=$3 csv_path=$4
    local line value raw

    # Biztonságos awk: a VALUE mindig a 4. oszlop, a RAW mindig az utolsó ($NF), függetlenül az eltolódásoktól
    line=$(smartctl -A "/dev/$dev" | awk -v id="$id" '$1==id {print $4, $NF}')
    read -r value raw <<< "$line"

    if [ -n "$value" ]; then
        echo "$DATE,$attr_name,$value,$raw" >> "$csv_path"
    fi
    echo "$value $raw"
}

# --- 6. Előző Valós Érték Lekérése a saját CSV-ből ---
prev_value() {
    local csv_path=$1 attr_name=$2
    grep ",$attr_name," "$csv_path" 2>/dev/null \
        | awk -F',' '$4!="" {print $4}' \
        | tail -2 | head -1
}

# --- 7. Adatgyűjtés és Kiértékelés ---
for dev in "${!DISK_IDS[@]}"; do
    id="${DISK_IDS[$dev]}"
    model="${DRIVE_MODEL[$dev]}"
    type="${DRIVE_TYPE[$dev]}"
    CSV_FILE="$LOG_DIR/smart_${id}.csv"

    if [ "$type" = "NVME" ]; then
        # --- NVMe Meghajtók Kezelése (Optimalizált, 1 db smartctl hívás) ---
        nvme_out=$(smartctl -A "/dev/$dev" 2>/dev/null)

        # Kivesszük az utolsó oszlopot ($NF), és a 'tr -cd' garantálja, hogy CSAK a tiszta számok maradnak meg.
        pct_used=$(echo "$nvme_out" | awk '/Percentage Used/{print $NF}' | tr -cd '0-9')
        unsafe=$(echo "$nvme_out" | awk '/Unsafe Shutdowns/{print $NF}' | tr -cd '0-9')
        media_err=$(echo "$nvme_out" | awk '/Media and Data Integrity Errors/{print $NF}' | tr -cd '0-9')
        err_log=$(echo "$nvme_out" | awk '/Error Information Log Entries/{print $NF}' | tr -cd '0-9')
        prev_err=$(prev_value "$CSV_FILE" "Error_Log_Entries")

        # Mentés a saját külön CSV-be
        echo "$DATE,Percentage_Used,-,$pct_used"         >> "$CSV_FILE"
        echo "$DATE,Unsafe_Shutdowns,-,$unsafe"           >> "$CSV_FILE"
        echo "$DATE,Media_Integrity_Errors,-,$media_err"  >> "$CSV_FILE"
        echo "$DATE,Error_Log_Entries,-,$err_log"         >> "$CSV_FILE"

        # Kivételkezelés: Intel Optane mentesítése a kopás riasztás alól
        if [[ "$model" =~ MEMPEK ]]; then
            continue
        fi

        if [ -n "$media_err" ] && [ "$media_err" -gt 0 ]; then
            ALERT="$ALERT\n🔴 $model ($dev): Media_Integrity_Errors=$media_err!"
        fi
        if [ -n "$prev_err" ] && [ -n "$err_log" ] && [ "$err_log" -gt "$prev_err" ]; then
            ALERT="$ALERT\n⚠️  $model ($dev): Error_Log_Entries növekedett: $prev_err → $err_log"
        fi
        if [ -n "$pct_used" ] && [ "$pct_used" -ge 80 ]; then
            ALERT="$ALERT\n⚠️  $model ($dev): Elhasználódás magas: ${pct_used}%!"
        fi

    elif [ "$type" = "SSD" ]; then
        # --- SATA SSD-k Kezelése (Gyártóspecifikus ágak) ---
        if [[ "$model" =~ [Mm]icron|MTFD ]]; then
            # Micron SSD logikája
            read val raw <<< $(save_sata "$dev" "184" "Error_Correction_Count" "$CSV_FILE")
            if [ -n "$val" ] && [ "$val" -le 99 ]; then
                ALERT="$ALERT\n⚠️  $model ($dev): Error_Correction_Count VALUE=$val (Közeledik a küszöbhöz!)"
            fi
            read val raw <<< $(save_sata "$dev" "174" "Unexpect_Power_Loss_Ct" "$CSV_FILE")
            if [ -n "$raw" ] && [ "$raw" -gt 300 ]; then
                ALERT="$ALERT\n⚠️  $model ($dev): Magas váratlan tápvesztés szám: $raw"
            fi
            prev=$(prev_value "$CSV_FILE" "POR_Recovery_Count")
            read val raw <<< $(save_sata "$dev" "235" "POR_Recovery_Count" "$CSV_FILE")
            if [ -n "$prev" ] && [ -n "$raw" ] && [ "$raw" -gt "$prev" ]; then
                ALERT="$ALERT\n⚠️  $model ($dev): POR_Recovery_Count emelkedett: $prev → $raw"
            fi

        elif [[ "$model" =~ [Ss]amsung ]]; then
            # Samsung SSD logikája
            read val raw <<< $(save_sata "$dev" "177" "Wear_Leveling_Count" "$CSV_FILE")
            if [ -n "$val" ] && [ "$val" -le 20 ]; then
                ALERT="$ALERT\n🔴 $model ($dev): Wear_Leveling_Count VALUE=$val (Kritikus kopásszint!)"
            elif [ -n "$val" ] && [ "$val" -le 50 ]; then
                ALERT="$ALERT\n⚠️  $model ($dev): Wear_Leveling_Count VALUE=$val (Figyelem, kopik a lemez)"
            fi
            read val raw <<< $(save_sata "$dev" "187" "Reported_Uncorrectable" "$CSV_FILE")
            if [ -n "$raw" ] && [ "$raw" -gt 0 ]; then
                ALERT="$ALERT\n🔴 $model ($dev): Reported_Uncorrectable=$raw!"
            fi
        fi

        # Generikus SATA SSD/HDD közös kritikus attribútumok
        prev_crc=$(prev_value "$CSV_FILE" "UDMA_CRC_Error_Count")
        read val raw <<< $(save_sata "$dev" "199" "UDMA_CRC_Error_Count" "$CSV_FILE")
        if [ -n "$prev_crc" ] && [ -n "$raw" ] && [ "$raw" -gt "$prev_crc" ]; then
            ALERT="$ALERT\n⚠️  $model ($dev): UDMA_CRC_Error_Count nőtt: $prev_crc → $raw (Kábel/SATA port hiba?)"
        fi
        read val raw <<< $(save_sata "$dev" "5" "Reallocated_Sector_Ct" "$CSV_FILE")
        if [ -n "$raw" ] && [ "$raw" -gt 0 ]; then
            ALERT="$ALERT\n🔴 $model ($dev): Reallocated_Sector_Ct=$raw (Hibás szektorok!)"
        fi
        read val raw <<< $(save_sata "$dev" "197" "Current_Pending_Sector" "$CSV_FILE")
        if [ -n "$raw" ] && [ "$raw" -gt 0 ]; then
            ALERT="$ALERT\n🔴 $model ($dev): Current_Pending_Sector=$raw (Függő szektorok!)"
        fi

    elif [ "$type" = "HDD" ]; then
        # --- Mechanikus HDD-k Kezelése ---
        read val raw <<< $(save_sata "$dev" "5" "Reallocated_Sector_Ct" "$CSV_FILE")
        if [ -n "$raw" ] && [ "$raw" -gt 0 ]; then
            ALERT="$ALERT\n🔴 $model ($dev): Reallocated_Sector_Ct=$raw"
        fi
        read val raw <<< $(save_sata "$dev" "197" "Current_Pending_Sector" "$CSV_FILE")
        if [ -n "$raw" ] && [ "$raw" -gt 0 ]; then
            ALERT="$ALERT\n🔴 $model ($dev): Current_Pending_Sector=$raw"
        fi
        prev_crc=$(prev_value "$CSV_FILE" "UDMA_CRC_Error_Count")
        read val raw <<< $(save_sata "$dev" "199" "UDMA_CRC_Error_Count" "$CSV_FILE")
        if [ -n "$prev_crc" ] && [ -n "$raw" ] && [ "$raw" -gt "$prev_crc" ]; then
            ALERT="$ALERT\n⚠️  $model ($dev): UDMA_CRC_Error_Count növekedés: $prev_crc → $raw"
        fi
    fi
done

# --- 8. Értesítés Küldése ---
if [ -n "$ALERT" ]; then
    echo -e "Subject: SMART ALERT - Hardver Figyelmeztetés!\n\nAzonnali beavatkozást igénylő értékek:\n$ALERT" \
        | /usr/libexec/proxmox-mail-forward
    echo -e "[ALERT KIKÜLDVE]:\n$ALERT"
else
    echo "Minden lemez állapota megfelelő, nincs teendő."
fi
