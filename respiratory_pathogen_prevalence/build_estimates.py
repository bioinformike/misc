#!/usr/bin/env python3
"""Build the pathogen-share estimates used by index.html.

Model
-----
For each tract (upper / lower), every pathogen has a BASELINE share of
etiologically attributed illnesses in a typical pre-pandemic year
(2015-2019 average). Each calendar year, that baseline is multiplied by an
ACTIVITY index (1.0 = typical year) taken from surveillance trends. Influenza
and SARS-CoV-2 are instead driven by CDC's illness-burden estimates (millions
of symptomatic illnesses), converted to the same units. The resulting values
are normalised so every tract-year sums to exactly 100.0%.

2026 covers January-September only: indices for 2026 are Jan-Sep activity
relative to a full typical year, so seasonal pathogens whose peak falls in
Oct-Dec (RSV, seasonal coronaviruses) carry less weight that year.

Outputs
-------
  estimates.csv   long-format table: year, tract, pathogen, share_pct, est_illnesses
  calculations.csv  every input, intermediate value, formula and source per value
  index.html      the block between DATA:START / DATA:END markers is rewritten

Usage:  python3 build_estimates.py
"""

import csv
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
YEARS = list(range(2015, 2027))

# ---------------------------------------------------------------------------
# Pathogens: id, display name, type, scientific/qualifier note
# ---------------------------------------------------------------------------
PATHOGENS = [
    # Viruses
    ("rhino",   "Rhinovirus / enterovirus",     "virus",    "Rhinovirus A-C, EV-D68 and other enteroviruses"),
    ("fluA",    "Influenza A",                  "virus",    "H1N1pdm09 and H3N2"),
    ("fluB",    "Influenza B",                  "virus",    "Victoria lineage (Yamagata not detected since 2020)"),
    ("sars2",   "SARS-CoV-2",                   "virus",    "COVID-19, from 2020"),
    ("rsv",     "RSV",                          "virus",    "Respiratory syncytial virus A and B"),
    ("hmpv",    "Human metapneumovirus",        "virus",    "hMPV"),
    ("piv",     "Parainfluenza viruses",        "virus",    "HPIV 1-4"),
    ("adeno",   "Adenovirus",                   "virus",    "Species B, C and E"),
    ("hcov",    "Seasonal coronaviruses",       "virus",    "229E, NL63, OC43, HKU1"),
    # Bacteria
    ("spn",     "Streptococcus pneumoniae",     "bacteria", "Pneumococcus"),
    ("gas",     "Streptococcus pyogenes",       "bacteria", "Group A strep"),
    ("hflu",    "Haemophilus influenzae",       "bacteria", "Mostly nontypeable"),
    ("mcat",    "Moraxella catarrhalis",        "bacteria", ""),
    ("mpn",     "Mycoplasma pneumoniae",        "bacteria", "Now also named Mycoplasmoides pneumoniae"),
    ("cpn",     "Chlamydia pneumoniae",         "bacteria", ""),
    ("bper",    "Bordetella pertussis",         "bacteria", "Whooping cough"),
    ("leg",     "Legionella spp.",              "bacteria", "Legionnaires' disease and Pontiac fever"),
    ("sau",     "Staphylococcus aureus",        "bacteria", "MSSA and MRSA"),
    ("gnb",     "Gram-negative bacilli",        "bacteria", "Klebsiella, Pseudomonas, E. coli and others"),
    ("fnec",    "Fusobacterium necrophorum",    "bacteria", "Adolescent and young-adult pharyngitis"),
    ("gcs",     "Group C/G streptococci",       "bacteria", "Streptococcus dysgalactiae"),
    ("mtb",     "Mycobacterium tuberculosis",   "bacteria", "Tuberculosis"),
    # Fungi
    ("cocci",   "Coccidioides spp.",            "fungi",    "Valley fever"),
    ("histo",   "Histoplasma capsulatum",       "fungi",    "Histoplasmosis"),
    ("pjp",     "Pneumocystis jirovecii",       "fungi",    "Classed as a protozoan until the 1980s"),
    ("asp",     "Aspergillus spp.",             "fungi",    "Including COVID-associated aspergillosis"),
    ("blasto",  "Blastomyces spp.",             "fungi",    "Blastomycosis"),
    ("mucor",   "Mucorales",                    "fungi",    "Mucormycosis, mostly rhino-sinus"),
    # Protozoa
    ("proto",   "Protozoa",                     "protozoa", "Toxoplasma, Cryptosporidium, Leishmania and others"),
]

