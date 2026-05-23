# 🖥️ SMART Monitor for Proxmox VE / Debian

**[English](#english) | [Magyar](#magyar)**

---

## English

### What does this script do?

This script monitors the health of your hard drives (HDD, SSD, NVMe) on Proxmox VE or Debian-based systems. It automatically detects all physical drives, runs short SMART self-tests, logs the results per drive into individual CSV files, and sends an email alert if any critical value is detected or worsening.

**Key features:**
- Automatic drive detection via stable `/dev/disk/by-id/` links — survives drive replacements and sdX reordering
- Per-drive CSV history files — suitable for AI or spreadsheet analysis
- Vendor-specific logic for Micron, Samsung, and generic drives
- Intel Optane support (logged only, no wear alerts)
- Baseline-aware alerting: only alerts on *changes*, not pre-existing high values (e.g. UDMA CRC errors)
- Intelligent self-test wait — no fixed sleep, polls until all tests finish
- Native Proxmox email integration via `proxmox-mail-forward`

---

### Requirements

- Proxmox VE or Debian-based system
- `smartmontools` installed:
  ```bash
  apt install smartmontools
  ```
- Email notifications configured in Proxmox VE (Datacenter → Notifications), or a working MTA on plain Debian

---

### Installation

**1. Download the script**
```bash
wget -O /root/smart_check.sh https://raw.githubusercontent.com/Vizion-HUN/proxmox/main/smart_check.sh
```

**2. Make it executable**
```bash
chmod +x /root/smart_check.sh
```

**3. Create the log directory**
```bash
mkdir -p /root/log
```

**4. Add to crontab** (runs weekly, every Sunday at 02:00)
```bash
crontab -e
```
Add this line:
```
0 2 * * 0 /root/smart_check.sh >> /root/log/smart_check.log 2>&1
```

---

### CSV Log Files

Each drive gets its own CSV file in `/root/log/`, named after its stable disk ID:

```
/root/log/smart_ata-Samsung_SSD_850_EVO_500GB_S21JNXAG123456.csv
/root/log/smart_nvme-Micron_3400_MTFDKBA512TFH_ABC123.csv
```

CSV format:
```
datum,attributum,ertek,raw
2026-05-23,Wear_Leveling_Count,098,27
2026-05-23,Reallocated_Sector_Ct,100,0
```

---

### Troubleshooting: Drive Not Recognized Correctly

If you suspect a drive is being detected with the wrong type or vendor logic, run these commands and paste the output along with the script into Claude AI — it will identify what needs to be adjusted:

**List all drives with type and model:**
```bash
lsblk -d -o NAME,TYPE,ROTA,SIZE,MODEL
```

**Check SMART data for a specific drive:**
```bash
# For SATA drives:
smartctl -A /dev/sda

# For NVMe drives:
smartctl -A /dev/nvme0n1

# Full info including model:
smartctl -i /dev/sda
```

Then paste the output and the script to [Claude AI](https://claude.ai) with a message like:
> *"This drive is not being recognized correctly. Here is the smartctl output and the script — please update the vendor detection logic."*

---

### Complementing with smartd

This script handles **slow degradation trends** (week-over-week changes). For **real-time catastrophic failure detection**, you can run the built-in `smartd` daemon alongside it with a minimal config:

```bash
# /etc/smartd.conf
DEVICESCAN -H -l error -m root -M exec /usr/share/smartmontools/smartd-runner
```

The two tools do not overlap — they complement each other well.

---

## Magyar

### Mit csinál ez a script?

Ez a script figyeli a számítógép merevlemezeinek (HDD, SSD, NVMe) egészségi állapotát Proxmox VE vagy Debian alapú rendszereken. Automatikusan felismeri az összes fizikai meghajtót, rövid SMART öntesztet futtat, az eredményeket meghajtónként külön CSV fájlba menti, és e-mail értesítést küld, ha kritikus értéket vagy romlást észlel.

**Főbb funkciók:**
- Automatikus meghajtófelismerés stabil `/dev/disk/by-id/` linkek alapján — meghajtócsere és sdX átrendeződés esetén is helyesen működik
- Meghajtónként külön CSV előzményfájlok — AI vagy táblázatkezelő elemzésre felkészítve
- Gyártóspecifikus logika Micron, Samsung és általános meghajtókhoz
- Intel Optane támogatás (csak naplózás, kopási riasztás nélkül)
- Alapérték-tudatos riasztás: csak a *változást* jelzi, nem a meglévő magas értékeket (pl. UDMA CRC hibák)
- Intelligens önteszt-várakozás — nincs fix sleep, addig vár amíg minden teszt lefut
- Natív Proxmox e-mail integráció a `proxmox-mail-forward` segítségével

---

### Követelmények

- Proxmox VE vagy Debian alapú rendszer
- Telepített `smartmontools`:
  ```bash
  apt install smartmontools
  ```
- Beállított e-mail értesítés Proxmox VE-ben (Datacenter → Notifications), vagy működő MTA plain Debian esetén

---

### Telepítés

**1. Script letöltése**
```bash
wget -O /root/smart_check.sh https://raw.githubusercontent.com/Vizion-HUN/proxmox/main/smart_check.sh
```

**2. Futtathatóvá tétel**
```bash
chmod +x /root/smart_check.sh
```

**3. Log mappa létrehozása**
```bash
mkdir -p /root/log
```

**4. Hozzáadás a crontab-hoz** (hetente egyszer, vasárnap hajnali 02:00-kor fut)
```bash
crontab -e
```
Add hozzá ezt a sort:
```
0 2 * * 0 /root/smart_check.sh >> /root/log/smart_check.log 2>&1
```

---

### CSV Naplófájlok

Minden meghajtónak saját CSV fájlja van a `/root/log/` mappában, a stabil disk-by-id azonosító alapján elnevezve:

```
/root/log/smart_ata-Samsung_SSD_850_EVO_500GB_S21JNXAG123456.csv
/root/log/smart_nvme-Micron_3400_MTFDKBA512TFH_ABC123.csv
```

CSV formátum:
```
datum,attributum,ertek,raw
2026-05-23,Wear_Leveling_Count,098,27
2026-05-23,Reallocated_Sector_Ct,100,0
```

---

### Hibaelhárítás: Meghajtó Nem Ismerhető Fel Helyesen

Ha egy meghajtó típusa vagy gyártója nem megfelelően van detektálva, futtasd le az alábbi parancsokat, majd az eredményt és a scriptet illeszd be Claude AI-ba — automatikusan azonosítja, mit kell módosítani:

**Összes meghajtó listázása típussal és modellel:**
```bash
lsblk -d -o NAME,TYPE,ROTA,SIZE,MODEL
```

**Egy meghatározott meghajtó SMART adatainak lekérdezése:**
```bash
# SATA meghajtókhoz:
smartctl -A /dev/sda

# NVMe meghajtókhoz:
smartctl -A /dev/nvme0n1

# Teljes info a modellel együtt:
smartctl -i /dev/sda
```

Majd illeszd be az eredményt és a scriptet a [Claude AI](https://claude.ai)-ba egy ilyen üzenettel:
> *„Ez a meghajtó nem ismerhető fel helyesen. Íme a smartctl kimenete és a script — kérlek egészítsd ki a gyártófelismerési logikát."*

---

### Kiegészítés a smartd daemon-nal

Ez a script a **lassú romlási trendeket** kezeli (hetek, hónapok alatt változó értékek). Az **azonnali, katasztrofális meghibásodások** valós idejű detektálásához futtathatod mellette a beépített `smartd` daemone-t minimális konfigurációval:

```bash
# /etc/smartd.conf
DEVICESCAN -H -l error -m root -M exec /usr/share/smartmontools/smartd-runner
```

A két eszköz nem fedi át egymást — jól kiegészítik egymást.

---

*Script developed with the help of [Claude AI](https://claude.ai) by Anthropic.*
