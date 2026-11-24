# Activitat 2 · Templates Debian i desplegament de la infraestructura

Delegació **25** · rang `10.25.0.0/16` · domini `del25.virtualcorp.internal`

Aquest document explica com es creen els dos templates Debian, com es
despleguen els 22 equips mitjançant clonació enllaçada i com s'instal·la
de manera desatesa Proxmox VE a `pve01`. Tot el procés s'executa amb
`make` i scripts Bash. No cal cap intervenció manual.

---

## 1. Posada en marxa ràpida

```bash
cp .env.example .env          # i definiu SYSADMIN_PASSWORD i PVE_ROOT_PASSWORD
make check_host               # VT-x, virtualització anidada, eines, RAM i disc
make download_isos            # ISO de Debian i Proxmox VE, verificades amb SHA256
make create_templates         # tpl-debian-server i tpl-debian-desktop
make deploy-routers           # (activitat 1) si els routers no existeixen
make deploy_equipment         # 22 clons enllaçats + pve01 (Proxmox VE)
make list_equipment           # inventari i estat de cada màquina
```

| Target | Què fa | Opcions |
| --- | --- | --- |
| `check_host` | Comprova VT-x/AMD-V, la virtualització anidada de VirtualBox, el mòdul `kvm`, les eines (`xorriso`, `openssl`, `dpkg-deb`...), les claus SSH, les contrasenyes del `.env` i els recursos de l'amfitrió. | — |
| `download_isos` | Descarrega les ISO fixades i en verifica el SHA256. Si ja hi són i el hash és correcte, no les torna a baixar. | — |
| `create_templates` | Crea els dos templates amb una instal·lació desatesa. | `ROLE=server\|desktop`, `FORCE=1` |
| `delete_templates` | Esborra els templates. Falla si encara tenen clons enllaçats. | `ROLE=` |
| `deploy_equipment` | Crea els clons enllaçats, els connecta a la xarxa, en comprova l'arrencada i instal·la `pve01`. És idempotent: els equips que ja existeixen no es toquen. | `VMS="a b"`, `FORCE=1`, `VERIFY=0` |
| `delete_equipment` | Esborra els equips (els templates i els routers es mantenen). | `VMS="a b"` |
| `list_equipment` | Mostra l'inventari amb l'estat de cada VM. | — |

Exemples: `make deploy_equipment VMS="printer0 direccio1"` desplega només
aquests dos equips; `make deploy_equipment VMS=pve01` instal·la només
Proxmox; `FORCE=1` esborra i torna a crear els equips indicats.

---

## 2. Versions fixades i descàrregues

Les versions, els noms de fitxer, les URL i els SHA256 són a
**`configs/versions.env`**. Aquest fitxer està versionat i el llegeixen
tant el `Makefile` com els scripts (`common.sh`). Els scripts mai cerquen
«la darrera versió»: només descarreguen la URL fixada i rebutgen qualsevol
fitxer amb un hash diferent.

| Component | Versió | URL oficial | SHA256 |
| --- | --- | --- | --- |
| Debian netinst amd64 | 13.7.0 | `https://cdimage.debian.org/debian-cd/13.7.0/amd64/iso-cd/debian-13.7.0-amd64-netinst.iso` | `a7ef94ac…e355` (verificat amb la signatura GPG de *Debian CD signing key*) |
| Proxmox VE | 9.2-1 | `https://download.proxmox.com/iso/proxmox-ve_9.2-1.iso` | `4e88fe41…2c6c` (`SHA256SUMS` oficial) |
| proxmox-auto-install-assistant | 9.2.9 | `http://download.proxmox.com/debian/pve/dists/trixie/pve-no-subscription/binary-amd64/` | `ceb1a220…5b75` |

- Cada ISO té una **URL mirror** opcional, que només es fa servir si la
  principal falla. El mirror ha de servir exactament el mateix fitxer
  (mateix nom i mateix SHA256), de manera que no és cap canvi de versió.
