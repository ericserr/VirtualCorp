#!/usr/bin/env python3
"""Genera el disseny de xarxa de la delegació 25 (HTML amb SVG).

Ús (des de l'arrel del repositori):
    python3 docs/src/gen_disseny.py docs/src/disseny-xarxa-del25.html
    google-chrome --headless=new --no-pdf-header-footer \
        --print-to-pdf="$PWD/docs/disseny-xarxa-del25.pdf" \
        "file://$PWD/docs/src/disseny-xarxa-del25.html"
"""
import sys
from html import escape

OUT = sys.argv[1]

# ---------------- Dades ----------------
SUBNETS = [  # intnet, subxarxa, gw, router, color, hosts
    ("dmz", "10.25.0.192/27", "10.25.0.193", "router0", "#f4d7c6",
     [("websrv", ".197")]),
    ("privada", "10.25.0.128/26", "10.25.0.129", "router0", "#d6e4f5",
     [("pve01", ".133 fixa"), ("dbsrv", ".134"), ("infosrv", ".135")]),
    ("pl0", "10.25.0.0/25", "10.25.0.1", "router1", "#dcefd9",
     [("printer0", ".65"), ("expo1", ".33"), ("expo2", ".34"), ("expo3", ".35"),
      ("expo4", ".36"), ("conserge1", "DHCP"), ("conserge2", "DHCP")]),
    ("pl1", "10.25.1.0/24", "10.25.1.1", "router2", "#ece0f3",
     [("printer1", ".65"), ("pc-pl1-01", "DHCP"), ("pc-pl1-02", "DHCP")]),
    ("pl2", "10.25.2.0/24", "10.25.2.1", "router2", "#ece0f3",
     [("printer2", ".65"), ("pc-pl2-01", "DHCP"), ("pc-pl2-02", "DHCP")]),
    ("pl3", "10.25.3.0/25", "10.25.3.1", "router3", "#f6efc8",
     [("printer3", ".65"), ("pc-pl3-01", "DHCP"), ("pc-pl3-02", "DHCP")]),
    ("pl3-direccio", "10.25.3.128/25", "10.25.3.129", "router3", "#f5d0d0",
     [("direccio1", "DHCP"), ("direccio2", "DHCP"), ("direccio3", "DHCP")]),
]
ROUTERS = ["router0", "router1", "router2", "router3"]
ROUTER_VM = {"router0": "mikrotik0", "router1": "mikrotik1",
             "router2": "mikrotik2", "router3": "mikrotik3"}
LINKS = [("router0", "router1", "r0-r1", "10.25.0.224/30", ".225", ".226"),
         ("router1", "router2", "r1-r2", "10.25.0.228/30", ".229", ".230"),
         ("router2", "router3", "r2-r3", "10.25.0.232/30", ".233", ".234")]

FONT = "font-family='DejaVu Sans, Arial, sans-serif'"


def text(x, y, s, size=12, weight="normal", anchor="middle", fill="#1d2430"):
    return (f"<text x='{x}' y='{y}' {FONT} font-size='{size}' font-weight='{weight}' "
            f"text-anchor='{anchor}' fill='{fill}'>{escape(s)}</text>")


