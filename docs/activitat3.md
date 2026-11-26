# Activitat 3 · Ansible i VPN WireGuard

Delegació **25** · rang `10.25.0.0/16` · túnel VPN `10.25.10.0/24`

Aquest document explica com s'engeguen i s'aturen els routers amb Ansible i
com es desplega una VPN WireGuard d'accés dividit a `mikrotik0`. També recull
les variables d'adreçament i les proves que s'han fet. Tot el codi és a
`automation/ansible/`.

---

## 1. Posada en marxa ràpida

```bash
cd automation/ansible
ansible-galaxy collection install community.routeros ansible.netcommon
sudo apt install wireguard-tools

ansible-playbook playbooks/start_routers.yml        # engega mikrotik0..3
ansible-playbook playbooks/configure_wireguard.yml  # servidor + fitxer del client
sudo wg-quick up ../../artifacts/vpn/wg-vcorp.conf  # activa el túnel al client
sudo wg-quick down ../../artifacts/vpn/wg-vcorp.conf
ansible-playbook playbooks/stop_routers.yml         # atura els routers (ACPI)
```

Versions provades: ansible-core 2.16.3, ansible.netcommon 5.3.0,
community.routeros 2.12.0, paramiko 2.12.0, wireguard-tools 1.0.20210914 i
RouterOS 7.21.4.

---

## 2. Estructura

```text
automation/ansible/
├── ansible.cfg                       # inventari, roles_path, host_key_checking=True
├── inventories/
│   ├── lab.yml                       # localhost (VBoxManage) i mikrotik0 (RouterOS)
│   └── group_vars/all/wireguard.yml  # variables NO secretes de la VPN
├── playbooks/
│   ├── start_routers.yml
│   ├── stop_routers.yml
│   └── configure_wireguard.yml
└── roles/
    ├── start_vm/          # VBoxManage startvm si la VM no està en execució
    ├── stop_vm/           # acpipowerbutton i espera fins a poweroff
    ├── wireguard_server/  # natpf UDP + interfície, adreça, peer i tallafoc
    └── wireguard_client/  # claus del client i fitxer .conf (artifacts/vpn)
```

L'inventari no conté cap secret. `mikrotik0` s'hi connecta per
`network_cli` a `127.0.0.1:2200` (el reenviament TCP de VirtualBox cap al
port 22) amb l'usuari `sysadmin` i la clau `~/.ssh/vcorp_sysadmin`, que es
queda fora del repositori. El sufix `+cet1024w` de l'usuari fa que RouterOS
no enviï colors ni detecti el terminal, i que no talli les línies llargues.
Així la sortida es pot analitzar sense errors.

`host_key_checking` continua activat. La clau RSA de `mikrotik0`
(`SHA256:LfHKjGZEXXbLD/pUgNueQW89nnHMElKYWPq+foQ1+9w`) s'ha afegit a
`~/.ssh/known_hosts` després de comprovar que coincidia amb la que mostra el
router. Desactivar la comprovació hauria permès un atac MITM sense cap avís.

---

## 3. Part 1 · Engegar i aturar els routers

Els dos rols consulten primer l'estat amb
`VBoxManage showvminfo --machinereadable` i només actuen quan cal:

- **`start_vm`**: si la VM no és `running`, fa `startvm --type headless`.
- **`stop_vm`**: si la VM és `running`, envia `acpipowerbutton`, que és una
  aturada ordenada de RouterOS i no un tall d'alimentació. Després espera
  fins a `VMState="poweroff"` (30 reintents de 2 s).

Els playbooks recorren la llista `mikrotik_routers` de l'inventari.

