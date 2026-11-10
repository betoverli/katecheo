#!/usr/bin/env python3
"""Build src/lib/bible/collections.ts from freely licensed Bible texts.

EN: World English Bible (public domain)
PT: Bíblia Livre (CC BY 3.0 BR)
ES: Versión Biblia Libre (CC BY-SA 4.0)

Snippets are the first few words only — not the full verse.
"""
from __future__ import annotations

import json
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from collection_expand import EXTRA_REFS, NEW_THEMES
CACHE = Path("/tmp/verse2note-bible-cache")
OUT = ROOT / "src/lib/bible/collections.ts"
CACHE.mkdir(parents=True, exist_ok=True)

TRANSLATIONS = {
    "en": "web",
    "pt": "blivre",
    "es": "vbl",
}

VBL_BOOK = {
    "GEN": "GEN", "EXO": "EXO", "LEV": "LEV", "NUM": "NUM", "DEU": "DEU",
    "JOS": "JOS", "JDG": "JDG", "RUT": "RUT", "1SA": "1SA", "2SA": "2SA",
    "1KI": "1KI", "2KI": "2KI", "1CH": "1CH", "2CH": "2CH", "EZR": "EZR",
    "NEH": "NEH", "EST": "EST", "JOB": "JOB", "PSA": "PSA", "PRO": "PRO",
    "ECC": "ECC", "SNG": "SOL", "ISA": "ISA", "JER": "JER", "LAM": "LAM",
    "EZK": "EZE", "DAN": "DAN", "HOS": "HOS", "JOL": "JOE", "AMO": "AMO",
    "OBA": "OBA", "JON": "JON", "MIC": "MIC", "NAM": "NAH", "HAB": "HAB",
    "ZEP": "ZEP", "HAG": "HAG", "ZEC": "ZEC", "MAL": "MAL", "MAT": "MAT",
    "MRK": "MAR", "LUK": "LUK", "JHN": "JOH", "ACT": "ACT", "ROM": "ROM",
    "1CO": "1CO", "2CO": "2CO", "GAL": "GAL", "EPH": "EPH", "PHP": "PHI",
    "COL": "COL", "1TH": "1TH", "2TH": "2TH", "1TI": "1TI", "2TI": "2TI",
    "TIT": "TIT", "PHM": "PHM", "HEB": "HEB", "JAS": "JAM", "1PE": "1PE",
    "2PE": "2PE", "1JN": "1JO", "2JN": "2JO", "3JN": "3JO", "JUD": "JUD",
    "REV": "REV",
}