# ---------------- Diagrama lògic ----------------
def logical_svg():
    W, H = 1240, 625
    bw, step, x0 = 165, 175, 15
    by, bh = 380, 225
    box_cx = [x0 + step * i + bw / 2 for i in range(len(SUBNETS))]
    rx = {"router0": (box_cx[0] + box_cx[1]) / 2, "router1": box_cx[2],
          "router2": (box_cx[3] + box_cx[4]) / 2, "router3": (box_cx[5] + box_cx[6]) / 2}
    ry = 225
    s = [f"<svg viewBox='0 0 {W} {H}' xmlns='http://www.w3.org/2000/svg'>"]
    # Internet
    ix, iy = rx["router0"], 70
    s.append(f"<ellipse cx='{ix}' cy='{iy}' rx='95' ry='38' fill='#eef1f5' stroke='#5b6675' stroke-width='1.5'/>")
    s.append(text(ix, iy - 3, "Internet / ISP", 14, "bold"))
    s.append(text(ix, iy + 15, "via NAT de VirtualBox", 11))
    s.append(f"<line x1='{ix}' y1='{iy + 38}' x2='{ix}' y2='{ry - 32}' stroke='#5b6675' stroke-width='2' stroke-dasharray='6 4'/>")
    s.append(text(ix + 8, (iy + 38 + ry - 32) / 2 + 4, "ether1 · NAT (DHCP 10.0.2.0/24)", 11, anchor="start", fill="#5b6675"))
    # Enllaços entre routers
    for a, b, net, cidr, ia, ib in LINKS:
        x1, x2 = rx[a] + 62, rx[b] - 62
        s.append(f"<line x1='{x1}' y1='{ry}' x2='{x2}' y2='{ry}' stroke='#33475b' stroke-width='3'/>")
        mx = (x1 + x2) / 2
        s.append(text(mx, ry - 26, f"{net}", 12, "bold"))
        s.append(text(mx, ry - 12, cidr, 11))
        s.append(text(x1 + 4, ry + 16, ia, 11, anchor="start"))
        s.append(text(x2 - 4, ry + 16, ib, 11, anchor="end"))
    # Routers
    for r in ROUTERS:
        x = rx[r]
        s.append(f"<rect x='{x - 62}' y='{ry - 32}' width='124' height='64' rx='10' fill='#33475b'/>")
        s.append(text(x, ry - 6, r, 15, "bold", fill="#ffffff"))
        s.append(text(x, ry + 13, f"{ROUTER_VM[r]} · RIP", 11, fill="#dfe7ef"))
    # Subxarxes
    for i, (net, cidr, gw, r, color, hosts) in enumerate(SUBNETS):
        bx = x0 + step * i
        cx = bx + bw / 2
        s.append(f"<path d='M{rx[r]},{ry + 32} L{rx[r]},{ry + 75} L{cx},{ry + 75} L{cx},{by}' "
                 f"fill='none' stroke='#33475b' stroke-width='2'/>")
        s.append(text(cx + 5, by - 8, f"gw {gw}", 10.5, anchor="start", fill="#33475b"))
        s.append(f"<rect x='{bx}' y='{by}' width='{bw}' height='{bh}' rx='8' fill='{color}' stroke='#5b6675'/>")
        s.append(text(cx, by + 22, net, 14, "bold"))
        s.append(text(cx, by + 40, cidr, 12))
        s.append(f"<line x1='{bx + 10}' y1='{by + 50}' x2='{bx + bw - 10}' y2='{by + 50}' stroke='#8792a2'/>")
        for j, (h, ip) in enumerate(hosts):
            yy = by + 72 + j * 21
            s.append(text(bx + 12, yy, h, 12, "bold" if h == "pve01" else "normal", anchor="start"))
            s.append(text(bx + bw - 12, yy, ip, 11.5, anchor="end", fill="#3d4756"))
    # Llegenda
    s.append(text(15, H - 6, "Totes les xarxes formen part de 10.25.0.0/16. Encaminament dinàmic RIP "
                  "(redistribute connected); ruta per defecte cap a router0.", 11, anchor="start", fill="#3d4756"))
    s.append("</svg>")
    return "\n".join(s)


# ---------------- Diagrama físic (VirtualBox) ----------------
SWITCHES = ["NAT", "dmz", "privada", "r0-r1", "pl0", "r1-r2", "pl1", "pl2", "r2-r3", "pl3", "pl3-direccio"]
ROUTER_NICS = {  # router -> [(nic, switch)]
    "mikrotik0": [(1, "NAT"), (2, "r0-r1"), (3, "dmz"), (4, "privada")],
    "mikrotik1": [(1, "r0-r1"), (2, "r0-r1"), (3, "r1-r2"), (4, "pl0")],
    "mikrotik2": [(1, "r1-r2"), (2, "r1-r2"), (3, "r2-r3"), (4, "pl1"), (5, "pl2")],
    "mikrotik3": [(1, "r2-r3"), (2, "r2-r3"), (3, "pl3"), (4, "pl3-direccio")],
}


