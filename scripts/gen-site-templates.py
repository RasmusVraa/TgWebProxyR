#!/usr/bin/env python3
"""Generate site/templates/* — run from repo root."""
from __future__ import annotations

import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "site" / "templates"

TEMPLATES = [
    dict(
        id="northwind",
        brand="Northwind Field Notes",
        kicker="Harbour · Tide · Route",
        h1="Notes from the outer piers",
        lede=(
            "Independent observations on coastal freight, weather windows, "
            "and the small rituals that keep a harbour honest."
        ),
        cards=[
            (
                "Morning survey",
                "Before the cranes wake, walk the north breakwater. Count the buoys. Write what the fog keeps.",
            ),
            (
                "Ledger of delays",
                "Every late ship has a story. We keep short ones: wind, paperwork, a missing hatch key.",
            ),
            (
                "Quiet tools",
                "Paper charts still matter when radios go soft. So do thermos flasks and clean boots.",
            ),
        ],
        about="A compact public face for coastal operators — replace the copy with something that is genuinely yours.",
        notfound="That page drifted out with the tide.",
        css="""
:root { --ink:#152028; --muted:#5c6b75; --paper:#f3efe6; --card:#fffaf1; --line:#d7cfc0; --accent:#1f6f78; --accent2:#134e56; --wash:#d9ebe8; }
html,body{background:radial-gradient(1200px 500px at 10% -10%,var(--wash) 0%,transparent 55%),linear-gradient(180deg,#f7f3ea 0%,var(--paper) 40%,#ebe4d6 100%);color:var(--ink);font-family:"Iowan Old Style","Palatino Linotype",Palatino,Georgia,serif;}
.kicker{color:var(--accent);} a{color:var(--accent2);} a:hover{color:var(--accent);}
.card{background:var(--card);border:1px solid var(--line);}
""",
        fav_bg="#134e56",
        fav_fg="#f3efe6",
        fav_dot="#e4d7c0",
        fav_path="M10 40c8-12 16-18 22-18s14 6 22 18",
    ),
    dict(
        id="atelier",
        brand="Atelier Lane Studio",
        kicker="Wood · Thread · Light",
        h1="A small workshop on Lane Street",
        lede=(
            "Hand tools, unfinished sketches, and the smell of cut cedar. "
            "We document the quiet craft that leaves the door open."
        ),
        cards=[
            (
                "Bench notes",
                "Measure twice. Sand once more than you planned. Leave the window cracked for the dust to leave.",
            ),
            (
                "Material list",
                "Oak scraps, beeswax, linen cord. Nothing exotic — just things that age without apology.",
            ),
            ("Visiting hours", "Afternoons only. Bring a question, not a rush. Tea is usually on."),
        ],
        about="Atelier Lane is a placeholder studio page for a single hostname. Swap in your craft, photos, and hours.",
        notfound="This shelf is empty.",
        css="""
:root { --ink:#2a2118; --muted:#7a6a58; --paper:#f6f0e8; --card:#fff8ef; --line:#e2d3c0; --accent:#a65d3f; --accent2:#6e3b28; --wash:#f0e0d0; }
html,body{background:linear-gradient(165deg,#faf6f0 0%,var(--paper) 50%,#efe6da 100%);color:var(--ink);font-family:"Source Serif 4",Georgia,"Times New Roman",serif;}
.kicker{color:var(--accent);} a{color:var(--accent2);} a:hover{color:var(--accent);}
.hero{border-bottom:2px solid var(--line);} .card{background:var(--card);border:1px solid var(--line);box-shadow:4px 4px 0 var(--wash);}
""",
        fav_bg="#6e3b28",
        fav_fg="#f6f0e8",
        fav_dot="#a65d3f",
        fav_path="M18 44 V20 h8 v10 h12 V20 h8 v24",
    ),
    dict(
        id="alpine",
        brand="Ridge Line Almanac",
        kicker="Trail · Elevation · Weather",
        h1="Field notes from the switchbacks",
        lede=(
            "Short reports on passes, snow bridges, and the hours when the wind turns polite. "
            "Pack light, write lighter."
        ),
        cards=[
            (
                "Pass conditions",
                "Cornices soft after noon. Prefer the west approach until melt settles.",
            ),
            (
                "Hut etiquette",
                "Boots by the door. Share the stove. Leave the logbook better than you found it.",
            ),
            (
                "Gear that stays",
                "A map that folds small, a headlamp with spare cells, patience for cloud.",
            ),
        ],
        about="Ridge Line Almanac is a static trail journal face. Replace routes and seasons with your own range.",
        notfound="That trail marker is missing.",
        css="""
:root { --ink:#1a2a24; --muted:#5a7168; --paper:#eef5f1; --card:#ffffff; --line:#c5d6cc; --accent:#2f7d5b; --accent2:#1e5a40; --wash:#cfe8dc; }
html,body{background:linear-gradient(180deg,#e3f0ea 0%,var(--paper) 45%,#d9e8e0 100%);color:var(--ink);font-family:ui-sans-serif,system-ui,"Segoe UI",sans-serif;}
.kicker{color:var(--accent);letter-spacing:.18em;} h1{letter-spacing:-.02em;}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;}
a{color:var(--accent2);} a:hover{color:var(--accent);}
""",
        fav_bg="#1e5a40",
        fav_fg="#eef5f1",
        fav_dot="#2f7d5b",
        fav_path="M12 48 L32 14 L52 48 Z",
    ),
    dict(
        id="metro",
        brand="Gridline Dispatch",
        kicker="Transit · Timetable · City",
        h1="Notes between stations",
        lede=(
            "A plain public board for line changes, weekend works, "
            "and the small delays that reshape a commute."
        ),
        cards=[
            (
                "Weekend works",
                "Platform 3 closed Sat 02:00–06:00. Shuttle on the north exit.",
            ),
            (
                "Signal quiet",
                "When boards freeze, listen for the guard. Paper still beats a blank screen.",
            ),
            (
                "Transfer map",
                "Two minutes is enough if you walk like you mean it. Four if you do not.",
            ),
        ],
        about="Gridline Dispatch is a municipal-style static page. Put your own city voice here.",
        notfound="No service to this stop.",
        css="""
:root { --ink:#111827; --muted:#6b7280; --paper:#f3f4f6; --card:#ffffff; --line:#e5e7eb; --accent:#2563eb; --accent2:#1d4ed8; --wash:#dbeafe; }
html,body{background:var(--paper);color:var(--ink);font-family:"IBM Plex Sans","Helvetica Neue",Arial,sans-serif;}
.top{border-bottom:3px solid var(--ink);padding-bottom:1rem;}
.brand{font-family:ui-monospace,Menlo,Consolas,monospace;text-transform:uppercase;letter-spacing:.08em;font-size:.95rem;}
.kicker{color:var(--accent);font-family:ui-monospace,Menlo,monospace;}
.card{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--accent);}
a{color:var(--accent2);}
""",
        fav_bg="#111827",
        fav_fg="#f3f4f6",
        fav_dot="#2563eb",
        fav_path="M16 16 h32 v8 H16 z M16 28 h20 v8 H16 z M16 40 h28 v8 H16 z",
    ),
    dict(
        id="orchard",
        brand="Greenrow Press",
        kicker="Season · Basket · Table",
        h1="From the rows behind the shed",
        lede=(
            "A soft public noticeboard for pick lists, jam days, "
            "and the weeks when the orchard smells like rain and sugar."
        ),
        cards=[
            (
                "This week",
                "Early pears ready. Leave the baskets by the gate if you are walking the loop.",
            ),
            (
                "Kitchen hours",
                "Saturdays for preserves. Bring jars that already know your shelves.",
            ),
            ("Weather note", "Frost watch after clear nights. Cover the young beds."),
        ],
        about="Greenrow Press stands in for a small food or farm site. Make the harvest yours.",
        notfound="That basket went home.",
        css="""
:root { --ink:#2f3a2a; --muted:#6f7d66; --paper:#f7faf4; --card:#ffffff; --line:#d5e0cb; --accent:#6a9a45; --accent2:#4d7532; --wash:#e4f0d8; }
html,body{background:radial-gradient(900px 420px at 90% 0%,var(--wash),transparent 60%),linear-gradient(180deg,#fbfdf8,var(--paper));color:var(--ink);font-family:"Fraunces",Georgia,serif;}
.kicker{color:var(--accent2);} .card{background:var(--card);border:1px solid var(--line);border-radius:18px;}
a{color:var(--accent2);} a:hover{color:var(--accent);}
""",
        fav_bg="#4d7532",
        fav_fg="#f7faf4",
        fav_dot="#c4e09a",
        fav_path="M32 12 c10 8 14 18 14 28 a14 14 0 1 1 -28 0 c0-10 4-20 14-28",
    ),
    dict(
        id="signal",
        brand="Beacon Range Club",
        kicker="HF · Net · Log",
        h1="Club log for the evening net",
        lede=(
            "Call signs, quiet hours, and antenna notes for operators "
            "who still keep a paper log beside the radio."
        ),
        cards=[
            (
                "Net schedule",
                "Wed 20:00 local. Check-ins on the posted frequency. Guests welcome with a short intro.",
            ),
            (
                "Antenna farm",
                "Dipole on the north mast. Spare coax labeled. Do not move the ground stake.",
            ),
            (
                "QSL desk",
                "Cards in the blue box. Stamp your own. Leave the ink pot closed.",
            ),
        ],
        about="Beacon Range Club is a ham-club style face. Swap frequencies and call signs for your group.",
        notfound="No copy of that QSO.",
        css="""
:root { --ink:#d7e0ea; --muted:#8fa0b3; --paper:#0f1720; --card:#182230; --line:#2a3a4c; --accent:#3ecfbf; --accent2:#2aa89a; --wash:#123038; }
html,body{background:radial-gradient(1000px 500px at 0% 0%,var(--wash),transparent 50%),linear-gradient(180deg,#0b1219,var(--paper));color:var(--ink);font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;}
.kicker{color:var(--accent);} a{color:var(--accent);} a:hover{color:#7aefe3;}
.top{border-bottom:1px solid var(--line);} .card{background:var(--card);border:1px solid var(--line);}
footer{color:var(--muted);}
""",
        fav_bg="#0f1720",
        fav_fg="#3ecfbf",
        fav_dot="#3ecfbf",
        fav_path="M32 10 v28 M20 28 l12 16 12-16",
    ),
    dict(
        id="library",
        brand="Cedar Branch Library",
        kicker="Open · Quiet · Borrow",
        h1="A small branch with open shelves",
        lede="Reading hours, returned stacks, and the soft noticeboard that lives beside the front desk.",
        cards=[
            (
                "Hours",
                "Tue–Sat 10:00–18:00. Story time Wed at 16:00 in the children’s alcove.",
            ),
            (
                "New arrivals",
                "Local history shelf restocked. Ask at the desk for the interloan form.",
            ),
            (
                "Quiet rooms",
                "Two study carrels. Headphones welcome. Phones on the porch.",
            ),
        ],
        about="Cedar Branch Library is a civic-looking static site. Replace hours and policies with your own.",
        notfound="That volume is checked out.",
        css="""
:root { --ink:#1e293b; --muted:#64748b; --paper:#f8fafc; --card:#ffffff; --line:#cbd5e1; --accent:#1e40af; --accent2:#1e3a8a; --wash:#e2e8f0; }
html,body{background:linear-gradient(180deg,#eef2ff 0%,var(--paper) 35%,#f1f5f9 100%);color:var(--ink);font-family:"Literata",Georgia,"Times New Roman",serif;}
.brand{font-weight:700;color:var(--accent2);} .kicker{color:var(--accent);font-family:ui-sans-serif,system-ui,sans-serif;}
.card{background:var(--card);border:1px solid var(--line);box-shadow:0 1px 0 var(--wash);}
a{color:var(--accent);} a:hover{color:var(--accent2);}
""",
        fav_bg="#1e3a8a",
        fav_fg="#f8fafc",
        fav_dot="#93c5fd",
        fav_path="M14 14 h36 v36 H14 z M20 22 h24 M20 30 h24 M20 38 h16",
    ),
    dict(
        id="kiln",
        brand="Clayroom Bulletin",
        kicker="Bisque · Glaze · Fire",
        h1="Studio board by the kiln door",
        lede="Firing schedules, glaze tests, and the notes people leave when clay is still cooling.",
        cards=[
            (
                "Next firing",
                "Cone 6 on Thursday night. Shelves labeled A–C. No wet pots.",
            ),
            (
                "Glaze tests",
                "New ash celadon on tile rack 2. Write your mix if you alter it.",
            ),
            (
                "Cleanup",
                "Wheels wiped. Slip buckets sealed. Floor swept before you leave.",
            ),
        ],
        about="Clayroom Bulletin is a ceramics-studio stand-in. Put your kiln and class schedule here.",
        notfound="That shelf cooled empty.",
        css="""
:root { --ink:#3b2a22; --muted:#8a6f60; --paper:#f4ebe3; --card:#fff7f0; --line:#e0cfc2; --accent:#c45c26; --accent2:#8f3f16; --wash:#edd9c8; }
html,body{background:linear-gradient(135deg,#f8efe6,#f4ebe3 40%,#eadfd4);color:var(--ink);font-family:"Newsreader",Georgia,serif;}
.kicker{color:var(--accent);} .card{background:var(--card);border:1px solid var(--line);border-radius:8px;}
a{color:var(--accent2);} a:hover{color:var(--accent);}
""",
        fav_bg="#8f3f16",
        fav_fg="#f4ebe3",
        fav_dot="#c45c26",
        fav_path="M20 44 h24 l-4-22 h-16 z M28 18 h8 v6 h-8 z",
    ),
    dict(
        id="reef",
        brand="Tidepool Observer",
        kicker="Low tide · Species · Sketch",
        h1="Sketches from the rock pools",
        lede=(
            "A light public log of anemones, crabs, and the hours "
            "when the water pulls back far enough to see."
        ),
        cards=[
            (
                "Today’s pool",
                "East ledge clear at 07:40. Hermit crabs busy. Do not turn rocks over.",
            ),
            (
                "ID corner",
                "New nudibranch photo on the cork board. Labels welcome.",
            ),
            (
                "Tide table",
                "Lowest of the week Friday. Bring soft shoes and leave shells where they are.",
            ),
        ],
        about="Tidepool Observer is a nature-journal face. Replace pools and species with your coast.",
        notfound="The tide took that page.",
        css="""
:root { --ink:#12353f; --muted:#4f7380; --paper:#eef8fa; --card:#ffffff; --line:#b9d8e0; --accent:#0e8a9a; --accent2:#0a6572; --wash:#c5ebf2; }
html,body{background:radial-gradient(800px 400px at 20% 0%,var(--wash),transparent 55%),linear-gradient(180deg,#e6f6f9,var(--paper));color:var(--ink);font-family:"Nunito",ui-sans-serif,system-ui,sans-serif;}
.kicker{color:var(--accent);} .card{background:var(--card);border:1px solid var(--line);border-radius:16px;}
a{color:var(--accent2);} a:hover{color:var(--accent);}
""",
        fav_bg="#0a6572",
        fav_fg="#eef8fa",
        fav_dot="#7dd3e0",
        fav_path="M12 36c8-16 20-22 20-22s12 6 20 22c-8 10-14 14-20 14s-12-4-20-14z",
    ),
    dict(
        id="foundry",
        brand="Typecase Works",
        kicker="Punch · Matrix · Proof",
        h1="Proofs from the back room",
        lede="Specimen sheets, press calendars, and the smell of ink that still means a working shop.",
        cards=[
            (
                "Press calendar",
                "Cylinder free Mon–Wed. Book the Heidelberg with a note on the door.",
            ),
            (
                "Specimen rack",
                "New grotesques on shelf B. Do not mix cases without asking.",
            ),
            (
                "Proof desk",
                "Leave sheets under the weight. Sign the log if you take a pull.",
            ),
        ],
        about="Typecase Works is a print-shop style page. Set your own shop rules and hours.",
        notfound="That form is out of sorts.",
        css="""
:root { --ink:#111111; --muted:#555555; --paper:#f5f5f0; --card:#ffffff; --line:#ccccc4; --accent:#c4a000; --accent2:#111111; --wash:#e8e8e0; }
html,body{background:repeating-linear-gradient(0deg,transparent,transparent 23px,rgba(0,0,0,.03) 24px),var(--paper);color:var(--ink);font-family:"Courier New",Courier,ui-monospace,monospace;}
.brand{text-transform:uppercase;letter-spacing:.12em;font-size:.9rem;}
.kicker{color:#111;background:var(--accent);display:inline-block;padding:.15rem .45rem;font-size:.7rem;}
.card{background:var(--card);border:2px solid var(--ink);} h1{text-transform:uppercase;letter-spacing:.04em;}
a{color:var(--ink);text-decoration:underline;} a:hover{background:var(--accent);}
""",
        fav_bg="#111111",
        fav_fg="#c4a000",
        fav_dot="#c4a000",
        fav_path="M18 18 h28 v8 H18 z M18 30 h28 v16 H18 z",
    ),
]

