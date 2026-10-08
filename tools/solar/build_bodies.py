"""Catalogue of the named bodies in the solar-system explorer: Sun, planets, big moons, dwarf
planets and famous comets with names, type and a short text (de/en/es), physical data and –
for dwarf planets and comets – orbital elements from the JPL Small-Body Database.
Planet and dwarf-planet texts come from the old Kivy app (astro_mini_games/locales), the
others are written here. Planet orbits are computed in the game (Kepler.PLANETS).
Output: godot/assets/data/solar/bodies.json

    uv run solar/build_bodies.py
"""

import json
from pathlib import Path

import requests
import yaml

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
CACHE = TOOLS / ".cache/solar"
OLD_LOCALES = Path("/home/schedar/projects/astro_mini_games/astro_mini_games/locales")
OUT = REPO / "godot/assets/data/solar/bodies.json"
LANGS = ["de", "en", "es"]

# id: kind, parent, radius km, mass kg, old-locale key, SBDB designation
BODIES = {
    "sun": ("star", "", 696340.0, 1.989e30, None, None),
    "mercury": ("planet", "sun", 2439.7, 3.301e23, "Merkur", None),
    "venus": ("planet", "sun", 6051.8, 4.867e24, "Venus", None),
    "earth": ("planet", "sun", 6371.0, 5.972e24, "Erde", None),
    "mars": ("planet", "sun", 3389.5, 6.417e23, "Mars", None),
    "jupiter": ("planet", "sun", 69911.0, 1.898e27, "Jupiter", None),
    "saturn": ("planet", "sun", 58232.0, 5.683e26, "Saturn", None),
    "uranus": ("planet", "sun", 25362.0, 8.681e25, "Uranus", None),
    "neptune": ("planet", "sun", 24622.0, 1.024e26, "Neptun", None),
    "moon": ("moon", "earth", 1737.4, 7.342e22, None, None),
    "io": ("moon", "jupiter", 1821.6, 8.93e22, None, None),
    "europa": ("moon", "jupiter", 1560.8, 4.80e22, None, None),
    "ganymede": ("moon", "jupiter", 2634.1, 1.48e23, None, None),
    "callisto": ("moon", "jupiter", 2410.3, 1.08e23, None, None),
    "titan": ("moon", "saturn", 2574.7, 1.345e23, None, None),
    "ceres": ("dwarf", "sun", 469.7, 9.38e20, "Ceres", "1"),
    "pluto": ("dwarf", "sun", 1188.3, 1.303e22, "Pluto", "134340"),
    "haumea": ("dwarf", "sun", 780.0, 4.0e21, "Haumea", "136108"),
    "makemake": ("dwarf", "sun", 715.0, 3.1e21, "Makemake", "136472"),
    "eris": ("dwarf", "sun", 1163.0, 1.66e22, "Eris", "136199"),
    "sedna": ("dwarf", "sun", 500.0, None, "Sedna", "90377"),
    "halley": ("comet", "sun", 5.5, 2.2e14, None, "1P"),
    "67p": ("comet", "sun", 1.7, 1.0e13, None, "67P"),
    "halebopp": ("comet", "sun", 30.0, None, None, "C/1995 O1"),
    "encke": ("comet", "sun", 2.4, None, None, "2P"),
}

NAMES = {
    "sun": ("Sonne", "Sun", "Sol"),
    "mercury": ("Merkur", "Mercury", "Mercurio"), "venus": ("Venus", "Venus", "Venus"),
    "earth": ("Erde", "Earth", "Tierra"), "mars": ("Mars", "Mars", "Marte"),
    "jupiter": ("Jupiter", "Jupiter", "Júpiter"), "saturn": ("Saturn", "Saturn", "Saturno"),
    "uranus": ("Uranus", "Uranus", "Urano"), "neptune": ("Neptun", "Neptune", "Neptuno"),
    "moon": ("Mond", "Moon", "Luna"), "io": ("Io", "Io", "Ío"), "europa": ("Europa", "Europa", "Europa"),
    "ganymede": ("Ganymed", "Ganymede", "Ganímedes"), "callisto": ("Kallisto", "Callisto", "Calisto"),
    "titan": ("Titan", "Titan", "Titán"),
    "ceres": ("Ceres", "Ceres", "Ceres"), "pluto": ("Pluto", "Pluto", "Plutón"), "haumea": ("Haumea", "Haumea", "Haumea"),
    "makemake": ("Makemake", "Makemake", "Makemake"), "eris": ("Eris", "Eris", "Eris"), "sedna": ("Sedna", "Sedna", "Sedna"),
    "halley": ("Halleyscher Komet", "Halley's Comet", "cometa Halley"),
    "67p": ("67P/Tschurjumow-Gerassimenko", "67P/Churyumov–Gerasimenko", "67P/Churiumov-Guerasimenko"),
    "halebopp": ("Hale-Bopp", "Hale-Bopp", "Hale-Bopp"),
    "encke": ("Enckescher Komet", "Comet Encke", "cometa Encke"),
}

TYPES = {
    "star": ("Stern", "Star", "Estrella"), "moon": ("Mond", "Moon", "Luna"), "comet": ("Komet", "Comet", "Cometa"),
}

