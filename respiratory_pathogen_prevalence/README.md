# respiratory_pathogen_prevalence

An interactive page showing the estimated share of US respiratory tract infections caused by each pathogen, split into upper and lower tract, for every year from 2015 to 2026.

Open `index.html` in a browser. It is a single self-contained file, apart from Google Fonts, which fall back to system fonts when offline.

## What the page shows

- **Two panels side by side:** the upper respiratory tract and the lower respiratory tract.
  - *Upper:* colds, sore throat, sinusitis, ear infections and croup (ICD-10 J00–J06, H65–H66).
  - *Lower:* bronchiolitis, acute bronchitis and pneumonia (J09–J22).
- **A donut chart for the selected year,** with a ranked list of shares that adds to 100%.
- **100% stacked year columns for 2015–2026.** Click a column, or use the ‹ › stepper or the arrow keys, to show that year in the donut and table. The two panels follow the same year unless **Link years across panels** is turned off.
- **One shared color legend.** Click any pathogen in the legend, the ranked list, the donut or the table to follow it. The page then moves that pathogen to the base of every column and lists its share under each year.
- **A full table of all 29 pathogens** (9 viruses, 13 bacteria, 6 fungi and protozoa), to two decimals, with subtotals by type.

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
| `estimates.csv` | Every value in long format: `year, tract, pathogen_id, pathogen, type, share_pct`. |

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