| Prova | Resultat |
| --- | --- |
| `start_routers.yml`, 1a execució | `changed=4` (s'engeguen els 4 routers) |
| `start_routers.yml`, 2a execució | `changed=0`, 4 tasques *skipped* |
| `stop_routers.yml`, 1a execució | `changed=4`, amb aproximadament 1 reintent d'espera per router |
| `stop_routers.yml`, 2a execució | `changed=0`, 8 tasques *skipped* |

---

## 4. Part 2 · VPN WireGuard

### 4.1. Adreçament i variables

Tots els valors no secrets són a `inventories/group_vars/all/wireguard.yml`,
separats de les tasques:

| Variable | Valor | Motiu |
| --- | --- | --- |
| `wg_tunnel_prefix` | `10.25.10.0/24` | Rang reservat per l'enunciat. No se solapa amb la delegació (`10.25.0.0`–`10.25.3.255`) ni amb la xarxa del client (`172.16.0.0/21`). |
| `wg_server_address` | `10.25.10.1/24` | Adreça del servidor que fixa l'enunciat. |
| `wg_client_address` | `10.25.10.2/32` | Primer client (`sysadmin-portatil`). Cada client nou rebria la següent adreça. |
| `wg_interface` / `wg_listen_port` | `wg-vpn` / `51820` | Port estàndard de WireGuard. |
| `wg_endpoint_host:port` | `127.0.0.1:51820` | El client és l'amfitrió de VirtualBox. És una adreça local i no revela cap IP pública. |
| `wg_authorized_networks` | vegeu 4.2 | Llista per a `AllowedIPs` i per al tallafoc. |

### 4.2. Xarxes autoritzades (`AllowedIPs`)

El túnel és **d'accés dividit**: pel túnel només passa el trànsit cap a
VirtualCorp. El de la resta d'Internet surt directament per la xarxa del
client. Per això no s'utilitza `0.0.0.0/0`.

| Xarxa | Prefix | Inclosa |
| --- | --- | --- |
| túnel | `10.25.10.0/24` | sí |
| privada | `10.25.0.128/26` | sí. Servidors: pve01, dbsrv, infosrv. |
| dmz | `10.25.0.192/27` | sí. websrv. |
| pl0 | `10.25.0.0/25` | sí |
| pl1 | `10.25.1.0/24` | sí |
| pl2 | `10.25.2.0/24` | sí |
| pl3 | `10.25.3.0/25` | sí |
| pl3-direccio | `10.25.3.128/25` | **no**. És la xarxa aïllada de direcció de l'activitat 2; obrir-la per la VPN trencaria aquest aïllament. |
| enllaços entre routers | `10.25.0.224/28` | no. No hi ha cap servei per a l'usuari. |

La restricció s'aplica en dues capes:

1. **Al client**: `AllowedIPs` només crea rutes cap a aquestes xarxes, i
   WireGuard no xifra cap paquet adreçat a una altra destinació.
2. **Al servidor**: el tallafoc de `mikrotik0` només reenvia des de `wg-vpn`
   cap a la llista d'adreces `vcorp-vpn-autoritzades`, i descarta la resta.
   Així, encara que algú editi el seu fitxer de client, no arribarà a
   direcció.

### 4.3. Claus

- **Servidor**: RouterOS genera la clau privada en crear la interfície i no
  surt mai del router. Ansible només en llegeix la `public-key`.
- **Client**: `wg genkey` es fa al node de control i la clau es desa a
  `artifacts/vpn/sysadmin-portatil.key`. Si el fitxer ja existeix, no se
  sobreescriu (`creates:`). Per això la clau no canvia entre execucions.
- `artifacts/vpn/` té permisos `0700`, i la clau i `wg-vcorp.conf` tenen
  `0600`. El `.gitignore` ignora tot `artifacts/**` (comprovat amb
  `git check-ignore`).
- Les tasques que llegeixen o escriuen la clau privada porten
  `no_log: true`.

### 4.4. Rols i playbook

`playbooks/configure_wireguard.yml` executa tres *plays* en ordre:

1. **localhost**: `wireguard_client` (`keys.yml`) genera o llegeix la clau
   del client i n'obté la pública.
2. **mikrotik0**: `wireguard_server` crea el reenviament UDP, la interfície,
   l'adreça, el peer, la llista d'adreces i les regles de tallafoc. També
   llegeix la clau pública del servidor.
3. **localhost**: `wireguard_client` (`config.yml`) escriu
   `artifacts/vpn/wg-vcorp.conf` a partir de la plantilla `client.conf.j2`.

**Idempotència a RouterOS.** Cada ordre de `community.routeros.command` és
un petit script RouterOS que fa tres coses:

- busca l'objecte pel nom, o pel comentari `vcorp-wg: …`;
- si no hi és, o si algun valor no coincideix, el crea o el corregeix;
- escriu `CHANGED` o `OK`, i Ansible marca la tasca com a `changed` només
  quan surt `CHANGED`.

La interfície i el peer es corregeixen amb `set` i no s'esborren, perquè
esborrar la interfície canviaria la clau del servidor. L'adreça, les
entrades de la llista i les regles de tallafoc, en canvi, s'esborren i es
tornen a crear quan no coincideixen. A més, el rol treu de la llista les
xarxes que s'eliminen de `wg_authorized_networks`.

### 4.5. Reenviament UDP de VirtualBox

La NIC1 de `mikrotik0` és NAT de VirtualBox, i des de l'amfitrió no s'hi
pot arribar directament. Per això, una tasca local del rol del servidor
(`delegate_to: localhost`) crea aquesta regla:

```text
wireguard,udp,127.0.0.1,51820,,51820      # NIC1: 127.0.0.1:51820 -> 10.0.2.15:51820
```

Abans de crear-la, la tasca consulta `showvminfo`. Si la regla ja existeix,
no fa res. Si n'hi ha una amb el mateix nom però amb valors diferents,
l'esborra i la torna a crear. Amb la VM encesa fa servir
`controlvm natpf1`, i amb la VM apagada, `modifyvm --natpf1`. Només escolta
a `127.0.0.1`, de manera que el port no queda exposat a la xarxa del
portàtil.

### 4.6. Regles de tallafoc afegides a `mikrotik0`

Abans de l'activitat, `/ip firewall filter` estava buit. La NAT només té el
`masquerade` cap a `ether1` (Internet), i entre el túnel i les xarxes
internes no s'aplica NAT. Per això els equips veuen l'adreça real del client,
`10.25.10.2`.

| # | Comentari | Regla | Posició |
| --- | --- | --- | --- |
| 0 | `vcorp-wg: forward VPN a xarxes autoritzades` | `chain=forward in-interface=wg-vpn dst-address-list=vcorp-vpn-autoritzades action=accept` | al principi |
| 1 | `vcorp-wg: input UDP 51820` | `chain=input protocol=udp dst-port=51820 action=accept` | al principi, abans de qualsevol `drop` |
| 2 | `vcorp-wg: forward VPN resta descartat` | `chain=forward in-interface=wg-vpn action=drop` | al final |

La llista `vcorp-vpn-autoritzades` conté les sis xarxes de la taula 4.2.

**Rutes de retorn.** RIP (`rip1`) ja redistribueix les rutes `connected`,
de manera que `10.25.10.0/24` s'anuncia als altres routers sense modificar
cap configuració de `mikrotik1`–`mikrotik3`.

### 4.7. Fitxer del client (versió sense secrets)

```ini
[Interface]
PrivateKey = <clau privada del client>
Address = 10.25.10.2/32

[Peer]
PublicKey = <clau pública de mikrotik0>
Endpoint = 127.0.0.1:51820
AllowedIPs = 10.25.10.0/24, 10.25.0.128/26, 10.25.0.192/27, 10.25.0.0/25, 10.25.1.0/24, 10.25.2.0/24, 10.25.3.0/25
PersistentKeepalive = 25
```

`PersistentKeepalive = 25` manté oberta l'entrada de la NAT de VirtualBox,
de manera que el router sempre pot enviar paquets al client.

---

## 5. Proves de la VPN (2026-11-26)

| Prova | Resultat |
| --- | --- |
| `configure_wireguard.yml`, 1a execució | `mikrotik0 changed=6`, `localhost changed=3` |
| `configure_wireguard.yml`, 2a execució | `changed=0` als dos hosts. Una sola interfície, una adreça, un peer, 6 entrades a la llista i 3 regles, sense duplicats. |
| Handshake a RouterOS | `last-handshake` de pocs segons; `current-endpoint-address=10.0.2.2` (la NAT de VirtualBox) |
| Ping a `10.25.10.1` (router pel túnel) | 0 % de pèrdua |
| Ping a la passarel·la de cada xarxa autoritzada: `.0.129` privada, `.0.193` dmz, `.0.1` pl0, `.1.1` pl1, `.2.1` pl2, `.3.1` pl3 | 0 % de pèrdua a totes. `pl1`–`pl3` són a `mikrotik1`–`mikrotik3`, per tant les rutes de retorn per RIP funcionen. |
| Ping a un equip: `pve01` (`10.25.0.133`, privada) | 0 % de pèrdua. També funcionen SSH (`pve01.del25.virtualcorp.internal`) i el port 8006 (interfície web de Proxmox). |
| Ping a `websrv` i `printer0`–`printer3` | No responen ni des del mateix `mikrotik0` (ARP `failed`). Els clons Debian fan servir DHCP i els routers encara no tenen cap servidor DHCP, de manera que arrenquen sense IP. Les adreces de `configs/equipment.conf` són les previstes. Per això, a cada xarxa s'ha provat la passarel·la del router (fila anterior), i com a equip final, `pve01`, que té IP estàtica. |
| Ping a `10.25.3.129` (pl3-direccio) | 100 % de pèrdua. `ip route get` mostra que surt per `wlo1` i no pel túnel. |
| SSH a `sysadmin@10.25.10.1` pel túnel | Correcte (`mikrotik0`) |
| Internet directa | `ip route get 1.1.1.1` → `via 172.16.0.1 dev wlo1`; el ping funciona |
| Desactivar i reactivar `wg-vpn` | Desactivada: no hi ha resposta. Reactivada: el client torna a negociar la sessió i el túnel respon al cap d'uns 15 s, sense pèrdua. |
| Reinici de `mikrotik0` (`/system reboot`) | Amb `uptime 28s`: hi ha handshake, el ping funciona i la configuració es manté. El playbook torna a donar `changed=0`. |

El comptador de la regla 2 (`drop`) queda a 0. La primera capa, el client,
ja no envia per `wg-vpn` el trànsit cap a xarxes no autoritzades. La regla
és la protecció del servidor si algú modifica el fitxer del client.

---

## 6. Incidències i decisions

- **`ansible-pylibssh` no està instal·lat**, i `network_cli` fa servir
  paramiko (és només un avís). Paramiko llegeix `~/.ssh/known_hosts`, i per
  això calia afegir-hi la clau del router abans de la primera connexió.
- **`sudo` no pot demanar la contrasenya** a l'entorn on s'executa Ansible.
  `wg-quick up/down` s'ha d'executar en un terminal interactiu.
- **Els comentaris com a identificadors**: el prefix `vcorp-wg:` permet
  trobar els objectes creats per Ansible sense dependre dels números de
  RouterOS, que canvien quan s'afegeixen o s'esborren regles.
