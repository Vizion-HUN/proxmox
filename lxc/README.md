# 🔄 Allupdate for Proxmox VE

**[English](#english) | [Magyar](#magyar)**

---

## English

### What does it do?

`allupdate.sh` is a comprehensive maintenance script for Proxmox VE that updates and cleans all running LXC containers, then updates the Proxmox host itself — in a single run.

Designed for **manual execution**: run it when you want a full system update, review the output live, and get an email summary at the end.

---

### LXC Containers

**Only running containers are processed.** Stopped containers are skipped and are NOT started automatically. Supported OS types: Alpine, Debian, Ubuntu. Other OS types are skipped with a log entry.

**For each running container:**

| Step | Details |
|---|---|
| Disk usage (before) | Shown for comparison |
| Update & Upgrade | `apk` (Alpine) or `apt-get` (Debian/Ubuntu) |
| Cache clean | APT cache / apk cache |
| Old logs | Files older than 7 days removed from `/var/log` |
| Temp clean | `/tmp` cleaned |
| Docker cleanup | Dangling (unreferenced) images and build cache pruned — **images belonging to any container (running or stopped) are NOT removed** |
| nerdctl cleanup | Same as Docker, for Alpine + nerdctl/containerd |
| Failed services | Listed in log (not fixed automatically) |
| Disk usage (after) | Shown for comparison |
| fstrim | Run on each container's storage |

---

### Proxmox VE Host

After all containers are done, the PVE host itself is updated:

- `apt-get update + upgrade + autoremove`
- `pveam update` (LXC template list)
- `update-grub`
- `proxmox-boot-tool refresh + status`
- Journal disk usage summary
- Current kernel and PVE version logged

**Reboot warning:** If a kernel update requires a reboot, a prominent warning is shown in the log and included in the email — clearly stating that the **Proxmox VE host** needs to be restarted, not the LXC containers.
The omission of the `dist-upgrade` command is intentional; its use requires caution, and it is specifically recommended to run it after executing `allupdate.sh`—if warranted.

---

### Requirements

- Proxmox VE
- Email notifications configured (Datacenter → Notifications) — used by `proxmox-mail-forward`

---

### Installation

**1. Download the script**
```bash
wget -O /root/allupdate.sh https://raw.githubusercontent.com/Vizion-HUN/proxmox/main/lxc/allupdate.sh
```

**2. Make it executable**
```bash
chmod +x /root/allupdate.sh
```

**3. Run manually**
```bash
/root/allupdate.sh
# or explicitly:
bash /root/allupdate.sh
```

### Log Management

The full log is saved to `/root/log/allupdate.log` (overwritten each run).

Since each run overwrites the previous log, logrotate is not needed.

---

## Magyar

### Mit csinál?

Az `allupdate.sh` egy átfogó karbantartó script Proxmox VE-hez, amely egyetlen futással frissíti és kitakarítja az összes futó LXC containert, majd frissíti a Proxmox host-ot is.

**Manuális futtatásra tervezve:** futtasd amikor teljes rendszerfrissítést szeretnél, élőben követheted a kimenetet, és a végén e-mail összesítőt kapsz.

---

### LXC Containerek

**Csak a futó containerek kerülnek feldolgozásra.** A leállított containerek ki vannak hagyva, és a script NEM indítja el őket. Támogatott OS típusok: Alpine, Debian, Ubuntu. Egyéb OS típusok kihagyásra kerülnek, naplóbejegyzéssel.

**Minden futó containeren elvégzett műveletek:**

| Lépés | Részletek |
|---|---|
| Lemezhasználat (előtte) | Összehasonlításhoz |
| Update & Upgrade | `apk` (Alpine) vagy `apt-get` (Debian/Ubuntu) |
| Cache tisztítás | APT cache / apk cache |
| Régi logok | 7 napnál régebbi fájlok törlése a `/var/log`-ból |
| Temp tisztítás | `/tmp` ürítése |
| Docker cleanup | Csak a "dangling" (sehova sem hivatkozott) image-ek és build cache törlése — **leállított containerekhez tartozó image-ek NEM törlődnek** |
| nerdctl cleanup | Mint Docker, Alpine + nerdctl/containerd esetén |
| Hibás szolgáltatások | Naplózva (nem javítja automatikusan) |
| Lemezhasználat (utána) | Összehasonlításhoz |
| fstrim | Lefut minden container storage-án |

---

### Proxmox VE Host

Miután minden container elkészült, maga a PVE host is frissül:

- `apt-get update + upgrade + autoremove`
- `pveam update` (LXC template lista)
- `update-grub`
- `proxmox-boot-tool refresh + status`
- Journal lemezhasználat összesítő
- Aktuális kernel és PVE verzió naplózva

**Újraindítás figyelmeztetés:** Ha egy kernel frissítés újraindítást igényel, jól látható figyelmeztetés jelenik meg a naplóban és az e-mailben — egyértelműen jelezve, hogy a **Proxmox VE host**-ot kell újraindítani, nem az LXC containereket.
A dist-upgrade parancs kihagyása szándékos, használata körültekintést igényel, az allupdate.sh futtatása után -indokolt esetben- külön ajánlott futtatni.

---

### Követelmények

- Proxmox VE
- Beállított e-mail értesítés (Datacenter → Notifications) — a `proxmox-mail-forward` használja

---

### Telepítés

**1. Script letöltése**
```bash
wget -O /root/allupdate.sh https://raw.githubusercontent.com/Vizion-HUN/proxmox/main/lxc/allupdate.sh
```

**2. Futtathatóvá tétel**
```bash
chmod +x /root/allupdate.sh
```

**3. Manuális futtatás**
```bash
/root/allupdate.sh
# vagy explicit módon:
bash /root/allupdate.sh
```

### Naplófájl kezelése

A teljes napló a `/root/log/allupdate.log` fájlba kerül (minden futáskor felülírja).

Mivel minden futás felülírja az előző naplót, logrotate nem szükséges.

---

*Script developed with the help of [Claude AI](https://claude.ai) by Anthropic.*