BASE_CSS = """
* { box-sizing: border-box; }
html, body { margin:0; padding:0; line-height:1.55; min-height:100%; }
a { text-decoration-thickness:1px; text-underline-offset:3px; }
.top { display:flex; justify-content:space-between; align-items:baseline; gap:1rem; max-width:980px; margin:0 auto; padding:1.4rem 1.25rem .5rem; }
.brand { font-weight:700; text-decoration:none; }
nav a { margin-left:1rem; font-size:.95rem; color:var(--muted); text-decoration:none; }
nav a:hover { color:var(--accent); }
main { max-width:980px; margin:0 auto; padding:1rem 1.25rem 3rem; }
.narrow { max-width:640px; }
.hero { padding:2.2rem 0 1.5rem; border-bottom:1px solid var(--line); margin-bottom:1.75rem; }
.kicker { text-transform:uppercase; letter-spacing:.14em; font-size:.75rem; margin:0 0 .75rem; }
h1 { font-size:clamp(1.9rem,4vw,2.9rem); line-height:1.15; margin:0 0 1rem; font-weight:700; }
.lede { font-size:1.12rem; color:var(--muted); max-width:40rem; margin:0; }
.grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:1rem; }
.card { padding:1.1rem 1.15rem; }
.card h2 { font-size:1.05rem; margin:0 0 .5rem; }
.card p { margin:0; color:var(--muted); font-size:.98rem; }
footer { max-width:980px; margin:0 auto; padding:0 1.25rem 2.5rem; color:var(--muted); font-size:.9rem; }
.mono { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; font-size:.92em; }
@media (max-width:640px){ .top{flex-direction:column; align-items:flex-start;} nav a{margin-left:0; margin-right:1rem;} }
"""


