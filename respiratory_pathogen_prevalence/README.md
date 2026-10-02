# respiratory_pathogen_prevalence

An interactive page showing the estimated share of US respiratory tract infections caused by each pathogen, split into upper and lower tract, for every year from 2015 to 2026.

Open `index.html` in a browser. It is a single self-contained file, apart from Google Fonts, which fall back to system fonts when offline.

## What the page shows

- **Two panels side by side:** the upper respiratory tract and the lower respiratory tract.
  - *Upper:* colds, sore throat, sinusitis, ear infections and croup (ICD-10 J00–J06, H65–H66).
  - *Lower:* bronchiolitis, acute bronchitis and pneumonia (J09–J22).
- **Ranked horizontal bars for the selected year** in each panel, on a shared scale, adding to 100%. Each panel also gives the estimated total number of illnesses and the rate per US resident.
- **Full-width 100% stacked horizontal bars,** one per year from 2015 to 2026, for each tract. Shares large enough to fit are labeled inside their segment. Click a bar, use the ‹ › stepper, or use the arrow keys to show that year in the panels and the table. The two panels follow the same year unless **Link years across panels** is turned off.
- **One shared color legend.** Click any pathogen in the legend, the ranked bars or the table to follow it. The page then moves that pathogen to the start of every year bar and lists its share at the right.
- **Calculation for every value:** a section below the sources. Pick a tract and a year to see each pathogen's arithmetic (baseline × multiplier = units; units ÷ total = share; units × illnesses-per-unit = illnesses) and the source of each input.
- **A full table of all 29 pathogens** (9 viruses, 13 bacteria, 6 fungi and protozoa), with subtotals by type. Each cell shows estimated illnesses with the share in brackets, for example `135,209,000 [35.12%]`.

## Method

The numbers are **modeled estimates**, not an official dataset. `build_estimates.py` builds them in four steps:

1. **Baseline shares.** Each pathogen starts from its share of illnesses with an identified cause in a typical 2015–2019 year.
   - Lower tract: the CDC EPIC pneumonia studies (Jain et al., *NEJM* 2015, adults and children).
   - Upper tract: common-cold, pharyngitis and acute otitis media etiology studies.
2. **Yearly activity scaling.** Each calendar year, the baseline is multiplied by that pathogen's activity relative to a typical year:
   - Viruses: CDC NREVSS lab surveillance trends.
   - Pertussis, Legionella, tuberculosis and coccidioidomycosis: NNDSS / NTSS annual case counts.
   - Mycoplasma (2024) and group A strep (2022–23): published surge reports.
   - Infant and older-adult RSV immunization: a small reduction in RSV's lower-tract share from 2024.
3. **Influenza and SARS-CoV-2.** These are driven directly by CDC estimates of symptomatic illnesses, apportioned to calendar years by season timing.
4. **Normalization.** Every tract-year is rescaled to 100% and rounded with the largest-remainder method, so the shares add to exactly 100.00.

**Illness counts:** shares are converted to numbers of illnesses by anchoring each tract to CDC's influenza illness estimates. Every flu illness counts once in the upper tract, and 15% of them (`LRTI_SHARE_OF_FLU`) count in the lower tract, so one share point stands for a fixed number of illnesses. That comes to about 1 identified-cause upper-tract illness per US resident per year and about 30 million lower-tract illnesses. US population figures are Census Bureau July 1 estimates (2025–26 approximate) and are used for the per-person rate. Counts are rounded to the nearest 1,000 on the page.

**What a share means:** the fraction of symptomatic illnesses with a known cause. It is not test positivity, and it is not deaths. Illnesses with no identified pathogen are excluded. A co-infection is counted once, under its main pathogen.

**Caveats:**
- The large categories are uncertain by a few percentage points.
- **2026 covers January–September only.** Its July–September activity is partly assumed.
- Rhinovirus and enterovirus are combined, because most multiplex panels can't tell them apart.

## Files

| File | Purpose |
|---|---|
| `index.html` | The interactive page. Its data block, between `DATA:START` / `DATA:END`, is generated. |
| `build_estimates.py` | The model: baseline shares, yearly activity indices, influenza and COVID illness estimates. |
| `calculations.csv` | Every input, intermediate value, formula and source behind each value: baseline, year multiplier, units, total units, share, illnesses-per-unit and estimated illnesses. |
| `estimates.csv` | Every value in long format: `year, tract, pathogen_id, pathogen, type, share_pct, est_illnesses`. |

To change an assumption, edit the tables in `build_estimates.py`, then regenerate the CSV and the page's data block:

```bash
python3 build_estimates.py
```

## Key sources

- Jain S, et al. Community-acquired pneumonia requiring hospitalization among U.S. adults / children. *N Engl J Med* 2015;373:415–27 and 372:835–45.
- Heikkinen T, Järvinen A. The common cold. *Lancet* 2003;361:51–59.
- Kaur R, et al. Epidemiology of acute otitis media in the postpneumococcal conjugate vaccine era. *Pediatrics* 2017;140:e20170181.
- CDC flu disease burden estimates by season, 2014–15 to 2024–25, plus 2025–26 in-season estimates and FluView.
- Estimated burden of COVID-19 in the US, October 2022–September 2024. *JAMA Intern Med* 2026;186:321–30. CDC preliminary 2024–25 COVID-19 burden estimates.
- CDC MMWR: *Mycoplasma pneumoniae* infections in hospitalized children, 2018–2024. CDC provisional pertussis reports for 2024 and 2025. CDC 2025 provisional TB data.

The page lists the full source set with links.