- El hash de `proxmox-auto-install-assistant` es va obtenir seguint la
  cadena signada del repositori de Proxmox: la clau *Proxmox Trixie Release
  Key* (`24B30F06ECC1836A4E5EFECBA7BCD1420BFE778E`) signa `Release`,
  `Release` conté el hash de `Packages.gz` i `Packages.gz` conté el del
  `.deb`. El repositori APT es publica per HTTP, així que és el hash fixat
  el que en garanteix la integritat. El paquet s'extreu amb `dpkg-deb -x` a
  `artifacts/build/tools/` i **no s'instal·la** a l'amfitrió.
- Les ISO es guarden a `artifacts/images/iso/` i els fitxers generats a
  `artifacts/build/`. Totes dues carpetes estan ignorades per Git.

**Actualitzacions controlades.** Per canviar una versió: creeu una branca
nova, modifiqueu `configs/versions.env` (URL + SHA256), executeu
`make create_templates FORCE=1` i `make deploy_equipment FORCE=1` en un
entorn de proves, valideu-ho i només llavors feu el merge a `main`.

---

## 3. Templates Debian

| | `tpl-debian-server` | `tpl-debian-desktop` |
| --- | --- | --- |
| Ús | Servidors del CPD i de la DMZ, impressores | Plantes, consergeria, expositors |
| Paquets afegits | `openssh-server sudo ca-certificates` | els de server + `xserver-xorg-core`, `lxqt-core`, `openbox`, `sddm`, `falkon`, `fonts-dejavu-core` |
| Entorn gràfic | cap | LXQt (sessió «LXQt Desktop» a SDDM), navegador Falkon |
| Recursos del template | 1024 MB, 2 vCPU, disc dinàmic de 20 GB | 2048 MB, 2 vCPU, disc dinàmic de 20 GB |
| Temps de creació | ~5 min | ~6 min |

Comú als dos templates:

- Instal·lació **sense tasksel** i **sense paquets recomanats**
  (`base-installer/install-recommends false`). Així no s'instal·len
  Firefox, LibreOffice ni cap altra aplicació que l'enunciat no demana.
- Xarxa per **DHCP**. Usuari **`sysadmin`** (grup `sudo`), amb la
  contrasenya en hash SHA-512 generat a partir del `.env`. L'usuari root
  no pot iniciar sessió.
- `~sysadmin/.ssh/authorized_keys` amb la **clau del professor**
  (`configs/ssh/vcorp_auditor.pub`) i la **clau personal**
  (`configs/ssh/vcorp_sysadmin.pub`), instal·lades per `late.sh` durant la
  instal·lació.
- Teclat `es`, zona horària `Europe/Madrid`. Al desktop, el teclat també
  es fixa per a X a `/etc/X11/xorg.conf.d/00-keyboard.conf`.
- Serveis propis: `vcorp-firstboot` (identitat de cada clon) i
  `vcorp-ready` (escriu `VCORP-READY <hostname>` al port sèrie).

### 3.1 Procediment (`create_templates.sh`)

1. **ISO desatesa**: `preseed.cfg` (renderitzat des de
   `configs/debian/preseed.cfg.tpl`), els scripts de `configs/debian/files/`
   i les claus públiques s'incrusten a la ISO de Debian amb `xorriso`. El
   menú d'arrencada es modifica perquè arrenqui l'instal·lador automàtic
   sense preguntar res.
2. **VM de construcció** amb una NIC **NAT temporal** (l'instal·lador
   netinst necessita Internet per baixar els paquets) i COM1 redirigit a
   un fitxer.
3. **Instal·lació**: en acabar, l'instal·lador apaga la VM.
4. **Validació** per SSH (amb la clau personal i un port redirigit):
   claus autoritzades, DHCP a `/etc/network/interfaces`, LXQt, Falkon i
   SDDM presents al desktop, cap Firefox ni LibreOffice, i cap servidor X
   al template server.
5. **Segellat** (`vcorp-seal`): esborra les claus de host SSH, buida el
   `machine-id` i elimina les concessions DHCP i els logs.
