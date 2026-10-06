"""Real asteroids used as targets in the asteroid hunt.

Mix of classes (main belt, near-Earth, Jupiter Trojans, Hildas) and a few with a
connection to German observatories or space missions, which makes good fun facts.
Objects that are too faint or badly placed from Golm in the survey period are dropped
automatically by build_scenarios.py.
"""

# (number, short note for us; the in-game facts come from JPL SBDB)
CANDIDATES = [
    (2, "Pallas – discovered by Olbers in Bremen"),
    (3, "Juno – discovered in Lilienthal near Bremen"),
    (5, "Astraea – Hencke, Driesen"),
    (6, "Hebe – Hencke"),
    (7, "Iris"),
    (8, "Flora"),
    (9, "Metis"),
    (11, "Parthenope"),
    (12, "Victoria"),
    (15, "Eunomia"),
    (16, "Psyche – NASA mission target"),
    (18, "Melpomene"),
    (20, "Massalia"),
    (21, "Lutetia – Rosetta flyby"),
    (29, "Amphitrite"),
    (39, "Laetitia"),
    (44, "Nysa"),
    (153, "Hilda – Hilda group"),
    (216, "Kleopatra – dog-bone shape"),
    (243, "Ida – has a moon (Dactyl)"),
    (253, "Mathilde – NEAR flyby"),
    (433, "Eros – first NEO, found in Berlin 1898"),
    (588, "Achilles – first Jupiter Trojan, Heidelberg"),
    (624, "Hektor – largest Trojan, Heidelberg"),
    (887, "Alinda – NEO, Heidelberg"),
    (944, "Hidalgo – comet-like orbit, Baade"),
    (951, "Gaspra – Galileo flyby"),
    (1036, "Ganymed – largest NEO, Baade in Bergedorf"),
    (1620, "Geographos – NEO"),
    (1627, "Ivar – NEO"),
    (1685, "Toro – NEO"),
    (1866, "Sisyphus – NEO"),
    (3122, "Florence – NEO with two moons"),
    (3200, "Phaethon – parent of the Geminids"),
    (4179, "Toutatis – NEO"),
]


# Additional, randomly drawn objects so that every difficulty has enough targets of the
# right brightness (V ~ 13-17 at opposition). Drawn reproducibly from JPL SBDB by
# build_scenarios.py --auto: (class, H range, how many).
AUTO_SAMPLE = [
    ("MBA", 10.5, 12.5, 30),   # main belt, V ~ 14-16
    ("OMB", 10.0, 12.0, 8),    # outer main belt incl. Hildas
    ("TJN", 9.0, 11.0, 8),     # Jupiter Trojans, V ~ 15-16, slow
    ("APO", 14.0, 17.5, 8),    # near-Earth (Apollo)
    ("AMO", 14.0, 17.0, 8),    # near-Earth (Amor)
]
AUTO_SEED = 2026