# ---------------------------------------------------------------------------
# Baseline shares in a typical 2015-2019 year (percent of attributed illness).
# Upper: common cold, pharyngitis, sinusitis, otitis media, croup (ICD-10 J00-J06, H65-H66).
# Lower: bronchiolitis, acute bronchitis, pneumonia (ICD-10 J09-J22).
# Influenza and SARS-CoV-2 are handled separately below.
# ---------------------------------------------------------------------------
BASELINE = {
    "upper": {
        "rhino": 40.0, "hcov": 11.0, "rsv": 5.0, "piv": 5.0, "adeno": 5.0, "hmpv": 3.0,
        "gas": 6.5, "spn": 3.5, "hflu": 4.5, "mcat": 2.0, "mpn": 1.2, "cpn": 0.5,
        "bper": 0.4, "fnec": 0.8, "gcs": 0.8, "sau": 0.3, "gnb": 0.1, "leg": 0.05,
        "mtb": 0.005,
        "asp": 0.05, "mucor": 0.004, "cocci": 0.0, "histo": 0.0, "pjp": 0.0, "blasto": 0.0,
        "proto": 0.001,
    },
    "lower": {
        "rhino": 19.0, "rsv": 15.0, "hmpv": 7.0, "piv": 5.5, "adeno": 4.5, "hcov": 4.5,
        "spn": 8.5, "hflu": 3.0, "mcat": 1.2, "mpn": 5.0, "cpn": 1.5, "bper": 1.2,
        "leg": 0.6, "sau": 2.2, "gnb": 2.0, "gas": 0.4, "mtb": 0.15, "fnec": 0.02,
        "gcs": 0.05,
        "cocci": 0.5, "histo": 0.25, "pjp": 0.12, "asp": 0.12, "blasto": 0.03, "mucor": 0.01,
        "proto": 0.003,
    },
}

# Baseline influenza share by tract (A+B), split by the 2015-19 A:B illness ratio.
FLU_BASELINE_SHARE = {"upper": 9.0, "lower": 15.0}

# ---------------------------------------------------------------------------
# Influenza: estimated symptomatic illnesses (millions) per calendar year,
# split into A and B. Built from CDC season burden estimates
# (2014-15 30M, 2015-16 24M, 2016-17 29M, 2017-18 41M, 2018-19 29M, 2019-20 36M,
# 2020-21 negligible, 2021-22 9M, 2022-23 31M, 2023-24 40M, 2024-25 ~58M
# [43-73M], 2025-26 ~42M [>=29M by 21 Mar 2026]) apportioned to calendar years by
# season timing, and split A/B using FluView clinical-lab positivity.
# ---------------------------------------------------------------------------
FLU_ILLNESS_M = {
    #      A      B
    2015: (13.25, 5.15),
    2016: (18.90, 7.50),
    2017: (23.60, 9.30),
    2018: (24.60, 12.60),
    2019: (27.90, 9.40),
    2020: (16.50, 7.00),
    2021: (3.80, 0.10),
    2022: (29.70, 0.55),
    2023: (20.10, 2.10),
    2024: (29.25, 6.35),
    2025: (60.40, 2.80),
    2026: (13.90, 11.30),   # Jan-Sep: tail of subclade K H3N2 season, then a large B wave Feb-Apr
}

# ---------------------------------------------------------------------------
# SARS-CoV-2: estimated symptomatic illnesses (millions) per calendar year.
# CDC burden estimates (Feb 2020-Sep 2021 ~124M; Oct 2022-Sep 2023 43.6M;
# Oct 2023-Sep 2024 33.0M; Oct 2024-Aug 2025 12-18.3M), apportioned to calendar
# years. LRTI_FACTOR: lower-tract involvement per illness relative to influenza
# (higher before population immunity built up).
# ---------------------------------------------------------------------------
COVID_ILLNESS_M = {2020: 75.0, 2021: 80.0, 2022: 100.0, 2023: 35.5, 2024: 26.5, 2025: 15.5, 2026: 10.0}
COVID_LRTI_FACTOR = {2020: 1.5, 2021: 1.4, 2022: 1.1, 2023: 1.05, 2024: 1.0, 2025: 1.0, 2026: 1.0}

