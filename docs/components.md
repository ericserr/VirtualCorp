# Components del projecte

Aquesta pàgina descriu les carpetes del repositori i la funció de cada fitxer.
Cobreix el desplegament dels routers (activitat 1, MikroTik RouterOS CHR) i el
dels templates Debian, els equips i Proxmox VE (activitat 2), i també
l'automatització amb Ansible i la VPN WireGuard (activitat 3). El procediment
detallat i les decisions de disseny són a [activitat2.md](activitat2.md) i
[activitat3.md](activitat3.md).

## Estructura de carpetes

```text
.
├── artifacts/
│   ├── build/            (generada, no versionada)
│   └── images/
│       ├── chr/
│       └── iso/          (generada, no versionada)
├── automation/
│   ├── ansible/
│   └── scripts/
│       └── bootstrap/
├── configs/
│   ├── debian/
│   │   └── files/
│   ├── proxmox/
│   └── ssh/
├── docs/
│   └── src/
└── infrastructure/
    ├── bash/
    └── terraform/
```

| Carpeta | Funció |
| --- | --- |
| `artifacts/images/chr/` | Imatge de disc de RouterOS CHR descarregada. Git n'ignora el contingut; `.gitkeep` conserva la carpeta. |
| `artifacts/images/iso/` | ISO de Debian i de Proxmox VE, descarregades i verificades. Ignorada per Git. |
| `artifacts/build/` | Fitxers generats: ISO desateses, registres del port sèrie i eines extretes. Ignorada per Git. |
| `automation/ansible/` | Inventari, rols i playbooks d'Ansible: engegar i aturar els routers i configurar la VPN WireGuard (activitat 3). |
| `artifacts/vpn/` | Claus i fitxer `.conf` del client WireGuard, generats per Ansible amb permisos `0700`/`0600`. Ignorada per Git. |
| `automation/scripts/bootstrap/` | Scripts de preparació inicial de l'entorn. |
| `configs/` | Versions fixades i inventari d'equips. |
| `configs/debian/` | Instal·lació desatesa de Debian i serveis propis dels templates. |
| `configs/proxmox/` | Instal·lació desatesa de Proxmox VE. |
| `configs/ssh/` | Claus SSH públiques. Les privades es guarden fora del repositori, normalment a `~/.ssh`. |
| `docs/` | Documentació del projecte i enunciat. |
| `docs/src/` | Fonts amb què es genera el PDF del disseny de xarxa. |
| `infrastructure/bash/` | Scripts que creen les màquines virtuals, les connecten i les configuren. |
| `infrastructure/terraform/` | Reservada per a Terraform. De moment només conté `.gitkeep`. |

## Fitxers principals

### Arrel del repositori

| Fitxer | Funció |
| --- | --- |
| `Makefile` | Punt d'entrada de tots els processos. Carrega `.env` i `configs/versions.env`. |
| `.env.example` | Exemple de configuració local: camins, claus, grups de VirtualBox, recursos de pve01 i contrasenyes (aquestes, només al `.env`). Cal copiar-lo a `.env`. |
| `.gitignore` | Exclou la configuració local, les credencials, les imatges i els fitxers generats. |
| `readme.md` | Presentació, requisits, posada en marxa dels routers i prova de connectivitat. |

### `automation/scripts/bootstrap/`

| Fitxer | Funció |
| --- | --- |
| `create_ssh_keys.sh` | Genera les claus d'auditor, de sysadmin i la compatible amb MikroTik. Les públiques es copien a `configs/ssh/`. |
| `create_mikrotik_box.sh` | Utilitat antiga per empaquetar una imatge RouterOS. El desplegament actual no la fa servir. |

### `configs/`