def page(brand: str, title: str, body_main: str, extra_head: str = "") -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  {extra_head}
  <link rel="stylesheet" href="/styles.css">
  <link rel="icon" href="/favicon.svg" type="image/svg+xml">
</head>
<body>
  <header class="top">
    <a class="brand" href="/">{brand}</a>
    <nav>
      <a href="/about">About</a>
      <a href="/privacy">Privacy</a>
    </nav>
  </header>
{body_main}
</body>
</html>
"""


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    ids: list[str] = []
    for t in TEMPLATES:
        d = ROOT / t["id"]
        d.mkdir(parents=True, exist_ok=True)
        cards_html = "\n".join(
            f'      <article class="card">\n        <h2>{h}</h2>\n        <p>{p}</p>\n      </article>'
            for h, p in t["cards"]
        )
        index_main = f"""  <main>
    <section class="hero">
      <p class="kicker">{t['kicker']}</p>
      <h1>{t['h1']}</h1>
      <p class="lede">{t['lede']}</p>
    </section>
    <section class="grid">
{cards_html}
    </section>
  </main>
  <footer>
    <p>© {t['brand']} · <span class="mono">__HOSTNAME__</span></p>
  </footer>"""
        desc = t["lede"][:120].replace('"', "&quot;")
        (d / "index.html").write_text(
            page(t["brand"], t["brand"], index_main, f'<meta name="description" content="{desc}">'),
            encoding="utf-8",
        )
        about_main = f"""  <main class="narrow">
    <h1>About</h1>
    <p>{t['about']}</p>
    <p>No third-party analytics. No frames. No forms. Static files served beside the private bridge channel.</p>
  </main>
  <footer>
    <p>© {t['brand']} · <span class="mono">__HOSTNAME__</span></p>
  </footer>"""
        (d / "about.html").write_text(
            page(t["brand"], f"About · {t['brand']}", about_main), encoding="utf-8"
        )
        privacy_main = f"""  <main class="narrow">
    <h1>Privacy</h1>
    <p>This public website does not collect accounts, tracking cookies, or third-party beacons. Server access logs, if enabled by the operator, may retain standard connection metadata for security and capacity planning.</p>
    <p>Contact the operator of <span class="mono">__HOSTNAME__</span> for questions about retention on this host.</p>
  </main>
  <footer>
    <p>© {t['brand']} · <span class="mono">__HOSTNAME__</span></p>
  </footer>"""
        (d / "privacy.html").write_text(
            page(t["brand"], f"Privacy · {t['brand']}", privacy_main), encoding="utf-8"
        )
        nf_main = f"""  <main class="narrow">
    <h1>404</h1>
    <p>{t['notfound']} <a href="/">Back home.</a></p>
  </main>"""
        (d / "404.html").write_text(
            page(t["brand"], f"Not found · {t['brand']}", nf_main), encoding="utf-8"
        )
        (d / "styles.css").write_text(
            BASE_CSS + "\n" + textwrap.dedent(t["css"]).strip() + "\n", encoding="utf-8"
        )
        (d / "robots.txt").write_text("User-agent: *\nAllow: /\n", encoding="utf-8")
        (d / "favicon.svg").write_text(
            f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-label="{t['brand']}">
  <rect width="64" height="64" rx="8" fill="{t['fav_bg']}"/>
  <path d="{t['fav_path']}" fill="none" stroke="{t['fav_fg']}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="32" cy="14" r="3" fill="{t['fav_dot']}"/>
</svg>
""",
            encoding="utf-8",
        )
        ids.append(t["id"])
        print("wrote", t["id"])
    (ROOT / "MANIFEST").write_text("\n".join(ids) + "\n", encoding="utf-8")
    print("done", len(ids))


if __name__ == "__main__":
    main()