# ---------------------------------------------------------------------------
# Activity indices for every other pathogen (1.0 = typical 2015-19 year).
# Sources: NREVSS national trends (viruses), NNDSS annual case counts
# (pertussis, Legionella, TB, coccidioidomycosis), ABCs/MMWR reports (GAS,
# pneumococcus, Mycoplasma). 2026 values are Jan-Sep activity.
# ---------------------------------------------------------------------------
def idx(*vals):
    assert len(vals) == len(YEARS), vals
    return dict(zip(YEARS, vals))

#                 2015  2016  2017  2018  2019  2020  2021  2022  2023  2024  2025  2026*
ACTIVITY = {
    "rhino":  idx(1.00, 1.00, 1.00, 1.05, 1.00, 0.80, 1.05, 1.10, 1.00, 1.05, 1.00, 0.70),
    "rsv":    idx(0.95, 1.00, 1.00, 1.00, 1.05, 0.45, 1.05, 1.50, 0.85, 0.95, 0.95, 0.45),
    "hmpv":   idx(1.00, 1.00, 0.95, 1.05, 1.00, 0.65, 0.45, 0.85, 1.35, 1.00, 1.15, 0.85),
    "piv":    idx(1.05, 0.95, 1.05, 0.95, 1.00, 0.35, 1.05, 1.00, 1.00, 1.00, 1.00, 0.70),
    "adeno":  idx(1.00, 1.00, 1.00, 1.00, 1.00, 0.50, 0.80, 1.10, 1.00, 1.00, 1.00, 0.75),
    "hcov":   idx(1.00, 0.95, 1.05, 0.95, 1.05, 0.50, 0.40, 0.95, 1.00, 1.05, 1.00, 0.65),
    "spn":    idx(1.04, 1.02, 1.00, 0.98, 0.96, 0.60, 0.70, 0.95, 1.00, 0.97, 0.94, 0.64),
    "gas":    idx(0.95, 0.97, 1.00, 1.03, 1.05, 0.55, 0.55, 1.20, 1.30, 1.10, 1.05, 0.75),
    "hflu":   idx(1.00, 1.00, 1.00, 1.00, 1.00, 0.60, 0.70, 0.95, 1.00, 1.00, 1.00, 0.70),
    "mcat":   idx(1.00, 1.00, 1.00, 1.00, 1.00, 0.60, 0.70, 0.95, 1.00, 1.00, 1.00, 0.70),
    "mpn":    idx(1.00, 1.05, 0.95, 1.00, 1.00, 0.35, 0.10, 0.10, 0.50, 2.60, 1.30, 0.65),
    "cpn":    idx(1.00, 1.00, 1.00, 1.00, 1.00, 0.50, 0.35, 0.50, 0.85, 1.00, 1.00, 0.75),
    # NNDSS pertussis: 20,762 / 17,972 / 18,975 / 15,609 / 18,617 / 6,124 / 2,116 /
    # 3,044 / 7,063 / ~35,400 / 28,783 / 2026 Jan-Sep assumed ~13,000
    "bper":   idx(1.13, 0.98, 1.03, 0.85, 1.01, 0.33, 0.12, 0.17, 0.38, 1.93, 1.57, 0.71),
    "leg":    idx(0.78, 0.79, 0.97, 1.25, 1.21, 1.00, 1.05, 1.05, 1.10, 1.10, 1.15, 0.77),
    "sau":    idx(1.00, 1.00, 1.00, 1.00, 1.00, 0.85, 0.90, 1.00, 1.00, 1.00, 1.00, 0.75),
    "gnb":    idx(1.00, 1.00, 1.00, 1.00, 1.00, 1.05, 1.05, 1.00, 1.00, 1.00, 1.00, 0.75),
    "fnec":   idx(1.00, 1.00, 1.00, 1.00, 1.00, 0.60, 0.60, 1.00, 1.00, 1.00, 1.00, 0.75),
    "gcs":    idx(1.00, 1.00, 1.00, 1.00, 1.00, 0.60, 0.60, 1.00, 1.00, 1.00, 1.00, 0.75),
    # NTSS TB cases: 9,557 ... 8,904 / 7,171 / 7,874 / 8,331 / 9,633 / 10,347 / 10,260
    "mtb":    idx(1.04, 1.01, 0.99, 0.98, 0.97, 0.78, 0.86, 0.91, 1.05, 1.13, 1.12, 0.83),
    "cocci":  idx(0.80, 0.80, 1.03, 1.10, 1.30, 1.30, 1.40, 1.30, 1.60, 1.90, 1.70, 1.04),
    "histo":  idx(1.00, 1.00, 1.00, 1.00, 1.00, 0.90, 1.00, 1.00, 1.00, 1.00, 1.00, 0.75),
    "pjp":    idx(1.10, 1.05, 1.00, 0.95, 0.92, 0.95, 0.95, 0.90, 0.88, 0.86, 0.85, 0.64),
    "asp":    idx(1.00, 1.00, 1.00, 1.00, 1.00, 1.30, 1.35, 1.10, 1.00, 1.00, 1.00, 0.75),
    "blasto": idx(1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.25, 1.00, 1.00, 0.75),
    "mucor":  idx(1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.20, 1.00, 1.00, 1.00, 1.00, 0.75),
    "proto":  idx(1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 0.75),
}