6. **Es treu el NAT** (només router0 pot tenir NAT): la NIC queda en una
   xarxa interna `unused` i desconnectada. Es fa la instantània **`base`**,
   que és d'on surten tots els clons.

---

## 4. Desplegament dels equips (`deploy_equipment.sh`)

L'inventari és a **`configs/equipment.conf`**, amb una línia per equip:
nom, template, xarxa interna, RAM, CPU, grup de VirtualBox i IP prevista.
Per afegir un equip només cal afegir-hi una línia.

Per a cada equip, l'script:

1. Crea un **clon enllaçat** (`clonevm --snapshot base --options link`).
   El disc del clon és un disc diferencial que només guarda els canvis
   respecte al template.
2. Aplica la RAM, les CPU i el grup (`/VirtualCorp/Servers`, `Printers` o
   `Desktops`).
3. Connecta la **NIC1 a la xarxa interna** que li correspon, amb una MAC
   nova. Cap equip té NAT.
4. Assigna el **hostname** a `DmiSystemSerial`. En arrencar,
   `vcorp-firstboot` el llegeix de `/sys/class/dmi/id/product_serial`, el
   desa a `/etc/hostname` i `/etc/hosts` i regenera les claus SSH del host.
   Així cada clon té un nom i una identitat SSH pròpis sense cap
   intervenció manual.
5. Redirigeix COM1 a `artifacts/build/equipment/<nom>.serial.log`.
6. **Comprova l'arrencada**: engega els equips en tandes de 3 (per no
   esgotar la RAM de l'amfitrió), espera la línia
   `VCORP-READY <nom>` (que demostra que el sistema ha arrencat, que SSH és
   actiu i que el hostname és el correcte) i els apaga.

La comprovació es fa pel port sèrie perquè els equips estan connectats
només a xarxes internes: des de l'amfitrió no s'hi pot arribar per xarxa.

### 4.1 Correspondència entre màquines i xarxes internes

| Màquina | Template | Xarxa interna | Subxarxa | Router / porta d'enllaç | IP prevista |
| --- | --- | --- | --- | --- | --- |
| `pve01` | ISO Proxmox VE | `privada` | 10.25.0.128/26 | router0 · 10.25.0.129 | **10.25.0.133** (estàtica) |
| `dbsrv` | server | `privada` | 10.25.0.128/26 | router0 · 10.25.0.129 | 10.25.0.134 |
| `infosrv` | server | `privada` | 10.25.0.128/26 | router0 · 10.25.0.129 | 10.25.0.135 |
| `websrv` | server | `dmz` | 10.25.0.192/27 | router0 · 10.25.0.193 | 10.25.0.197 |
| `printer0` | server | `pl0` | 10.25.0.0/25 | router1 · 10.25.0.1 | 10.25.0.65 |
| `printer1` | server | `pl1` | 10.25.1.0/24 | router2 · 10.25.1.1 | 10.25.1.65 |
| `printer2` | server | `pl2` | 10.25.2.0/24 | router2 · 10.25.2.1 | 10.25.2.65 |
| `printer3` | server | `pl3` | 10.25.3.0/25 | router3 · 10.25.3.1 | 10.25.3.65 |
| `expo1`–`expo4` | desktop | `pl0` | 10.25.0.0/25 | router1 · 10.25.0.1 | 10.25.0.33–36 |
| `conserge1`, `conserge2` | desktop | `pl0` | 10.25.0.0/25 | router1 · 10.25.0.1 | DHCP |
| `pc-pl1-01`, `pc-pl1-02` | desktop | `pl1` | 10.25.1.0/24 | router2 · 10.25.1.1 | DHCP |
| `pc-pl2-01`, `pc-pl2-02` | desktop | `pl2` | 10.25.2.0/24 | router2 · 10.25.2.1 | DHCP |
| `pc-pl3-01`, `pc-pl3-02` | desktop | `pl3` | 10.25.3.0/25 | router3 · 10.25.3.1 | DHCP |
| `direccio1`–`direccio3` | desktop | `pl3-direccio` | 10.25.3.128/25 | router3 · 10.25.3.129 | DHCP |