def physical_svg():
    W, H = 1240, 700
    step, sw, x0 = 111, 101, 14
    sy, sh = 300, 44
    sx = {n: x0 + step * i for i, n in enumerate(SWITCHES)}
    scx = {n: sx[n] + sw / 2 for n in SWITCHES}
    rpos = {"mikrotik0": (scx["dmz"] + scx["privada"]) / 2 - 30, "mikrotik1": scx["pl0"],
            "mikrotik2": (scx["pl1"] + scx["pl2"]) / 2, "mikrotik3": (scx["pl3"] + scx["r2-r3"]) / 2 + 40}
    ry = 90
    s = [f"<svg viewBox='0 0 {W} {H}' xmlns='http://www.w3.org/2000/svg'>"]
    s.append(f"<rect x='4' y='4' width='{W - 8}' height='{H - 30}' rx='12' fill='none' stroke='#8792a2' stroke-dasharray='8 5'/>")
    s.append(text(16, 26, "Amfitrió: Ubuntu 24.04 · VirtualBox 7.2 · i5-1235U, 15,6 GB RAM", 12, "bold", anchor="start", fill="#5b6675"))
    # Routers i NIC
    for r, nics in ROUTER_NICS.items():
        x = rpos[r]
        for k, (nic, swn) in enumerate(nics):
            ox = x - 50 + k * (100 / max(1, len(nics) - 1))
            col = "#b5502b" if swn == "NAT" else "#33475b"
            dash = " stroke-dasharray='6 4'" if swn == "NAT" else ""
            s.append(f"<line x1='{ox}' y1='{ry + 28}' x2='{scx[swn]}' y2='{sy}' stroke='{col}' stroke-width='1.6'{dash}/>")
            s.append(text(ox, ry + 42, f"N{nic}", 9.5, fill=col))
        s.append(f"<rect x='{x - 60}' y='{ry - 28}' width='120' height='56' rx='9' fill='#33475b'/>")
        s.append(text(x, ry - 4, r, 14, "bold", fill="#ffffff"))
        s.append(text(x, ry + 14, "RouterOS CHR", 10.5, fill="#dfe7ef"))
    # Switches (xarxes internes)
    vms = {n: [] for n in SWITCHES}
    for net, _c, _g, _r, _col, hosts in SUBNETS:
        vms[net] = [h for h, _ in hosts]
    for n in SWITCHES:
        nat = n == "NAT"
        fill = "#fbe3d6" if nat else ("#e3e8ef" if n.startswith("r") and "-" in n else "#d6e4f5")
        s.append(f"<rect x='{sx[n]}' y='{sy}' width='{sw}' height='{sh}' rx='6' fill='{fill}' stroke='#33475b' stroke-width='1.5'/>")
        s.append(text(scx[n], sy + 19, n, 12.5 if len(n) < 10 else 11, "bold"))
        s.append(text(scx[n], sy + 35, "NAT VBox" if nat else "intnet", 10, fill="#5b6675"))
        for j, v in enumerate(vms[n]):
            vy = sy + sh + 40 + j * 34
            s.append(f"<line x1='{scx[n]}' y1='{sy + sh if j == 0 else vy - 34 + 12}' x2='{scx[n]}' y2='{vy - 12}' stroke='#33475b' stroke-width='1.4'/>")
            fillv = "#ffffff" if v != "pve01" else "#fff4d6"
            s.append(f"<rect x='{sx[n] + 4}' y='{vy - 12}' width='{sw - 8}' height='24' rx='5' fill='{fillv}' stroke='#5b6675'/>")
            s.append(text(scx[n], vy + 4, v, 11, "bold" if v == "pve01" else "normal"))
    s.append(text(16, H - 8, "N1..N5 = adaptadors de xarxa de cada router. Tots els equips tenen UNA sola NIC (NIC1) en mode "
                  "xarxa interna; només mikrotik0 té NAT. NIC1 de mikrotik1-3 duplica la xarxa de la NIC2, sense IP (disseny de l'activitat 1).",
                  10.5, anchor="start", fill="#3d4756"))
    s.append("</svg>")
    return "\n".join(s)