# Lower-tract-only modifier: infant RSV immunisation (nirsevimab, maternal
# vaccine) and older-adult RSV vaccines reduce severe RSV LRTI from late 2023.
LOWER_MODIFIER = {"rsv": {2024: 0.90, 2025: 0.85, 2026: 0.85}}

# Where each number comes from, shown beside every calculation on the page.
BASELINE_SOURCE = {
    "upper": "Author-set from Heikkinen & Jarvinen 2003 (colds), Kaur 2017 (otitis media), Centor 2015 (pharyngitis)",
    "lower": "Author-set from the CDC EPIC studies (Jain 2015, NEJM, adults and children)",
}
_NREVSS = "CDC NREVSS national trend, read by the author (not an exact ratio)"
_DIP = "Author estimate: typical-year 1.0, with a 2020-21 pandemic dip"
ACTIVITY_SOURCE = {
    "rhino": _NREVSS + "; EV-D68 years 2018/2022/2024 raised",
    "rsv": _NREVSS + "; 2021 off-season and 2022 early surges",
    "hmpv": _NREVSS + "; large 2023 spring season",
    "piv": _NREVSS, "adeno": _NREVSS, "hcov": _NREVSS,
    "spn": "Author estimate from CDC ABCs pneumococcal trends; PCV15/20/21 slow decline",
    "gas": "Author estimate from CDC ABCs group A strep trends; 2022-23 surge",
    "hflu": _DIP, "mcat": _DIP, "sau": _DIP, "gnb": _DIP, "fnec": _DIP, "gcs": _DIP,
    "mpn": "Author estimate; 2024 = 2.6 from MMWR 2025 (pediatric CAP 12.5 vs 2.1 per 1,000)",
    "cpn": "Author estimate tracking the Mycoplasma pattern",
    "bper": "NNDSS pertussis cases / 18,386 (2015-19 mean); 2024 ~35,400, 2025 28,783; 2026 assumed",
    "leg": "NNDSS legionellosis cases (approximate) / 2015-19 mean",
    "mtb": "NTSS TB cases / 9,173 (2015-19 mean); 2025 = 10,260",
    "cocci": "NNDSS coccidioidomycosis cases (approximate) / 2015-19 mean",
    "histo": "Author estimate (flat)", "pjp": "Author estimate: slow decline with HIV treatment",
    "asp": "Author estimate: COVID-associated aspergillosis 2020-22",
    "blasto": "Author estimate: 2023 Michigan outbreak", "mucor": "Author estimate (flat)",
    "proto": "Author estimate (flat)",
    "fluA": "CDC flu burden by season, apportioned to calendar years; A/B split from FluView",
    "fluB": "CDC flu burden by season, apportioned to calendar years; A/B split from FluView",
    "sars2": "CDC COVID-19 burden estimates and JAMA Intern Med 2026, apportioned to calendar years",
}


# ---------------------------------------------------------------------------
# Case counts. Shares are turned into estimated illness counts by anchoring each
# tract to CDC's influenza illness estimates: in the upper tract every influenza
# illness counts once, and in the lower tract LRTI_SHARE_OF_FLU of them involve
# the lower airways. One model unit therefore equals a fixed number of illnesses.
# US resident population (Census Bureau July 1 estimates; 2025-26 approximate)
# is used to express the totals per person.
# ---------------------------------------------------------------------------
LRTI_SHARE_OF_FLU = 0.15
US_POP_M = {
    2015: 320.7, 2016: 323.1, 2017: 325.1, 2018: 326.8, 2019: 328.3, 2020: 331.6,
    2021: 332.1, 2022: 334.0, 2023: 336.8, 2024: 340.1, 2025: 341.8, 2026: 343.3,
}


def illnesses_per_unit(tract):
    """Millions of illnesses represented by one model unit in a tract."""
    a_base, b_base = flu_baseline_split()
    flu_m = a_base + b_base
    if tract == "lower":
        flu_m *= LRTI_SHARE_OF_FLU
    return flu_m / FLU_BASELINE_SHARE[tract]