Enllaços entre routers: `r0-r1` (10.25.0.224/30), `r1-r2`
(10.25.0.228/30) i `r2-r3` (10.25.0.232/30). Només `router0` (mikrotik0)
té una interfície NAT cap a l'exterior.

Totes les màquines, excepte pve01, fan **DHCP**. Les IP de la columna
«prevista» són les reservades pel projecte: s'hauran de fixar al servidor
DHCP quan es desplegui (amb reserves per MAC).

### 4.2 Recursos

| Grup | Equips | RAM | vCPU | Disc |
| --- | --- | --- | --- | --- |
| Servers | dbsrv, infosrv, websrv | 1024 MB | 2 | diferencial sobre el template (20 GB) |
| Printers | printer0–3 | 512 MB | 1 | diferencial |
| Desktops | 15 equips d'usuari | 2048 MB | 2 | diferencial |
| pve01 | — | 8192 MB | 4 | 64 GB dinàmic propi |

Els 22 clons ocupen menys de 700 MB de disc en total (els dos templates,
5,5 GB). L'amfitrió (15,6 GB de RAM) no pot executar totes les màquines
alhora, i per això la comprovació d'arrencada es fa per tandes.

---

## 5. Proxmox VE a pve01 (`deploy_pve.sh`)

`pve01` és l'única màquina que no surt d'un template. S'instal·la amb el
**mecanisme oficial d'instal·lació automàtica de Proxmox VE**: un fitxer de
respostes `answer.toml` incrustat a la ISO amb
`proxmox-auto-install-assistant prepare-iso --fetch-from iso`.

### 5.1 Procediment

1. Verifica la ISO `proxmox-ve_9.2-1.iso` (SHA256).
2. Descarrega i verifica `proxmox-auto-install-assistant` 9.2.9 i l'extreu
   amb `dpkg-deb`.
3. Genera `answer.toml` des de `configs/proxmox/answer.toml.tpl` i el valida
   amb `validate-answer`:
   - `fqdn = pve01.del25.virtualcorp.internal`, teclat `es`, zona
     `Europe/Madrid`.
   - `root-password-hashed`: hash SHA-512 de `PVE_ROOT_PASSWORD` (`.env`).
     La contrasenya mai s'escriu en clar.
   - `root-ssh-keys`: clau del professor i clau personal. Aquest és el
     mecanisme propi de Proxmox per autoritzar claus a root.
   - Xarxa `from-answer`: `10.25.0.133/26`, porta d'enllaç `10.25.0.129`
     (router0), DNS `1.1.1.1`. La NIC es tria amb
     `filter.ID_NET_NAME_MAC` i la MAC fixa `08:00:27:25:01:33`.
   - Disc: `filesystem = "ext4"`. Proxmox crea l'arrel en ext4 i
     l'emmagatzematge `local-lvm` en **LVM-thin**. No s'utilitza ZFS.
   - `[first-boot]`: hook `configs/proxmox/first-boot.sh` incrustat a la
     ISO, que s'executa un cop la xarxa ja és activa.
4. Genera `artifacts/build/pve01/pve01-auto.iso` (permisos `0600`, perquè
   conté el hash de root). En arrencar, el menú ja selecciona *Install
   Proxmox VE (Automated)*.
5. Crea la VM: 8192 MB, 4 vCPU, disc de 64 GB, una sola NIC a `privada`,
   COM1 a fitxer i **`--nested-hw-virt on`**, que s'aplica després de crear
   la VM i abans d'engegar-la.
6. Engega la VM. El disc buit no arrenca i la BIOS passa al DVD
   (instal·lador automàtic). En reiniciar, arrenca Proxmox des del disc.
7. Espera `PVE-READY` al port sèrie, treu la ISO i mostra el resultat de
   les comprovacions.