# id, pt, en, es, list of (bookId, chapter, verseStart, verseEnd|None)
THEMES: list[tuple] = [
    ("salvation", "Salvação", "Salvation", "Salvación", [("JHN", 3, 16, None), ("ROM", 3, 23, None), ("ROM", 5, 8, None), ("ROM", 6, 23, None), ("ROM", 10, 9, 10), ("EPH", 2, 8, 9), ("ACT", 16, 31, None), ("TIT", 3, 5, None)]),
    ("grace", "Graça", "Grace", "Gracia", [("EPH", 2, 8, 9), ("ROM", 3, 24, None), ("2CO", 12, 9, None), ("HEB", 4, 16, None), ("JHN", 1, 16, 17), ("TIT", 2, 11, None)]),
    ("faith", "Fé", "Faith", "Fe", [("HEB", 11, 1, None), ("HEB", 11, 6, None), ("ROM", 10, 17, None), ("2CO", 5, 7, None), ("HAB", 2, 4, None), ("JAS", 2, 17, None), ("MRK", 11, 22, 24)]),
    ("prayer", "Oração", "Prayer", "Oración", [("MAT", 6, 6, 13), ("PHP", 4, 6, 7), ("1TH", 5, 17, None), ("JAS", 5, 16, None), ("JHN", 14, 13, 14), ("JER", 33, 3, None), ("1JN", 5, 14, None)]),
    ("anxiety", "Ansiedade", "Anxiety", "Ansiedad", [("PHP", 4, 6, 7), ("1PE", 5, 7, None), ("MAT", 6, 25, 34), ("ISA", 41, 10, None), ("JHN", 14, 27, None), ("PSA", 55, 22, None)]),
    ("family", "Família", "Family", "Familia", [("JOS", 24, 15, None), ("PRO", 22, 6, None), ("EPH", 5, 25, None), ("EPH", 6, 1, 4), ("COL", 3, 18, 21), ("PSA", 127, 3, None)]),
    ("church", "Igreja", "Church", "Iglesia", [("MAT", 16, 18, None), ("ACT", 2, 42, None), ("HEB", 10, 24, 25), ("EPH", 4, 11, 16), ("1CO", 12, 12, 13), ("COL", 1, 18, None)]),
    ("christmas", "Natal", "Christmas", "Navidad", [("ISA", 9, 6, None), ("MIC", 5, 2, None), ("MAT", 1, 21, 23), ("LUK", 2, 8, 14), ("JHN", 1, 14, None), ("GAL", 4, 4, None)]),
    ("easter", "Páscoa", "Easter", "Pascua", [("ISA", 53, 5, None), ("MAT", 28, 5, 6), ("JHN", 11, 25, 26), ("1CO", 15, 3, 4), ("ROM", 6, 4, None), ("1PE", 1, 3, None)]),
    ("youth", "Jovens", "Youth", "Jóvenes", [("ECC", 12, 1, None), ("PSA", 119, 9, None), ("PRO", 3, 5, 6), ("JER", 29, 11, None), ("1TI", 4, 12, None), ("1JN", 2, 14, None)]),
    ("love", "Amor", "Love", "Amor", [("JHN", 3, 16, None), ("1CO", 13, 4, 7), ("1JN", 4, 7, 8), ("ROM", 5, 8, None), ("JHN", 13, 34, 35), ("MAT", 22, 37, 39)]),
    ("hope", "Esperança", "Hope", "Esperanza", [("ROM", 15, 13, None), ("JER", 29, 11, None), ("HEB", 6, 19, None), ("ROM", 8, 24, 25), ("1PE", 1, 3, None), ("PSA", 42, 11, None)]),
    ("peace", "Paz", "Peace", "Paz", [("JHN", 14, 27, None), ("PHP", 4, 7, None), ("ISA", 26, 3, None), ("ROM", 5, 1, None), ("COL", 3, 15, None), ("NUM", 6, 24, 26)]),
    ("joy", "Alegria", "Joy", "Gozo", [("PSA", 16, 11, None), ("PHP", 4, 4, None), ("NEH", 8, 10, None), ("JHN", 15, 11, None), ("ROM", 15, 13, None), ("1PE", 1, 8, None)]),
    ("forgiveness", "Perdão", "Forgiveness", "Perdón", [("1JN", 1, 9, None), ("EPH", 4, 32, None), ("MAT", 6, 14, 15), ("COL", 3, 13, None), ("PSA", 103, 12, None), ("LUK", 6, 37, None)]),
    ("repentance", "Arrependimento", "Repentance", "Arrepentimiento", [("ACT", 3, 19, None), ("2CO", 7, 10, None), ("LUK", 15, 7, None), ("ISA", 55, 7, None), ("PRO", 28, 13, None), ("ACT", 17, 30, None)]),
    ("holiness", "Santidade", "Holiness", "Santidad", [("1PE", 1, 15, 16), ("HEB", 12, 14, None), ("LEV", 19, 2, None), ("2CO", 7, 1, None), ("ROM", 12, 1, None), ("1TH", 4, 3, None)]),
    ("holy-spirit", "Espírito Santo", "Holy Spirit", "Espíritu Santo", [("JHN", 14, 26, None), ("ACT", 1, 8, None), ("GAL", 5, 22, 23), ("ROM", 8, 26, None), ("EPH", 5, 18, None), ("1CO", 12, 4, 7)]),
    ("baptism", "Batismo", "Baptism", "Bautismo", [("MAT", 28, 19, None), ("ACT", 2, 38, None), ("ROM", 6, 3, 4), ("GAL", 3, 27, None), ("MRK", 16, 16, None), ("1PE", 3, 21, None)]),
    ("lords-supper", "Ceia do Senhor", "Lord's Supper", "Cena del Señor", [("1CO", 11, 23, 26), ("LUK", 22, 19, 20), ("MAT", 26, 26, 28), ("JHN", 6, 53, 56), ("1CO", 10, 16, None)]),
    ("second-coming", "Segunda vinda", "Second coming", "Segunda venida", [("ACT", 1, 11, None), ("1TH", 4, 16, 17), ("MAT", 24, 30, 31), ("REV", 22, 12, None), ("TIT", 2, 13, None), ("JHN", 14, 3, None)]),
    ("creation", "Criação", "Creation", "Creación", [("GEN", 1, 1, None), ("PSA", 19, 1, None), ("JHN", 1, 1, 3), ("COL", 1, 16, None), ("HEB", 11, 3, None), ("ISA", 40, 28, None)]),
    ("wisdom", "Sabedoria", "Wisdom", "Sabiduría", [("PRO", 9, 10, None), ("JAS", 1, 5, None), ("PRO", 3, 5, 7), ("1CO", 1, 30, None), ("COL", 2, 3, None), ("ECC", 12, 13, None)]),
    ("money", "Dinheiro", "Money", "Dinero", [("1TI", 6, 10, None), ("MAT", 6, 24, None), ("HEB", 13, 5, None), ("PRO", 3, 9, None), ("LUK", 12, 15, None), ("MAL", 3, 10, None)]),
    ("work", "Trabalho", "Work", "Trabajo", [("COL", 3, 23, None), ("PRO", 14, 23, None), ("2TH", 3, 10, None), ("ECC", 9, 10, None), ("GEN", 2, 15, None), ("1CO", 15, 58, None)]),
    ("suffering", "Sofrimento", "Suffering", "Sufrimiento", [("ROM", 8, 18, None), ("1PE", 4, 12, 13), ("2CO", 4, 17, None), ("JAS", 1, 2, 4), ("PSA", 34, 19, None), ("JHN", 16, 33, None)]),
    ("healing", "Cura", "Healing", "Sanidad", [("ISA", 53, 5, None), ("JAS", 5, 14, 15), ("PSA", 103, 2, 3), ("MAT", 8, 16, 17), ("1PE", 2, 24, None), ("EXO", 15, 26, None)]),
    ("fear", "Medo", "Fear", "Miedo", [("ISA", 41, 10, None), ("2TI", 1, 7, None), ("PSA", 27, 1, None), ("JOS", 1, 9, None), ("PSA", 23, 4, None), ("1JN", 4, 18, None)]),
    ("temptation", "Tentação", "Temptation", "Tentación", [("1CO", 10, 13, None), ("JAS", 1, 13, 14), ("MAT", 26, 41, None), ("HEB", 2, 18, None), ("1PE", 5, 8, 9), ("PSA", 119, 11, None)]),
    ("humility", "Humildade", "Humility", "Humildad", [("PHP", 2, 3, 8), ("JAS", 4, 6, None), ("MIC", 6, 8, None), ("1PE", 5, 5, 6), ("PRO", 22, 4, None), ("MAT", 23, 12, None)]),
    ("pride", "Orgulho", "Pride", "Orgullo", [("PRO", 16, 18, None), ("JAS", 4, 6, None), ("1PE", 5, 5, None), ("DAN", 4, 37, None), ("PRO", 11, 2, None), ("ISA", 2, 11, None)]),
    ("anger", "Ira", "Anger", "Ira", [("EPH", 4, 26, 27), ("JAS", 1, 19, 20), ("PRO", 15, 1, None), ("PSA", 37, 8, None), ("ECC", 7, 9, None), ("COL", 3, 8, None)]),
    ("patience", "Paciência", "Patience", "Paciencia", [("ROM", 12, 12, None), ("JAS", 5, 7, 8), ("GAL", 5, 22, None), ("PSA", 37, 7, None), ("COL", 1, 11, None), ("ECC", 7, 8, None)]),
    ("kindness", "Bondade", "Kindness", "Bondad", [("EPH", 4, 32, None), ("COL", 3, 12, None), ("PRO", 3, 3, None), ("GAL", 5, 22, None), ("ROM", 2, 4, None), ("MIC", 6, 8, None)]),
    ("service", "Serviço", "Service", "Servicio", [("MRK", 10, 45, None), ("GAL", 5, 13, None), ("1PE", 4, 10, None), ("JHN", 13, 14, 15), ("MAT", 20, 26, 28), ("JOS", 24, 15, None)]),
    ("missions", "Missões", "Missions", "Misiones", [("MAT", 28, 18, 20), ("ACT", 1, 8, None), ("ISA", 6, 8, None), ("ROM", 10, 14, 15), ("PSA", 96, 3, None), ("MRK", 16, 15, None)]),
    ("evangelism", "Evangelismo", "Evangelism", "Evangelismo", [("MRK", 16, 15, None), ("ROM", 1, 16, None), ("1PE", 3, 15, None), ("2CO", 5, 20, None), ("ACT", 4, 12, None), ("MAT", 9, 37, 38)]),
    ("discipleship", "Discipulado", "Discipleship", "Discipulado", [("LUK", 9, 23, None), ("MAT", 28, 19, 20), ("JHN", 8, 31, None), ("2TI", 2, 2, None), ("MAT", 16, 24, None), ("COL", 2, 6, 7)]),
    ("scripture", "Palavra de Deus", "Scripture", "Escritura", [("2TI", 3, 16, 17), ("PSA", 119, 105, None), ("HEB", 4, 12, None), ("JOS", 1, 8, None), ("PSA", 1, 2, None), ("MAT", 4, 4, None)]),
    ("worship", "Adoração", "Worship", "Adoración", [("JHN", 4, 23, 24), ("PSA", 95, 6, None), ("ROM", 12, 1, None), ("PSA", 29, 2, None), ("HEB", 12, 28, None), ("REV", 4, 11, None)]),
    ("thanksgiving", "Gratidão", "Thanksgiving", "Gratitud", [("1TH", 5, 18, None), ("PSA", 100, 4, None), ("COL", 3, 17, None), ("PHP", 4, 6, None), ("PSA", 107, 1, None), ("EPH", 5, 20, None)]),
    ("fasting", "Jejum", "Fasting", "Ayuno", [("MAT", 6, 16, 18), ("ISA", 58, 6, None), ("JOL", 2, 12, None), ("ACT", 13, 2, 3), ("EZR", 8, 23, None), ("LUK", 4, 2, None)]),
    ("marriage", "Casamento", "Marriage", "Matrimonio", [("GEN", 2, 24, None), ("EPH", 5, 25, 33), ("HEB", 13, 4, None), ("MAT", 19, 4, 6), ("1CO", 13, 4, 7), ("PRO", 18, 22, None)]),
    ("children", "Filhos", "Children", "Hijos", [("PRO", 22, 6, None), ("EPH", 6, 1, 4), ("PSA", 127, 3, 5), ("DEU", 6, 6, 7), ("MRK", 10, 14, None), ("COL", 3, 20, 21)]),
    ("friendship", "Amizade", "Friendship", "Amistad", [("PRO", 17, 17, None), ("PRO", 18, 24, None), ("ECC", 4, 9, 10), ("JHN", 15, 13, None), ("1SA", 18, 1, None), ("PRO", 27, 17, None)]),
    ("leadership", "Liderança", "Leadership", "Liderazgo", [("MRK", 10, 42, 45), ("1TI", 3, 1, 2), ("PRO", 11, 14, None), ("JOS", 1, 6, 9), ("1PE", 5, 2, 3), ("EXO", 18, 21, None)]),
    ("justice", "Justiça", "Justice", "Justicia", [("MIC", 6, 8, None), ("AMO", 5, 24, None), ("ISA", 1, 17, None), ("PRO", 21, 3, None), ("PSA", 89, 14, None), ("MAT", 23, 23, None)]),
    ("the-poor", "Os pobres", "The poor", "Los pobres", [("PRO", 19, 17, None), ("MAT", 25, 35, 40), ("JAS", 2, 5, None), ("ISA", 58, 7, None), ("DEU", 15, 11, None), ("LUK", 4, 18, None)]),
    ("covenant", "Aliança", "Covenant", "Pacto", [("GEN", 17, 7, None), ("JER", 31, 31, 33), ("HEB", 8, 6, None), ("LUK", 22, 20, None), ("EXO", 19, 5, None), ("PSA", 89, 34, None)]),
    ("law-and-grace", "Lei e graça", "Law and grace", "Ley y gracia", [("JHN", 1, 17, None), ("ROM", 6, 14, None), ("GAL", 3, 24, 25), ("ROM", 3, 20, 24), ("GAL", 5, 4, None), ("ROM", 8, 1, 2)]),
    ("rest", "Descanso", "Rest", "Descanso", [("MAT", 11, 28, 30), ("HEB", 4, 9, 11), ("EXO", 20, 8, 11), ("PSA", 23, 2, None), ("ISA", 30, 15, None), ("PSA", 62, 1, None)]),
    ("death", "Morte", "Death", "Muerte", [("PSA", 23, 4, None), ("JHN", 11, 25, 26), ("1CO", 15, 54, 57), ("PHP", 1, 21, None), ("ECC", 3, 1, 2), ("REV", 21, 4, None)]),
    ("heaven", "Céu", "Heaven", "Cielo", [("JHN", 14, 2, 3), ("REV", 21, 3, 4), ("PHP", 3, 20, None), ("2CO", 5, 1, None), ("MAT", 6, 20, None), ("1PE", 1, 4, None)]),
    ("hell", "Inferno", "Hell", "Infierno", [("MAT", 25, 46, None), ("REV", 20, 14, 15), ("LUK", 16, 23, 24), ("2TH", 1, 8, 9), ("MAT", 10, 28, None), ("MRK", 9, 43, None)]),
    ("resurrection", "Ressurreição", "Resurrection", "Resurrección", [("1CO", 15, 20, 22), ("JHN", 11, 25, None), ("ROM", 6, 5, None), ("1TH", 4, 14, None), ("DAN", 12, 2, None), ("PHP", 3, 10, 11)]),
    ("identity", "Identidade em Cristo", "Identity in Christ", "Identidad en Cristo", [("2CO", 5, 17, None), ("GAL", 2, 20, None), ("EPH", 2, 10, None), ("1PE", 2, 9, None), ("ROM", 8, 16, 17), ("COL", 3, 3, None)]),
    ("armor", "Armadura de Deus", "Armor of God", "Armadura de Dios", [("EPH", 6, 10, 18), ("2CO", 10, 4, None), ("1TH", 5, 8, None), ("ROM", 13, 12, None), ("ISA", 59, 17, None)]),
    ("fruit", "Fruto do Espírito", "Fruit of the Spirit", "Fruto del Espíritu", [("GAL", 5, 22, 23), ("JHN", 15, 4, 5), ("COL", 1, 10, None), ("MAT", 7, 16, 20), ("EPH", 5, 9, None)]),
    ("gifts", "Dons espirituais", "Spiritual gifts", "Dones espirituales", [("1CO", 12, 4, 11), ("ROM", 12, 6, 8), ("1PE", 4, 10, None), ("EPH", 4, 11, 12), ("1CO", 14, 1, None)]),
    ("unity", "Unidade", "Unity", "Unidad", [("PSA", 133, 1, None), ("EPH", 4, 3, 6), ("JHN", 17, 21, None), ("1CO", 1, 10, None), ("PHP", 2, 2, None), ("COL", 3, 14, None)]),
    ("false-teaching", "Falso ensino", "False teaching", "Falsa enseñanza", [("2TI", 4, 3, 4), ("MAT", 7, 15, None), ("1JN", 4, 1, None), ("GAL", 1, 8, None), ("2PE", 2, 1, None), ("ACT", 20, 29, 30)]),
    ("persecution", "Perseguição", "Persecution", "Persecución", [("2TI", 3, 12, None), ("MAT", 5, 10, 12), ("JHN", 15, 18, 20), ("1PE", 4, 14, None), ("ROM", 8, 35, None), ("ACT", 14, 22, None)]),
    ("courage", "Coragem", "Courage", "Valor", [("JOS", 1, 9, None), ("DEU", 31, 6, None), ("PSA", 27, 14, None), ("1CO", 16, 13, None), ("2TI", 1, 7, None), ("ISA", 41, 13, None)]),
    ("waiting", "Esperar em Deus", "Waiting on God", "Esperar en Dios", [("ISA", 40, 31, None), ("PSA", 27, 14, None), ("LAM", 3, 25, 26), ("PSA", 37, 7, None), ("HAB", 2, 3, None), ("MIC", 7, 7, None)]),
    ("guidance", "Direção", "Guidance", "Guía", [("PRO", 3, 5, 6), ("PSA", 32, 8, None), ("ISA", 30, 21, None), ("JHN", 16, 13, None), ("PSA", 119, 105, None), ("JAS", 1, 5, None)]),
    ("promises", "Promessas", "Promises", "Promesas", [("2CO", 1, 20, None), ("JOS", 21, 45, None), ("2PE", 1, 4, None), ("NUM", 23, 19, None), ("HEB", 10, 23, None), ("ROM", 4, 21, None)]),
    ("the-cross", "A cruz", "The cross", "La cruz", [("1CO", 1, 18, None), ("GAL", 6, 14, None), ("LUK", 9, 23, None), ("ISA", 53, 5, None), ("COL", 2, 14, None), ("PHP", 2, 8, None)]),
    ("blood", "O sangue", "The blood", "La sangre", [("HEB", 9, 22, None), ("1JN", 1, 7, None), ("EPH", 1, 7, None), ("REV", 12, 11, None), ("1PE", 1, 18, 19), ("MAT", 26, 28, None)]),
    ("name-of-jesus", "O nome de Jesus", "The name of Jesus", "El nombre de Jesús", [("PHP", 2, 9, 11), ("ACT", 4, 12, None), ("COL", 3, 17, None), ("JHN", 14, 13, 14), ("PRO", 18, 10, None), ("ACT", 3, 6, None)]),
    ("lordship", "Senhorio de Cristo", "Lordship of Christ", "Señorío de Cristo", [("ROM", 10, 9, None), ("PHP", 2, 11, None), ("COL", 1, 18, None), ("LUK", 6, 46, None), ("ACT", 2, 36, None), ("REV", 19, 16, None)]),
    ("obedience", "Obediência", "Obedience", "Obediencia", [("JHN", 14, 15, None), ("1SA", 15, 22, None), ("JAS", 1, 22, None), ("DEU", 5, 33, None), ("LUK", 11, 28, None), ("1JN", 5, 3, None)]),
    ("faith-and-works", "Fé e obras", "Faith and works", "Fe y obras", [("JAS", 2, 17, 18), ("EPH", 2, 8, 10), ("MAT", 7, 21, None), ("GAL", 5, 6, None), ("TIT", 3, 8, None), ("1JN", 3, 18, None)]),
    ("confession", "Confissão", "Confession", "Confesión", [("1JN", 1, 9, None), ("JAS", 5, 16, None), ("PRO", 28, 13, None), ("PSA", 32, 5, None), ("ROM", 10, 9, 10), ("PSA", 51, 1, 4)]),
    ("new-life", "Nova vida", "New life", "Nueva vida", [("2CO", 5, 17, None), ("ROM", 6, 4, None), ("EPH", 4, 22, 24), ("JHN", 3, 3, None), ("COL", 3, 1, 3), ("TIT", 3, 5, None)]),
    ("light", "Luz", "Light", "Luz", [("JHN", 8, 12, None), ("MAT", 5, 14, 16), ("PSA", 119, 105, None), ("1JN", 1, 5, 7), ("ISA", 9, 2, None), ("EPH", 5, 8, None)]),
    ("truth", "Verdade", "Truth", "Verdad", [("JHN", 8, 32, None), ("JHN", 14, 6, None), ("JHN", 17, 17, None), ("EPH", 4, 15, None), ("PSA", 119, 160, None), ("2TI", 2, 15, None)]),
    ("mercy", "Misericórdia", "Mercy", "Misericordia", [("LAM", 3, 22, 23), ("MIC", 6, 8, None), ("PSA", 103, 8, None), ("MAT", 5, 7, None), ("EPH", 2, 4, 5), ("TIT", 3, 5, None)]),
    ("compassion", "Compaixão", "Compassion", "Compasión", [("COL", 3, 12, None), ("MAT", 9, 36, None), ("PSA", 103, 13, None), ("1PE", 3, 8, None), ("LUK", 10, 33, 37), ("EPH", 4, 32, None)]),
    ("integrity", "Integridade", "Integrity", "Integridad", [("PRO", 10, 9, None), ("PSA", 15, 1, 2), ("PRO", 11, 3, None), ("JOB", 2, 3, None), ("PSA", 25, 21, None), ("2CO", 8, 21, None)]),
    ("speech", "Palavras", "Speech", "Palabras", [("EPH", 4, 29, None), ("PRO", 18, 21, None), ("JAS", 3, 5, 10), ("PRO", 15, 1, None), ("COL", 4, 6, None), ("MAT", 12, 36, None)]),
    ("purity", "Pureza", "Purity", "Pureza", [("MAT", 5, 8, None), ("1TH", 4, 3, 4), ("PSA", 51, 10, None), ("PHP", 4, 8, None), ("1TI", 4, 12, None), ("2TI", 2, 22, None)]),
    ("contentment", "Contentamento", "Contentment", "Contentamiento", [("PHP", 4, 11, 13), ("1TI", 6, 6, 8), ("HEB", 13, 5, None), ("PRO", 30, 8, None), ("PSA", 23, 1, None), ("LUK", 12, 15, None)]),
    ("generosity", "Generosidade", "Generosity", "Generosidad", [("2CO", 9, 6, 7), ("PRO", 11, 24, 25), ("LUK", 6, 38, None), ("ACT", 20, 35, None), ("MAL", 3, 10, None), ("1TI", 6, 18, None)]),
    ("fathers", "Pais", "Fathers", "Padres", [("EPH", 6, 4, None), ("PRO", 20, 7, None), ("PSA", 103, 13, None), ("COL", 3, 21, None), ("DEU", 6, 6, 7), ("PRO", 4, 1, 4)]),
    ("mothers", "Mães", "Mothers", "Madres", [("PRO", 31, 26, 28), ("ISA", 66, 13, None), ("PRO", 1, 8, 9), ("2TI", 1, 5, None), ("PSA", 113, 9, None), ("EXD", 2, 9, None)]),
    ("widows", "Viúvas", "Widows", "Viudas", [("JAS", 1, 27, None), ("1TI", 5, 3, None), ("PSA", 68, 5, None), ("DEU", 10, 18, None), ("ISA", 1, 17, None), ("ACT", 6, 1, None)]),
    ("government", "Autoridades", "Government", "Autoridades", [("ROM", 13, 1, 4), ("1PE", 2, 13, 17), ("1TI", 2, 1, 2), ("PRO", 21, 1, None), ("TIT", 3, 1, None), ("DAN", 2, 21, None)]),
    ("israel", "Israel", "Israel", "Israel", [("GEN", 12, 2, 3), ("ROM", 11, 1, 2), ("PSA", 122, 6, None), ("ISA", 43, 1, None), ("JER", 31, 35, 37), ("ZEC", 2, 8, None)]),
    ("beatitudes", "Bem-aventuranças", "Beatitudes", "Bienaventuranzas", [("MAT", 5, 3, 12), ("LUK", 6, 20, 23), ("PSA", 1, 1, None), ("REV", 1, 3, None)]),
    ("love-god", "Amar a Deus", "Loving God", "Amar a Dios", [("DEU", 6, 4, 5), ("MAT", 22, 37, None), ("JHN", 14, 15, None), ("1JN", 4, 19, None), ("JOS", 22, 5, None), ("PSA", 18, 1, None)]),
    ("love-neighbor", "Amar o próximo", "Loving neighbor", "Amar al prójimo", [("MAT", 22, 39, None), ("LEV", 19, 18, None), ("ROM", 13, 9, 10), ("GAL", 5, 14, None), ("LUK", 10, 27, 37), ("JAS", 2, 8, None)]),
    ("prodigal", "Filho pródigo", "The prodigal son", "El hijo pródigo", [("LUK", 15, 11, 24), ("PSA", 103, 8, 13), ("ISA", 55, 7, None), ("JOL", 2, 13, None)]),
    ("good-shepherd", "Bom Pastor", "Good Shepherd", "Buen Pastor", [("JHN", 10, 11, 14), ("PSA", 23, 1, 4), ("EZE", 34, 11, 12), ("ISA", 40, 11, None), ("1PE", 5, 4, None)]),
    ("bread-of-life", "Pão da vida", "Bread of life", "Pan de vida", [("JHN", 6, 35, None), ("JHN", 6, 48, 51), ("MAT", 4, 4, None), ("DEU", 8, 3, None), ("LUK", 22, 19, None)]),
    ("the-vine", "A videira", "The vine", "La vid", [("JHN", 15, 1, 5), ("JHN", 15, 8, None), ("PSA", 80, 8, None), ("ISA", 5, 1, 2)]),
    ("comfort", "Consolo", "Comfort", "Consuelo", [("2CO", 1, 3, 4), ("PSA", 34, 18, None), ("ISA", 61, 1, 3), ("MAT", 5, 4, None), ("JHN", 14, 16, 18), ("PSA", 23, 4, None)]),
    ("praise", "Louvor", "Praise", "Alabanza", [("PSA", 150, 6, None), ("PSA", 100, 1, 2), ("HEB", 13, 15, None), ("PSA", 34, 1, None), ("ISA", 25, 1, None), ("REV", 5, 12, None)]),
    ("revival", "Avivamento", "Revival", "Avivamiento", [("2CH", 7, 14, None), ("HAB", 3, 2, None), ("PSA", 85, 6, None), ("ISA", 57, 15, None), ("ACT", 3, 19, None), ("JOL", 2, 28, None)]),
    ("freedom", "Liberdade", "Freedom", "Libertad", [("JHN", 8, 36, None), ("GAL", 5, 1, None), ("2CO", 3, 17, None), ("ROM", 8, 1, 2), ("GAL", 5, 13, None), ("ISA", 61, 1, None)]),
    ("grief", "Luto", "Grief", "Duelo", [("PSA", 34, 18, None), ("MAT", 5, 4, None), ("1TH", 4, 13, 14), ("REV", 21, 4, None), ("PSA", 147, 3, None), ("ISA", 53, 4, None)]),
    ("doubt", "Dúvida", "Doubt", "Duda", [("MRK", 9, 24, None), ("JAS", 1, 6, None), ("JHN", 20, 27, 29), ("JUD", 1, 22, None), ("MAT", 14, 31, None), ("PSA", 73, 26, None)]),
    ("calling", "Chamado", "Calling", "Llamado", [("EPH", 4, 1, None), ("2TI", 1, 9, None), ("ROM", 8, 28, None), ("1PE", 2, 9, None), ("ISA", 6, 8, None), ("PHP", 3, 14, None)]),
    ("women", "Mulheres", "Women", "Mujeres", [("PRO", 31, 30, None), ("GAL", 3, 28, None), ("LUK", 8, 1, 3), ("JDG", 4, 4, None), ("ACT", 16, 14, 15), ("ROM", 16, 1, 2)]),
    ("men", "Homens", "Men", "Hombres", [("1CO", 16, 13, None), ("MIC", 6, 8, None), ("JOS", 1, 9, None), ("1TI", 6, 11, None), ("PRO", 20, 7, None), ("EPH", 5, 25, None)]),
    ("end-times", "Fim dos tempos", "End times", "Tiempos finales", [("MAT", 24, 6, 14), ("2TI", 3, 1, 5), ("1TH", 5, 2, 6), ("2PE", 3, 10, None), ("DAN", 12, 4, None), ("REV", 1, 7, None)]),
    ("new-covenant", "Nova aliança", "New covenant", "Nuevo pacto", [("JER", 31, 31, 34), ("HEB", 8, 6, 13), ("LUK", 22, 20, None), ("2CO", 3, 6, None), ("HEB", 9, 15, None)]),
    ("sabbath", "Sábado / descanso", "Sabbath", "Sábado", [("EXO", 20, 8, 11), ("MRK", 2, 27, None), ("ISA", 58, 13, 14), ("HEB", 4, 9, 10), ("GEN", 2, 2, 3)]),
    ("angels", "Anjos", "Angels", "Ángeles", [("PSA", 91, 11, None), ("HEB", 1, 14, None), ("LUK", 2, 13, 14), ("MAT", 18, 10, None), ("PSA", 34, 7, None), ("HEB", 13, 2, None)]),
    ("creation-care", "Cuidado da criação", "Creation care", "Cuidado de la creación", [("GEN", 2, 15, None), ("PSA", 24, 1, None), ("GEN", 1, 28, None), ("COL", 1, 16, 17), ("PSA", 104, 24, None)]),
    ("fast-and-pray", "Vigília", "Watch and pray", "Velad y orad", [("MAT", 26, 41, None), ("COL", 4, 2, None), ("1PE", 5, 8, None), ("LUK", 21, 36, None), ("EPH", 6, 18, None)]),
]

