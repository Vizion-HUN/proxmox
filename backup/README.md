# 💾 Backup Scripts for Proxmox VE / Debian

**[English](#english) | [Magyar](#magyar)**

---

## English

### Overview

Two companion scripts for a complete local backup solution on Proxmox VE or Debian-based systems:

| Script | Purpose |
|---|---|
| `backup.sh` | Incremental backup of selected folders using rsync + hardlinks |
| `external_sync.sh` | Syncs the backup to an external HDD, auto-mounts and unmounts |

---

## backup.sh

### What does it do?

Backs up selected folders from a source drive to a backup drive using rsync with hardlink-based incremental logic. Keeps the current and one previous version (`.1`) — unchanged files are not duplicated, they are hardlinked, saving significant disk space.

**Key features:**
- Source and target mount point verification before running — prevents accidental deletion via `--delete`
- Disk space check on target before starting
- `--max-delete=500` safety limit — prevents wiping the backup if the source is accidentally empty
- Per-folder error handling — one folder failing does not stop the rest
- Per-folder log files with rotation
- Email notification on completion or error via `proxmox-mail-forward`

### 💡 Best Practice: Split Large Backup Sets

If you have many folders to back up, consider splitting them across multiple scripts (e.g. `backup1.sh`, `backup2.sh`, `backup3.sh`) with separate crontab entries.

**Why?** If one script exits on error at the first folder, the remaining folders in that script won't be backed up. With smaller, independent scripts, a failure in one does not affect the others — and you get more granular email alerts per group.

### Requirements

- Proxmox VE or Debian-based system
- `rsync` installed (usually pre-installed)
- Source and target drives mounted and accessible
- Email notifications configured in Proxmox VE (Datacenter → Notifications)

### Installation

**1. Download the script**
```bash
wget -O /root/backup.sh https://raw.githubusercontent.com/Vizion-HUN/proxmox/main/backup/backup.sh
```

**2. Make it executable**
```bash
chmod +x /root/backup.sh
```

**3. Create the log directory**
```bash
mkdir -p /root/log
```

**4. Edit the configuration** at the top of the script:
```bash
source_mount="/mnt/ssd"           # source drive mount point
source="/mnt/ssd/"                # source path
folders=("Folder1" "Folder2")     # folders to back up
backup="/mnt/ssd_backup/NAS_backup/"  # destination path
target_mount="/mnt/ssd_backup"    # target drive mount point
```

**5. Add to crontab** (runs daily at 01:00)
```bash
crontab -e
```
```
0 1 * * * /root/backup.sh
```

### Log Management

Per-folder logs are saved in `/root/log/` as `backup_FolderName.log`. Previous run is kept as `backup_FolderName.1.log`.

The logs are small and self-rotating — no logrotate needed.

---

## external_sync.sh

### What does it do?

Syncs the entire backup destination to an external USB HDD. The drive is automatically mounted at the start and safely unmounted at the end — so it can remain physically connected without being permanently mounted.

**Key features:**
- Silent exit if the external HDD is not connected — safe to run daily via cron even when the drive is unplugged
- `--hard-links` preserves the hardlink structure from the incremental backup
- Email notification with disk usage summary and rsync output
- Safe unmount after sync

### fstab Configuration (Required)

The external HDD must be listed in `/etc/fstab` with the `noauto` option so it is not mounted at boot but can be mounted on demand by the script. Sample fstab line:

```
UUID=your-drive-uuid  /mnt/external_hdd  ntfs-3g  defaults,noauto  0  0
or this
vagy például
UUID=your-drive-uuid  /mnt/external_hdd  ext4  defaults,noatime,noexec,nodev,nosuid,noauto,nofail  0  0
```

Find your drive's UUID:
```bash
blkid
```

### Installation

**1. Download the script**
```bash
wget -O /root/external_sync.sh https://raw.githubusercontent.com/Vizion-HUN/proxmox/main/backup/external_sync.sh
```

**2. Make it executable**
```bash
chmod +x /root/external_sync.sh
```

**3. Edit the configuration** at the top of the script:
```bash
external_mount="/mnt/external_hdd"
source_backup="/mnt/ssd_backup/NAS_backup/"
dest_backup="/mnt/external_hdd/NAS_backup/"
```

**4. Add to crontab** (runs daily at 04:00)
```bash
crontab -e
```
```
0 4 * * * /root/external_sync.sh
```

### Log Management

The sync log is saved to `/root/log/external_sync.log` (overwritten each run).

Add logrotate to keep a few weeks of history:
```bash
nano /etc/logrotate.d/external_sync
```
```
/root/log/external_sync.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
```

---

### Suggested Crontab Layout

```
# Backup (split across scripts if needed)
0 1 * * * /root/backup.sh

# External HDD sync (runs after backup)
0 4 * * * /root/external_sync.sh
```

---

## Magyar

### Áttekintés

Két kísérő script egy teljes helyi mentési megoldáshoz Proxmox VE vagy Debian alapú rendszereken:

| Script | Funkció |
|---|---|
| `backup.sh` | Kiválasztott mappák inkrementális mentése rsync + hardlink alapon |
| `external_sync.sh` | A mentés szinkronizálása külső HDD-re, automatikus csatolással és leválasztással |

---

## backup.sh

### Mit csinál?

Kiválasztott mappákat ment egy forrás meghajtóról egy backup meghajtóra, rsync alapú hardlink-inkrementális logikával. Az aktuális és egy előző verziót (`.1`) tárolja — a változatlan fájlok nem másolódnak, hanem hardlinkelve lesznek, jelentős tárhelyet megtakarítva.

**Főbb funkciók:**
- Forrás és cél csatolási pontok ellenőrzése futtatás előtt — megakadályozza az `--delete` miatti véletlen törlést
- Tárhely ellenőrzés a célon indítás előtt
- `--max-delete=500` biztonsági korlát — véd a véletlen üres forrás miatti teljes törlés ellen
- Mappánkénti hibakezelés — egy mappa hibája nem állítja le a többit
- Mappánkénti naplófájlok rotációval
- E-mail értesítés befejezéskor vagy hiba esetén a `proxmox-mail-forward` segítségével

### 💡 Tipp: Nagy mentési lista felosztása

Ha sok mappát kell menteni, érdemes több scriptre osztani (pl. `backup1.sh`, `backup2.sh`, `backup3.sh`) külön crontab bejegyzésekkel.

**Miért?** Ha egy script az első mappánál hibával kilép, a script többi mappája nem kerül mentésre. Kisebb, független scriptekkel egy hiba nem érinti a többit — és mappacsoport-szintű e-mail értesítéseket is kapsz.

### Követelmények

- Proxmox VE vagy Debian alapú rendszer
- Telepített `rsync` (általában előre telepített)
- A forrás és cél meghajtók csatolva és elérhetők
- Beállított e-mail értesítés Proxmox VE-ben (Datacenter → Notifications)

### Telepítés

**1. Script letöltése**
```bash
wget -O /root/backup.sh https://raw.githubusercontent.com/Vizion-HUN/proxmox/main/backup/backup.sh
```

**2. Futtathatóvá tétel**
```bash
chmod +x /root/backup.sh
```

**3. Log mappa létrehozása**
```bash
mkdir -p /root/log
```

**4. Konfiguráció szerkesztése** a script elején:
```bash
source_mount="/mnt/ssd"           # forrás meghajtó csatolási pontja
source="/mnt/ssd/"                # forrás útvonal
folders=("Mappa1" "Mappa2")       # menteni kívánt mappák
backup="/mnt/ssd_backup/NAS_backup/"  # cél útvonal
target_mount="/mnt/ssd_backup"    # cél meghajtó csatolási pontja
```

**5. Hozzáadás a crontab-hoz** (naponta 01:00-kor fut)
```bash
crontab -e
```
```
0 1 * * * /root/backup.sh
```

### Naplófájlok kezelése

A mappánkénti naplók a `/root/log/` mappában találhatók `backup_MappaName.log` névvel. Az előző futás naplója `backup_MappaName.1.log` néven marad meg.

A naplók kicsik és önrotálók — logrotate nem szükséges.

---

## external_sync.sh

### Mit csinál?

A teljes backup célt szinkronizálja egy külső USB HDD-re. A meghajtó automatikusan csatolódik indításkor és biztonságosan leválasztódik a végén — így fizikailag csatlakoztatva maradhat anélkül, hogy állandóan csatolva legyen.

**Főbb funkciók:**
- Csendes kilépés ha a külső HDD nincs csatlakoztatva — napi cron futtatás esetén is biztonságos, ha a meghajtó nincs bedugva
- `--hard-links` megőrzi az inkrementális mentés hardlink struktúráját
- E-mail értesítés tárhelyhasználat összesítővel és rsync kimenettel
- Biztonságos leválasztás a szinkronizálás után

### fstab konfiguráció (szükséges)

A külső HDD-nek szerepelnie kell az `/etc/fstab`-ban `noauto` opcióval — így nem csatolódik rendszerindításkor, de a script igény szerint csatolhatja. Példa fstab csatolásra:

```
UUID=a-meghajtó-uuid-ja  /mnt/external_hdd  ntfs-3g  defaults,noauto  0  0
vagy például
UUID=a-meghajtó-uuid-ja  /mnt/external_hdd  ext4  defaults,noatime,noexec,nodev,nosuid,noauto,nofail  0  0
```

A meghajtó UUID-jának lekérdezése:
```bash
blkid
```

### Telepítés

**1. Script letöltése**
```bash
wget -O /root/external_sync.sh https://raw.githubusercontent.com/Vizion-HUN/proxmox/main/backup/external_sync.sh
```

**2. Futtathatóvá tétel**
```bash
chmod +x /root/external_sync.sh
```

**3. Konfiguráció szerkesztése** a script elején:
```bash
external_mount="/mnt/external_hdd"
source_backup="/mnt/ssd_backup/NAS_backup/"
dest_backup="/mnt/external_hdd/NAS_backup/"
```

**4. Hozzáadás a crontab-hoz** (naponta 04:00-kor fut)
```bash
crontab -e
```
```
0 4 * * * /root/external_sync.sh
```

### Naplófájlok kezelése

A szinkronizálási napló `/root/log/external_sync.log` néven kerül mentésre (minden futáskor felülírja).

Logrotate hozzáadása néhány hét előzmény megőrzéséhez:
```bash
nano /etc/logrotate.d/external_sync
```
```
/root/log/external_sync.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
```

---

### Javasolt crontab beállítás

```
# Mentés (szükség esetén több scriptre osztva)
0 1 * * * /root/backup.sh

# Külső HDD szinkronizálás (mentés után fut)
0 4 * * * /root/external_sync.sh
```

---

*Scripts developed with the help of [Claude AI](https://claude.ai) by Anthropic.*