### 5.2 Validació des de dins de pve01

El hook de primera arrencada (`first-boot.sh`) comprova, **des de dins de
pve01**, el que demana l'enunciat i ho escriu a `/root/vcorp-validacio.log`
i al port sèrie (`artifacts/build/pve01/serial.log`):

- Virtualització anidada funcional: flag `vmx`/`svm` a `/proc/cpuinfo`,
  existència de `/dev/kvm` i mòdul `kvm_intel`/`kvm_amd` carregat.
- Ping a una IP de cada router: router0 `10.25.0.129`, router1
  `10.25.0.226`, router2 `10.25.0.230`, router3 `10.25.0.234`.
- Ping a una IP pública d'Internet (`1.1.1.1`).

Si KVM no té extensions de virtualització, el desplegament falla. Si falla
un ping, només mostra un avís (normalment vol dir que algun router està
apagat).

### 5.3 Per què una sola NIC

pve01 només necessita la xarxa `privada`: hi té la IP del projecte, la
porta d'enllaç (router0) i, a través del NAT de router0, Internet. Les
futures màquines virtuals de Proxmox es connectaran al bridge `vmbr0`
d'aquesta mateixa interfície.

---

## 6. Decisions de disseny i desviacions justificades

- **Noms de les xarxes internes.** L'enunciat proposa `pl3_direccio`,
  `rt0_1`, `rt1_2` i `rt2_3`, però els routers de l'activitat 1 ja estan
  desplegats amb `pl3-direccio`, `r0-r1`, `r1-r2` i `r2-r3`. A VirtualBox,
  el nom identifica el switch virtual: si els equips nous fessin servir un
  altre nom, quedarien en un switch diferent del del seu router i
  aïllats. Per això els equips nous usen **els noms existents**. Canviar-los
  obligaria a redesplegar i reconfigurar els routers.
- **router0 a la xarxa privada.** L'enunciat exigeix que pve01 arribi als
  quatre routers i a Internet, però cap router tenia interfície a la xarxa
  `privada`. S'hi ha afegit la NIC4 de router0 (`10.25.0.129/26`, anunciada
  per RIP), perquè router0 és el router del CPD i té el NAT cap a l'ISP.
- **conserge1 i conserge2.** El projecte els descriu com a equips Windows,
  però l'activitat demana desplegar la consergeria a partir del template
  Desktop. De moment són Debian LXQt.
- **DNS de pve01.** Encara no hi ha DNS a la delegació, de manera que
  s'usa `1.1.1.1` (a través del NAT de router0). S'haurà de canviar quan es
  desplegui el DNS intern. L'enunciat no demana resolució DNS en aquesta
  fase.
- **Hostname per DMI** en lloc de modificar cada disc: el clon no s'ha
  d'arrencar ni tocar abans de tenir el nom, i el mateix template serveix
  per a tots els equips.
- **Comprovació pel port sèrie** en lloc de per xarxa: no hi ha DHCP i els
  equips estan en xarxes internes, que l'amfitrió no veu.

---

## 7. Comprovacions realitzades

| Comprovació | Resultat |
| --- | --- |
| Templates creats i validats per SSH (usuari, claus, DHCP, paquets) | ✅ els dos, amb la instantània `base` |
| Desktop sense Firefox ni ofimàtica; sessió LXQt a SDDM | ✅ |
| 22 equips existents, amb els noms i els grups correctes (`make list_equipment`) | ✅ |
| Discos dels equips = discos diferencials del template (clonació enllaçada) | ✅ tots |
| Cada equip arrenca i anuncia `VCORP-READY <nom>` amb el hostname correcte | ✅ 22/22 |
| Cap VM, excepte mikrotik0, té cap interfície NAT | ✅ |
| Cada NIC a la xarxa interna que indica la taula 4.1 | ✅ |
| pve01: instal·lació desatesa, IP estàtica, KVM anidat, ping als routers i a Internet | ✅ `PVE-READY kvm=ok net=ok`: hostname `pve01.del25.virtualcorp.internal`, IP `10.25.0.133/26`, flag `vmx`, `/dev/kvm` i `kvm_intel`; ping OK als 4 routers (també confirma la propagació RIP) i a 1.1.1.1 |