# Fix typo EXD -> EXO if I used EXD
# EZE vs EZK - our books use EZK

BOOK_FIX = {"EXD": "EXO", "EZE": "EZK", "ZCH": "ZEC"}


def load_book_nums() -> dict[str, int]:
    text = (ROOT / "src/lib/bible/books.ts").read_text()
    ids = re.findall(r'"id": "([A-Z0-9]+)"', text)
    nums = [int(n) for n in re.findall(r'"num": (\d+)', text)]
    return dict(zip(ids, nums, strict=False))


def fetch_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "Katecheo/1.0"})
    with urllib.request.urlopen(req, timeout=60) as res:
        return res.read()


def fetch_json(url: str) -> dict:
    return json.loads(fetch_bytes(url).decode("utf-8"))


def ensure_file(url: str, dest: Path) -> Path:
    if dest.exists() and dest.stat().st_size > 1000:
        return dest
    dest.write_bytes(fetch_bytes(url))
    return dest


def chapter_verses_web(book_num: int, chapter: int) -> dict[int, str]:
    path = CACHE / f"web-{book_num}-{chapter}.json"
    if path.exists():
        data = json.loads(path.read_text())
    else:
        url = f"https://api.getbible.net/v2/web/{book_num}/{chapter}.json"
        for attempt in range(4):
            try:
                data = fetch_json(url)
                path.write_text(json.dumps(data, ensure_ascii=False))
                break
            except Exception as exc:  # noqa: BLE001
                if attempt == 3:
                    raise RuntimeError(f"{url}: {exc}") from exc
                time.sleep(0.4 * (attempt + 1))
        time.sleep(0.03)
    out: dict[int, str] = {}
    for verse in data.get("verses") or []:
        out[int(verse["verse"])] = verse.get("text") or ""
    return out