# Texts for bodies the old app did not have.
TEXTS = {
    "sun": ("Unser Stern. In der Sonne stecken 99,8 % der Masse des ganzen Sonnensystems.",
            "Our star. The Sun holds 99.8 % of the mass of the whole solar system.",
            "Nuestra estrella. El Sol contiene el 99,8 % de la masa de todo el sistema solar."),
    "moon": ("Der einzige natürliche Begleiter der Erde. Er zeigt uns immer dieselbe Seite.",
             "Earth's only natural companion. It always shows us the same side.",
             "El único compañero natural de la Tierra. Siempre nos muestra la misma cara."),
    "io": ("Der Jupitermond mit den meisten aktiven Vulkanen im ganzen Sonnensystem.",
           "Jupiter's moon with the most active volcanoes in the whole solar system.",
           "La luna de Júpiter con más volcanes activos de todo el sistema solar."),
    "europa": ("Unter seiner Eiskruste liegt vermutlich ein Ozean aus flüssigem Wasser.",
               "Beneath its icy crust there is probably an ocean of liquid water.",
               "Bajo su corteza de hielo probablemente hay un océano de agua líquida."),
    "ganymede": ("Der größte Mond im Sonnensystem – größer als der Planet Merkur.",
                 "The largest moon in the solar system – bigger than the planet Mercury.",
                 "La luna más grande del sistema solar, mayor que el planeta Mercurio."),
    "callisto": ("Einer der am dichtesten mit Kratern übersäten Himmelskörper überhaupt.",
                 "One of the most heavily cratered bodies of all.",
                 "Uno de los cuerpos con más cráteres de todos."),
    "titan": ("Saturns größter Mond hat eine dichte Atmosphäre und Seen aus flüssigem Methan.",
              "Saturn's largest moon has a thick atmosphere and lakes of liquid methane.",
              "La mayor luna de Saturno tiene una atmósfera densa y lagos de metano líquido."),
    "halley": ("Der berühmteste Komet. Er kehrt etwa alle 76 Jahre zurück – das nächste Mal 2061.",
               "The most famous comet. It returns about every 76 years – next time in 2061.",
               "El cometa más famoso. Vuelve aproximadamente cada 76 años; la próxima vez, en 2061."),
    "67p": ("Die Raumsonde Rosetta hat diesen Kometen umkreist, 2014 landete Philae auf ihm. Die OST hat ihn 2015 fotografiert.",
            "The spacecraft Rosetta orbited this comet, and Philae landed on it in 2014. The OST photographed it in 2015.",
            "La sonda Rosetta orbitó este cometa y Philae aterrizó en él en 2014. El OST lo fotografió en 2015."),
    "halebopp": ("Einer der hellsten Kometen des 20. Jahrhunderts – 1997 monatelang mit bloßem Auge zu sehen.",
                 "One of the brightest comets of the 20th century – visible to the naked eye for months in 1997.",
                 "Uno de los cometas más brillantes del siglo XX, visible a simple vista durante meses en 1997."),
    "encke": ("Hat eine der kürzesten Umlaufzeiten aller Kometen: nur etwa 3,3 Jahre.",
              "Has one of the shortest orbital periods of all comets: only about 3.3 years.",
              "Tiene uno de los periodos orbitales más cortos de todos los cometas: solo unos 3,3 años."),
}


def old_texts() -> dict:
    out = {}
    for lang in LANGS:
        d = yaml.safe_load((OLD_LOCALES / f"{lang}.yaml").read_text())
        out[lang] = d["sonnensystem_info"]["planet"]
    return out


def sbdb_elements(designation: str) -> dict:
    path = CACHE / f"sbdb_body_{designation.replace('/', '_').replace(' ', '_')}.json"
    if path.exists():
        raw = json.loads(path.read_text())
    else:
        r = requests.get("https://ssd-api.jpl.nasa.gov/sbdb.api", params={"sstr": designation}, timeout=60)
        r.raise_for_status()
        raw = r.json()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(raw))
    orbit = raw["orbit"]
    el = {e["name"]: e["value"] for e in orbit["elements"]}
    epoch = float(orbit["epoch"])
    a = float(el["a"]) if el.get("a") else float(el["q"]) / (1.0 - float(el["e"]))
    e = float(el["e"])
    n = float(el["n"]) if el.get("n") else 0.9856076686 / abs(a) ** 1.5
    if el.get("ma") is not None:
        ma = float(el["ma"])
    else:
        ma = n * (epoch - float(el["tp"]))
    return {"a": a, "e": e, "i": float(el["i"]), "node": float(el["om"]), "w": float(el["w"]), "M": ma,
            "n": n, "epoch": epoch}


def main() -> None:
    old = old_texts()
    out = []
    for bid, (kind, parent, radius, mass, old_key, desig) in BODIES.items():
        entry = {"id": bid, "kind": kind, "parent": parent, "radius_km": radius, "mass_kg": mass,
                 "name": dict(zip(LANGS, NAMES[bid]))}
        if old_key:
            entry["type"] = {lang: old[lang][old_key]["type"] for lang in LANGS}
            entry["text"] = {lang: old[lang][old_key]["desc"] for lang in LANGS}
        else:
            entry["type"] = dict(zip(LANGS, TYPES[kind]))
            entry["text"] = dict(zip(LANGS, TEXTS[bid]))
        if desig:
            entry["elements"] = sbdb_elements(desig)
        out.append(entry)
        print(bid, entry["elements"]["a"] if desig else "")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"source": "JPL Small-Body Database; NASA planetary fact sheets", "bodies": out},
                              ensure_ascii=False, indent=1))
    print(len(out), "bodies ->", OUT)


if __name__ == "__main__":
    main()