def flu_baseline_split():
    yrs = range(2015, 2020)
    a = sum(FLU_ILLNESS_M[y][0] for y in yrs) / 5
    b = sum(FLU_ILLNESS_M[y][1] for y in yrs) / 5
    return a, b


def raw_units(tract, year):
    """Unnormalised activity-weighted units for every pathogen in a tract-year."""
    units = {}
    for pid, *_ in PATHOGENS:
        if pid in ("fluA", "fluB", "sars2"):
            continue
        v = BASELINE[tract][pid] * ACTIVITY[pid][year]
        if tract == "lower":
            v *= LOWER_MODIFIER.get(pid, {}).get(year, 1.0)
        units[pid] = v

    a_base, b_base = flu_baseline_split()
    flu_share = FLU_BASELINE_SHARE[tract]
    a_share = flu_share * a_base / (a_base + b_base)
    b_share = flu_share * b_base / (a_base + b_base)
    a_m, b_m = FLU_ILLNESS_M[year]
    units["fluA"] = a_share * a_m / a_base
    units["fluB"] = b_share * b_m / b_base

    covid_m = COVID_ILLNESS_M.get(year, 0.0)
    per_flu_illness = flu_share / (a_base + b_base)  # units per million illnesses
    factor = COVID_LRTI_FACTOR.get(year, 1.0) if tract == "lower" else 1.0
    units["sars2"] = covid_m * per_flu_illness * factor
    return units


def explain(tract, year, pid, units):
    """Human-readable calculation of one pathogen's units in a tract-year."""
    a_base, b_base = flu_baseline_split()
    flu_share = FLU_BASELINE_SHARE[tract]
    if pid in ("fluA", "fluB"):
        is_a = pid == "fluA"
        mean = a_base if is_a else b_base
        slice_ = flu_share * mean / (a_base + b_base)
        ill = FLU_ILLNESS_M[year][0 if is_a else 1]
        return {"baseline": round(slice_, 3), "mult": round(ill / mean, 4),
                "formula": f"{slice_:.2f} x ({ill:.2f}M / {mean:.2f}M) = {units:.3f}"}
    if pid == "sars2":
        ill = COVID_ILLNESS_M.get(year, 0.0)
        f = COVID_LRTI_FACTOR.get(year, 1.0) if tract == "lower" else 1.0
        tail = f" x {f:.2f} LRTI factor" if tract == "lower" else ""
        return {"baseline": None, "mult": None,
                "formula": f"{ill:.1f}M x ({flu_share:g} / {a_base + b_base:.2f}M){tail} = {units:.3f}"}
    base = BASELINE[tract][pid]
    mult = ACTIVITY[pid][year]
    mod = LOWER_MODIFIER.get(pid, {}).get(year, 1.0) if tract == "lower" else 1.0
    mod_txt = f" x {mod:.2f} immunization" if mod != 1.0 else ""
    return {"baseline": base, "mult": mult, "mod": mod,
            "formula": f"{base:g} x {mult:.2f}{mod_txt} = {units:.3f}"}


def to_shares(units, decimals=2):
    """Normalise to 100 and round with largest-remainder so the total is exact."""
    total = sum(units.values())
    scale = 10 ** decimals
    exact = {k: v / total * 100 * scale for k, v in units.items()}
    floored = {k: int(v) for k, v in exact.items()}
    shortfall = 100 * scale - sum(floored.values())
    for k in sorted(exact, key=lambda k: exact[k] - floored[k], reverse=True)[:shortfall]:
        floored[k] += 1
    return {k: v / scale for k, v in floored.items()}


def build():
    raw = {t: {y: raw_units(t, y) for y in YEARS} for t in ("upper", "lower")}
    shares = {t: {y: to_shares(raw[t][y]) for y in YEARS} for t in raw}
    for t in shares:
        for y in YEARS:
            s = round(sum(shares[t][y].values()), 6)
            assert s == 100.0, (t, y, s)
    # Pathogens present in a tract-year but too small to show at two decimals.
    trace = {
        t: {y: [pid for pid, *_ in PATHOGENS if raw[t][y][pid] > 0 and shares[t][y][pid] == 0] for y in YEARS}
        for t in raw
    }
    cases = {
        t: {y: {pid: round(v * illnesses_per_unit(t) * 1e6) for pid, v in raw[t][y].items()} for y in YEARS}
        for t in raw
    }
    audit = {t: {y: {pid: explain(t, y, pid, raw[t][y][pid]) for pid, *_ in PATHOGENS} for y in YEARS} for t in raw}
    for t in raw:
        for y in YEARS:
            for pid in audit[t][y]:
                audit[t][y][pid]["units"] = raw[t][y][pid]
    return shares, trace, cases, audit