def load_blivre(nums: dict[str, int]) -> dict[tuple[str, int], dict[int, str]]:
    path = ensure_file(
        "https://raw.githubusercontent.com/Everson33rj/bibialivrejson/main/biblialivre.json",
        CACHE / "biblialivre.json",
    )
    data = json.loads(path.read_text())
    by_num = {int(item["id"]): item for item in data if isinstance(item, dict) and str(item.get("id", "")).isdigit()}
    out: dict[tuple[str, int], dict[int, str]] = {}
    for book_id, num in nums.items():
        item = by_num.get(num)
        if not item:
            continue
        for ch_i, verses in enumerate(item.get("capitulos") or [], start=1):
            out[(book_id, ch_i)] = {i + 1: (v or "") for i, v in enumerate(verses)}
    return out


def load_vbl() -> dict[tuple[str, str, int], dict[int, str]]:
    zip_path = ensure_file(
        "https://ebible.org/Scriptures/spavbl_vpl.zip",
        CACHE / "spavbl_vpl.zip",
    )
    import zipfile

    with zipfile.ZipFile(zip_path) as zf:
        text = zf.read("spavbl_vpl.txt").decode("utf-8")
    code_to_ours = {code: book for book, code in VBL_BOOK.items()}
    out: dict[tuple[str, int], dict[int, str]] = {}
    for line in text.splitlines():
        m = re.match(r"^([A-Z0-9]+)\s+(\d+):(\d+)\s+(.*)$", line)
        if not m:
            continue
        code, ch, vs, body = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
        book = code_to_ours.get(code)
        if not book:
            continue
        out.setdefault((book, ch), {})[vs] = body
    return out