# ---------------- Taules ----------------
INVENTORY = [
    ("pve01", "Proxmox VE 9.2 (ISO)", "privada", "10.25.0.133/26 estàtica", "8192 MB · 4 vCPU · 64 GB · nested"),
    ("dbsrv", "Debian Server", "privada", "10.25.0.134 (DHCP)", "1024 MB · 2 vCPU"),
    ("infosrv", "Debian Server", "privada", "10.25.0.135 (DHCP)", "1024 MB · 2 vCPU"),
    ("websrv", "Debian Server", "dmz", "10.25.0.197 (DHCP)", "1024 MB · 2 vCPU"),
    ("printer0..3", "Debian Server", "pl0, pl1, pl2, pl3", "10.25.n.65 (DHCP)", "512 MB · 1 vCPU"),
    ("expo1..4", "Debian Desktop", "pl0", "10.25.0.33–36 (DHCP)", "2048 MB · 2 vCPU"),
    ("conserge1..2", "Debian Desktop", "pl0", "DHCP", "2048 MB · 2 vCPU"),
    ("pc-pl1-01/02", "Debian Desktop", "pl1", "DHCP", "2048 MB · 2 vCPU"),
    ("pc-pl2-01/02", "Debian Desktop", "pl2", "DHCP", "2048 MB · 2 vCPU"),
    ("pc-pl3-01/02", "Debian Desktop", "pl3", "DHCP", "2048 MB · 2 vCPU"),
    ("direccio1..3", "Debian Desktop", "pl3-direccio", "DHCP", "2048 MB · 2 vCPU"),
]
ADDR = [
    ("Planta baixa · zona general", "10.25.0.0/25", "pl0", "router1 · 10.25.0.1", "Consergeria, expositors, printer0"),
    ("Planta baixa · zona privada", "10.25.0.128/26", "privada", "router0 · 10.25.0.129", "CPD intern: pve01, dbsrv, infosrv"),
    ("Planta baixa · DMZ", "10.25.0.192/27", "dmz", "router0 · 10.25.0.193", "Serveis públics: websrv"),
    ("Enllaç router0–router1", "10.25.0.224/30", "r0-r1", ".225 / .226", "Troncal"),
    ("Enllaç router1–router2", "10.25.0.228/30", "r1-r2", ".229 / .230", "Troncal"),
    ("Enllaç router2–router3", "10.25.0.232/30", "r2-r3", ".233 / .234", "Troncal"),
    ("Planta 1", "10.25.1.0/24", "pl1", "router2 · 10.25.1.1", "Desenvolupament i projectes"),
    ("Planta 2", "10.25.2.0/24", "pl2", "router2 · 10.25.2.1", "Desenvolupament i projectes"),
    ("Planta 3 · departaments", "10.25.3.0/25", "pl3", "router3 · 10.25.3.1", "Comercial, gestió, màrqueting"),
    ("Planta 3 · direcció", "10.25.3.128/25", "pl3-direccio", "router3 · 10.25.3.129", "Xarxa aïllada de direcció"),
]


def table(head, rows):
    h = "".join(f"<th>{escape(c)}</th>" for c in head)
    b = "".join("<tr>" + "".join(f"<td>{escape(c)}</td>" for c in r) + "</tr>" for r in rows)
    return f"<table><thead><tr>{h}</tr></thead><tbody>{b}</tbody></table>"