| Fitxer | Funció |
| --- | --- |
| `versions.env` | Versions, URL i SHA256 fixats de Debian, de Proxmox VE i de l'assistent d'instal·lació. El llegeixen el `Makefile` i els scripts. |
| `equipment.conf` | Inventari dels 22 equips: nom, template, xarxa interna, RAM, CPU, grup i IP prevista. |
| `debian/preseed.cfg.tpl` | Plantilla de respostes de l'instal·lador de Debian. |
| `debian/files/late.sh` | Personalitza el sistema al final de la instal·lació: claus autoritzades, `sshd`, teclat i serveis propis. |
| `debian/files/vcorp-firstboot.sh`, `.service` | En arrencar, regenera les claus SSH de host si falten i fixa el hostname a partir del número de sèrie DMI. |
| `debian/files/vcorp-ready.service` | Escriu `VCORP-READY <hostname>` al port sèrie quan SSH és actiu. |
| `debian/files/vcorp-seal.sh` | Segella el template: esborra les claus de host, el `machine-id`, les concessions DHCP i els registres. |
| `proxmox/answer.toml.tpl` | Plantilla de respostes de l'instal·lador de Proxmox VE. |
| `proxmox/first-boot.sh` | Comprova KVM i la connectivitat des de pve01 i escriu `PVE-READY` al port sèrie. |
| `ssh/vcorp_auditor.pub` | Clau pública del professor (auditor). |
| `ssh/vcorp_mikrotik.pub` | Clau pública en el format compatible amb MikroTik. |
| `ssh/vcorp_sysadmin.pub` | Clau pública de l'administrador (clau personal). |

### `infrastructure/bash/`

| Fitxer | Funció |
| --- | --- |
| `common.sh` | Variables compartides (VirtualBox, camins, grups, domini), funcions de registre i espera de SSH. |
| `router_base.sh` | Funcions per crear els routers, connectar-ne les interfícies i configurar RouterOS. |
| `deploy_routers.sh` | Defineix i crea els quatre routers (`mikrotik0`–`mikrotik3`). |
| `del_vbox_group.sh` | Esborra les VM d'un grup de VirtualBox i dels seus subgrups. |
| `check_host.sh` | Comprova que l'amfitrió compleix els requisits de l'activitat 2. |
| `iso_lib.sh` | Funcions per descarregar i verificar ISO i per generar la de Debian desatesa. |
| `download_isos.sh` | Descarrega i verifica les ISO fixades (`debian`, `pve` o `all`). |
| `template_base.sh` | Paquets de cada template i funcions per generar-ne el preseed i la ISO. |
| `create_templates.sh` | Crea, valida i segella `tpl-debian-server` i `tpl-debian-desktop`. |
| `vm_lib.sh` | Funcions genèriques de VirtualBox: estat, espera, apagada, esborrat i SSH. |
| `deploy_equipment.sh` | Crea i comprova els clons enllaçats i orquestra la instal·lació de pve01. |
| `deploy_pve.sh` | Instal·la Proxmox VE a `pve01` de manera desatesa. |

### `docs/`

| Fitxer | Funció |
| --- | --- |
| `components.md` | Aquest document. |
| `activitat2.md` | Procediment, decisions, comprovacions i incidències de l'activitat 2. |
| `activitat3.md` | Ansible (start/stop dels routers) i VPN WireGuard: variables d'adreçament, tallafoc i proves. |
| `disseny-xarxa-del25.pdf` | Disseny lògic i físic de la xarxa de la delegació 25. |
| `src/gen_disseny.py`, `src/disseny-xarxa-del25.html` | Script que genera el disseny i HTML resultant, d'on surt el PDF. |
| `statement.html` | Escenari, requisits i detalls del projecte. |

## Targets de `make`

| Target | Funció |
| --- | --- |
| `ssh-keys` | Genera les claus SSH del projecte. |
| `deploy-routers`, `delete-routers`, `reset-routers` | Crea, esborra o recrea els routers. |
| `routeros-box` | Executa la utilitat antiga d'empaquetament. |
| `check_host` | Comprova l'amfitrió. |
| `download_isos` | Descarrega i verifica les ISO. |
| `create_templates`, `delete_templates` | Crea o esborra els templates Debian (`ROLE=`; `FORCE=1` per refer-los). |
| `deploy_equipment`, `delete_equipment` | Desplega o esborra els equips i pve01 (`VMS="a b"`; `FORCE=1` i `VERIFY=0` en desplegar). |
| `list_equipment` | Mostra l'inventari i l'estat de cada màquina. |

## Flux de treball habitual

1. Copiar `.env.example` a `.env`, adaptar-lo i definir-hi les contrasenyes.
2. `make ssh-keys`, si les claus encara no existeixen.
3. `make check_host` per comprovar l'amfitrió.
4. `make deploy-routers` per crear els routers.
5. `make create_templates` (descarrega i verifica abans les ISO).
6. `make deploy_equipment` per desplegar els equips i pve01.
7. `make list_equipment` per revisar el resultat.