def snippet(text: str, max_words: int = 10) -> str:
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\[[^\]]*\]", " ", text)
    text = text.replace("\xa0", " ")
    text = re.sub(r"\s+", " ", text).strip(" \t\n\r-–—“”\"'«»")
    words = text.split()
    if not words:
        return ""
    if len(words) <= max_words:
        return " ".join(words)
    return " ".join(words[:max_words]) + "…"


def ts_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def main() -> None:
    nums = load_book_nums()
    needed: set[tuple[str, int]] = set()
    themes = []
    for cid, pt, en, es, refs in THEMES + NEW_THEMES:
        clean = []
        seen: set[tuple] = set()
        for book, ch, vs, ve in list(refs) + EXTRA_REFS.get(cid, []):
            book = BOOK_FIX.get(book, book)
            key = (book, ch, vs, ve)
            if key in seen:
                continue
            seen.add(key)
            if book not in nums:
                raise SystemExit(f"unknown book {book} in {cid}")
            needed.add((book, ch))
            clean.append((book, ch, vs, ve))
        themes.append((cid, pt, en, es, clean))

    print(f"{len(themes)} themes, {len(needed)} unique chapters")
    print("loading Bíblia Livre…")
    blivre = load_blivre(nums)
    print("loading Versión Biblia Libre…")
    vbl = load_vbl()
    print("loading WEB chapters…")
    web: dict[tuple[str, int], dict[int, str]] = {}
    for book, ch in sorted(needed):
        web[(book, ch)] = chapter_verses_web(nums[book], ch)

    sources = {"pt": blivre, "en": web, "es": vbl}

    missing = 0
    blocks = []
    for cid, pt, en, es, refs in themes:
        lines = [
            "  {",
            f'    id: "{cid}",',
            f'    names: {{ pt: "{ts_escape(pt)}", en: "{ts_escape(en)}", es: "{ts_escape(es)}" }},',
            "    passages: [",
        ]
        for book, ch, vs, ve in refs:
            snips = {}
            for loc in ("pt", "en", "es"):
                raw = sources[loc].get((book, ch), {}).get(vs, "")
                cut = snippet(raw)
                if not cut:
                    missing += 1
                    print(f"missing {loc} {book} {ch}:{vs}")
                snips[loc] = cut
            ve_js = "null" if ve is None else str(ve)
            lines.append(
                "      {"
                f' bookId: "{book}", chapter: {ch}, verseStart: {vs}, verseEnd: {ve_js},'
                f' snippet: {{ pt: "{ts_escape(snips["pt"])}", en: "{ts_escape(snips["en"])}", es: "{ts_escape(snips["es"])}" }}'
                " },"
            )
        lines.append("    ],")
        lines.append("  },")
        blocks.append("\n".join(lines))

    header = '''import type { Locale } from "./books";
import { bookById } from "./books";
import { formatPassage, type Passage } from "./passage";

export type CollectionPassage = Passage & {
  snippet: Record<Locale, string>;
};

export type Collection = {
  id: string;
  names: Record<Locale, string>;
  passages: CollectionPassage[];
};

/** First words only. Full verse text is not stored. */
export const SNIPPET_SOURCES: Record<Locale, string> = {
  pt: "Bíblia Livre (CC BY 3.0)",
  en: "World English Bible (public domain)",
  es: "Versión Biblia Libre (CC BY-SA 4.0)",
};

export const COLLECTIONS: Collection[] = [
'''
    footer = '''];

export function collectionById(id: string): Collection | undefined {
  return COLLECTIONS.find((item) => item.id === id);
}

export function searchCollections(query: string, locale: Locale): Collection[] {
  const q = fold(query);
  const list = !q ? COLLECTIONS : COLLECTIONS.filter((item) => haystack(item, locale).includes(q));
  return sortCollections(list, locale);
}

export function sortCollections(items: Collection[], locale: Locale): Collection[] {
  const collator = new Intl.Collator(locale === "pt" ? "pt" : locale === "es" ? "es" : "en", {
    sensitivity: "base",
  });
  return [...items].sort((a, b) => collator.compare(a.names[locale], b.names[locale]));
}

function fold(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\\p{M}/gu, "")
    .toLowerCase()
    .trim();
}

function haystack(item: Collection, locale: Locale): string {
  const parts = [item.names.pt, item.names.en, item.names.es, item.id.replaceAll("-", " ")];
  for (const passage of item.passages) {
    const book = bookById(passage.bookId);
    parts.push(passage.bookId, passage.snippet.pt, passage.snippet.en, passage.snippet.es);
    if (book) {
      parts.push(book.names.pt, book.names.en, book.names.es, book.abbr.pt, book.abbr.en, book.abbr.es);
      parts.push(formatPassage(book, passage, locale));
    }
  }
  return fold(parts.join(" "));
}
'''
    OUT.write_text(header + "\n".join(blocks) + "\n" + footer)
    print(f"wrote {OUT} missing={missing} bytes={OUT.stat().st_size}")


if __name__ == "__main__":
    main()