HTML = f"""<!doctype html>
<html lang="ca"><head><meta charset="utf-8">
<title>Disseny de xarxa · Delegació 25</title>
<style>
@page {{ size: A4 landscape; margin: 12mm; }}
body {{ font-family: 'DejaVu Sans', Arial, sans-serif; color:#1d2430; margin:0; font-size:11pt; }}
section {{ page-break-after: always; }}
section:last-child {{ page-break-after: auto; }}
h1 {{ font-size:22pt; margin:0 0 4px; color:#33475b; }}
h2 {{ font-size:15pt; margin:0 0 8px; color:#33475b; border-bottom:2px solid #33475b; padding-bottom:3px; }}
p.sub {{ margin:0 0 14px; color:#5b6675; }}
table {{ border-collapse:collapse; width:100%; font-size:9.5pt; margin-bottom:10px; }}
th {{ background:#33475b; color:#fff; text-align:left; padding:5px 7px; }}
td {{ border-bottom:1px solid #cfd6df; padding:4px 7px; }}
tr:nth-child(even) td {{ background:#f3f5f8; }}
svg {{ width:100%; height:auto; }}
ul {{ margin:4px 0; padding-left:18px; font-size:10pt; }}
li {{ margin-bottom:3px; }}
.cols {{ display:flex; gap:18px; }} .cols > div {{ flex:1; }}
</style></head><body>

<section>
<h1>VirtualCorp · Delegació 25 · Disseny de xarxa</h1>
<p class="sub">Rang 10.25.0.0/16 · domini del25.virtualcorp.internal · Activitat 2 (templates i desplegament d'equips) · novembre 2026</p>
<h2>Pla d'adreçament</h2>
{table(["Segment", "Xarxa", "Xarxa interna VBox", "Router / porta d'enllaç", "Ús"], ADDR)}
<div class="cols"><div>
<h2>Adreces reservades</h2>
<ul>
<li><b>pve01</b> 10.25.0.133 (estàtica) · <b>dbsrv</b> .134 · <b>infosrv</b> .135 a la zona privada.</li>
<li><b>websrv</b> 10.25.0.197 a la DMZ.</li>
<li><b>printer0..3</b> 10.25.n.65 (n = planta) · <b>expo1..4</b> 10.25.0.33–36.</li>
<li>Totes les màquines, excepte pve01, usen DHCP; les IP reservades es fixaran amb reserves per MAC quan es desplegui el servei DHCP.</li>
</ul></div><div>
<h2>Canvis respecte al disseny anterior</h2>
<ul>
<li>router0 té una interfície nova a la zona <b>privada</b> (10.25.0.129/26), anunciada per RIP, perquè pve01 arribi als routers i a Internet.</li>
<li>Es fan servir els noms de xarxa interna dels routers ja desplegats: <b>pl3-direccio</b>, <b>r0-r1</b>, <b>r1-r2</b>, <b>r2-r3</b> (l'enunciat proposa pl3_direccio i rt0_1…).</li>
<li>S'hi afegeixen els 22 equips i pve01 desplegats en aquesta activitat.</li>
</ul></div></div>
</section>

<section>
<h2>Diagrama lògic (nivell 3)</h2>
{logical_svg()}
</section>

<section>
<h2>Diagrama físic (VirtualBox: adaptadors i xarxes internes)</h2>
{physical_svg()}
</section>

<section>
<h2>Inventari d'equips</h2>
{table(["Equip", "Origen", "Xarxa interna", "Adreçament", "Recursos"], INVENTORY)}
<ul>
<li>Els equips Debian són <b>clons enllaçats</b> de la instantània <i>base</i> dels templates tpl-debian-server / tpl-debian-desktop (grups VirtualBox /VirtualCorp/Servers, Printers i Desktops).</li>
<li>Tots tenen una sola NIC en mode xarxa interna; cap equip té NAT. Només router0 (mikrotik0) té sortida NAT cap a l'exterior.</li>
<li>pve01 s'instal·la des de la ISO de Proxmox VE 9.2-1 amb answer.toml; té la virtualització anidada activada (--nested-hw-virt on) i l'emmagatzematge ext4 + LVM-thin.</li>
</ul>
</section>
</body></html>
"""

with open(OUT, "w", encoding="utf-8") as f:
    f.write(HTML)
print("escrit", OUT)