def write_calculations(shares, cases, audit):
    path = HERE / "calculations.csv"
    with path.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["year", "tract", "pathogen_id", "pathogen", "baseline_pct", "year_multiplier", "lower_modifier",
                    "units", "total_units", "share_pct", "illnesses_per_unit", "est_illnesses",
                    "units_formula", "multiplier_source", "baseline_source"])
        for t in ("upper", "lower"):
            for y in YEARS:
                total = sum(a["units"] for a in audit[t][y].values())
                for pid, name, _, _ in PATHOGENS:
                    a = audit[t][y][pid]
                    w.writerow([y, t, pid, name, a["baseline"] if a["baseline"] is not None else "",
                                a["mult"] if a["mult"] is not None else "", a.get("mod", ""),
                                f"{a['units']:.4f}", f"{total:.4f}", f"{shares[t][y][pid]:.2f}",
                                round(illnesses_per_unit(t) * 1e6), cases[t][y][pid], a["formula"],
                                ACTIVITY_SOURCE[pid], BASELINE_SOURCE[t] if pid not in ("fluA", "fluB", "sars2") else ""])
    return path


def write_csv(shares, cases):
    path = HERE / "estimates.csv"
    with path.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["year", "tract", "pathogen_id", "pathogen", "type", "share_pct", "est_illnesses"])
        for t in ("upper", "lower"):
            for y in YEARS:
                for pid, name, ptype, _ in PATHOGENS:
                    w.writerow([y, t, pid, name, ptype, f"{shares[t][y][pid]:.2f}", cases[t][y][pid]])
    return path


def write_html(shares, trace, cases, audit):
    path = HERE / "index.html"
    payload = {
        "years": YEARS,
        "pathogens": [
            {"id": pid, "name": name, "type": ptype, "note": note}
            for pid, name, ptype, note in PATHOGENS
        ],
        "shares": {
            t: {str(y): [shares[t][y][pid] for pid, *_ in PATHOGENS] for y in YEARS}
            for t in shares
        },
        "trace": {t: {str(y): trace[t][y] for y in YEARS} for t in trace},
        "cases": {
            t: {str(y): [cases[t][y][pid] for pid, *_ in PATHOGENS] for y in YEARS}
            for t in cases
        },
        "population": {str(y): round(US_POP_M[y] * 1e6) for y in YEARS},
        "audit": {
            "rows": {
                t: {str(y): [[round(audit[t][y][pid]["units"], 4), audit[t][y][pid]["formula"]] for pid, *_ in PATHOGENS]
                    for y in YEARS}
                for t in audit
            },
            "source": [ACTIVITY_SOURCE[pid] for pid, *_ in PATHOGENS],
            "baselineSource": BASELINE_SOURCE,
            "perUnit": {t: round(illnesses_per_unit(t) * 1e6) for t in ("upper", "lower")},
            "fluMean": [round(v, 3) for v in flu_baseline_split()],
            "fluShare": FLU_BASELINE_SHARE,
            "lrtiShareOfFlu": LRTI_SHARE_OF_FLU,
            "flu": {str(y): list(FLU_ILLNESS_M[y]) for y in YEARS},
            "covid": {str(y): COVID_ILLNESS_M.get(y, 0.0) for y in YEARS},
            "covidLrti": {str(y): COVID_LRTI_FACTOR.get(y, 1.0) for y in YEARS},
        },
    }
    block = "/* DATA:START */\nconst DATA = " + json.dumps(payload, separators=(",", ":")) + ";\n/* DATA:END */"
    html = path.read_text()
    new, n = re.subn(r"/\* DATA:START \*/.*?/\* DATA:END \*/", lambda _: block, html, flags=re.S)
    if n != 1:
        raise SystemExit("index.html: DATA:START / DATA:END markers not found")
    path.write_text(new)
    return path


if __name__ == "__main__":
    shares, trace, cases, audit = build()
    print("wrote", write_csv(shares, cases))
    print("wrote", write_calculations(shares, cases, audit))
    if (HERE / "index.html").exists():
        print("wrote", write_html(shares, trace, cases, audit))