Ordres útils per revisar-ho:

```bash
make list_equipment
VBoxManage showvminfo printer0 --machinereadable | grep -E 'intnet1|nic1|SATA-0-0|groups'
for v in $(VBoxManage list vms | cut -d'"' -f2); do
  VBoxManage showvminfo "$v" --machinereadable | grep -q '^nic[0-9]="nat"' && echo "NAT: $v"
done
cat artifacts/build/pve01/serial.log
```

---

## 8. Incidències i solucions

| Incidència | Causa | Solució |
| --- | --- | --- |
| `download.proxmox.com` falla per TLS (18 i 19/11/2026) | El certificat del CDN no incloïa aquest nom de servidor | Mirror oficial `enterprise.proxmox.com`, amb el mateix fitxer i el mateix SHA256 (fallback automàtic a `iso_ensure`) |
| El mirror de Debian es penja a mitja descàrrega | Un servidor del redirector (umu.se) deixa d'enviar dades | Descàrrega reprenible (`.part`), 5 intents i `--speed-limit` per detectar el bloqueig |
| Primer template: «Bad archive mirror» | A `mirror/http/directory` del preseed hi faltava el tipus `string` | S'hi ha afegit el tipus |
| SDDM mostra el teclat `us` | Sense paquets recomanats, X no tenia cap configuració de teclat; a més, X mostra el mapa per defecte fins a la primera pulsació | `00-keyboard.conf` amb `XkbLayout es`. Verificat: després de la primera tecla, l'indicador passa a `es` i el teclat real ja és `es` |
| Els clons apareixien al grup `templates` | `clonevm --groups` només decideix la carpeta; el grup el copia del template | `modifyvm --groups` després de clonar |
| Cap router a la xarxa `privada` | Disseny original de l'activitat 1 | NIC4 de router0 a `privada` (vegeu l'apartat 6) |

---

## 9. Disseny de xarxa

El PDF del disseny lògic i físic, adaptat a aquesta activitat, és a
`docs/disseny-xarxa-del25.pdf`. Conté el pla d'adreçament, el diagrama
lògic (routers, subxarxes i equips), el diagrama físic (adaptadors de
VirtualBox i xarxes internes) i l'inventari.

Es genera a partir de `docs/src/gen_disseny.py`, que escriu
`docs/src/disseny-xarxa-del25.html` (diagrames en SVG). Després, Chrome
en mode headless el converteix a PDF (vegeu les ordres a la capçalera de
l'script). Així el diagrama es pot actualitzar i regenerar quan canviï
l'inventari.

## 10. Fitxers de l'activitat

| Fitxer | Funció |
| --- | --- |
| `configs/versions.env` | Versions, URL i SHA256 fixats |
| `configs/equipment.conf` | Inventari dels equips (clons) |
| `configs/debian/preseed.cfg.tpl`, `configs/debian/files/*` | Instal·lació desatesa de Debian i serveis dels clons |
| `configs/proxmox/answer.toml.tpl`, `configs/proxmox/first-boot.sh` | Instal·lació desatesa de Proxmox VE i validació |
| `infrastructure/bash/common.sh` | Variables comunes (grups, domini, adreçament de pve01) |
| `infrastructure/bash/check_host.sh` | Comprovació de l'amfitrió |
| `infrastructure/bash/iso_lib.sh`, `download_isos.sh` | Descàrrega i verificació de les ISO |
| `infrastructure/bash/template_base.sh`, `create_templates.sh` | Creació dels templates |
| `infrastructure/bash/vm_lib.sh` | Funcions genèriques de VirtualBox |
| `infrastructure/bash/deploy_equipment.sh` | Clons enllaçats i orquestració |
| `infrastructure/bash/deploy_pve.sh` | Instal·lació de pve01 |
