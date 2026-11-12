"""
Builds the EXCURSION_ data set for the MMR test instance: capacity and demand nearly identical.

Inputs (unchanged):  data/production_capacity_scenarios_NEW_6OCT.xlsx   (base_capacity -> s_real)
                     data/scenario_pairs_new_1_scenario_6OCT.json       (capacity[t][p] -> s_pt, demand[t][a] -> d_at)
                     data/Demand_Scenarios_Base.xlsx / Medium_Demand_calc (vaccine demand d_hat, award ceilings)
Outputs:             data/EXCURSION_production_capacity_scenarios_MMR_balanced.xlsx
                     data/EXCURSION_scenario_pairs_1_scenario_MMR_balanced.json

Rules, per year t (raw doses):
  * vaccine demand d_hat[v,t] is kept;
  * antigen demand d_at[a,t] = sum of d_hat[v,t] over vaccines v containing a (consistent with d_hat;
    the original JSON antigen rows are mislabelled for Mumps/Rubella);
  * Serum Institute (supplies MMR, MR, M) keeps its capacity, split across its vaccines in proportion to demand;
  * each single-vaccine producer is sized so that total capacity for its vaccine = HEADROOM * d_hat[v,t]:
        GSK -> MMR,  Biological_E -> MR,  PT_Bio -> M.
Producers and antigens outside the MMR instance are left untouched.

Run:  python make_excursion_data.py            (MMR instance, HEADROOM = 1.02)
      python make_excursion_data.py 1.00        (MMR, exact match)
      python make_excursion_data.py full [1.02] (full 13-vaccine data, see make_full below)
"""
import json
import sys
from pathlib import Path

import openpyxl

DATA = Path(__file__).resolve().parent / "data"


def make_full(headroom):
    """
    Full data set (13 vaccines, 15 producers; files used by run_original):
      data/production_capacity_scenarios_NEW_15YR_NO_MMR.xlsx, data/scenario_pairs_new_1_scenario_15YR_NO_MMR.json
    Producers share capacity across vaccines, so capacity is built from market shares
    (data/producer_ratios.xlsx, prop_by_manuf, normalised over the producers of each vaccine in the model):
        cap[p,t] = headroom * sum_{v in V_p} share[v,p] * d_hat[v,t]
    so that if every producer devotes share[v,p] of its capacity-need to v, every vaccine's demand is covered.
    Antigen demand d_at[a,t] = sum of d_hat[v,t] over vaccines containing a.
    Only years with vaccine demand (1-10) are changed; later years in the 15-year files are left as they are.
    """
    # sets: must match create_vaccine_data.jl
    V_p = {
        "AJ_Vaccines": ["IPV"], "BB_NCIPD": ["Td", "TT", "DT"], "China_National": ["HPV", "OPV"],
        "Bharat_Biotech": ["Rotavirus", "OPV"], "Bilthoven": ["IPV"], "Biological_E": ["Td", "TT", "Penta", "DTwP"],
        "GSK": ["PCV", "Rotavirus", "HPV", "OPV"], "Haffkine_Bio": ["OPV"], "LG_Chem": ["IPV", "HepB", "Penta"],
        "Merck_Sharp": ["HPV"], "Panacea_Biotec": ["Penta", "OPV"], "PT_Bio": ["Td", "TT", "DT", "Penta", "OPV"],
        "Sanofi": ["IPV", "Hexa", "OPV"],
        "Serum_Institute": ["Td", "PCV", "Rotavirus", "DTwP-Hib", "TT", "HepB", "Penta", "DTwP", "OPV"],
        "Pfizer": ["PCV"],
    }
    V_a = {
        "Diphtheria": ["Td", "DTwP-Hib", "Hexa", "DT", "Penta", "DTwP"],
        "Tetanus": ["Td", "DTwP-Hib", "Hexa", "TT", "DT", "Penta", "DTwP"],
        "Pertussis": ["DTwP-Hib", "Hexa", "Penta", "DTwP"],
        "Hepatitis_B": ["Hexa", "HepB", "Penta"], "Hib": ["DTwP-Hib", "Hexa", "Penta"],
        "Polio": ["IPV", "Hexa", "OPV"], "HPV": ["HPV"], "Rotavirus": ["Rotavirus"], "PCV": ["PCV"],
    }
    vaccines = sorted({v for vs in V_p.values() for v in vs})
    P_v = {v: [p for p, vs in V_p.items() if v in vs] for v in vaccines}

    cap_in = DATA / "production_capacity_scenarios_NEW_15YR_NO_MMR.xlsx"
    scen_in = DATA / "scenario_pairs_new_1_scenario_15YR_NO_MMR.json"
    cap_out = DATA / "EXCURSION_production_capacity_scenarios_FULL_balanced.xlsx"
    scen_out = DATA / "EXCURSION_scenario_pairs_1_scenario_FULL_balanced.json"

    # vaccine demand
    ws = openpyxl.load_workbook(DATA / "Demand_Scenarios_Base.xlsx", data_only=True)["Medium_Demand_calc"]
    first = next(ws.iter_rows(min_row=1, max_row=1, values_only=True))
    years = [int(c) for c in first[1:] if isinstance(c, (int, float))]
    d_hat = {}
    for row in ws.iter_rows(min_row=2, values_only=True):
        if row[0] in vaccines and row[0] not in d_hat:   # first row, as the Julia loader (findfirst)
            d_hat[row[0]] = {t: float(row[i + 1] or 0.0) for i, t in enumerate(years)}
    missing = set(vaccines) - set(d_hat)
    if missing:
        sys.exit(f"Vaccine demand rows not found: {missing}")

    # market shares, normalised over P_v (equal split if no ratio is listed for any producer of v)
    rs = openpyxl.load_workbook(DATA / "producer_ratios.xlsx", data_only=True)["prop_by_manuf"]
    raw = {(row[2], row[0]): float(row[1]) for row in rs.iter_rows(min_row=2, values_only=True) if row[0] and row[2]}
    share = {}
    for v, ps in P_v.items():
        tot = sum(raw.get((v, p), 0.0) for p in ps)
        for p in ps:
            share[(v, p)] = raw.get((v, p), 0.0) / tot if tot > 0 else 1.0 / len(ps)

    new_cap = {p: {t: headroom * sum(share[(v, p)] * d_hat[v][t] for v in vs) for t in years} for p, vs in V_p.items()}

    wb = openpyxl.load_workbook(cap_in)
    cap_ws = wb["base_capacity"]
    header = [c.value for c in cap_ws[1]]
    col_of_year = {int(h): j for j, h in enumerate(header) if isinstance(h, (int, float))}
    row_of = {cap_ws.cell(r, 1).value: r for r in range(2, cap_ws.max_row + 1)}
    old_cap1 = {}
    for p in V_p:
        if p not in row_of:
            sys.exit(f"Producer {p} not in base_capacity of {cap_in.name}")
        old_cap1[p] = float(cap_ws.cell(row_of[p], col_of_year[1] + 1).value)
        for t in years:
            if t in col_of_year:
                cap_ws.cell(row_of[p], col_of_year[t] + 1).value = new_cap[p][t]
    wb.save(cap_out)

    scen = json.loads(scen_in.read_text())
    for s in scen.values():
        for t_str in s["capacity"]:
            t = int(t_str)
            if t in years:
                for p in V_p:
                    s["capacity"][t_str][p] = new_cap[p][t]
        for t_str in s["demand"]:
            t = int(t_str)
            if t in years:
                for a, vs in V_a.items():
                    s["demand"][t_str][a] = sum(d_hat[v][t] for v in vs)
    scen_out.write_text(json.dumps(scen, indent=2))

    print(f"FULL excursion, headroom = {headroom}")
    print(f"{'producer':16s} {'old cap y1':>12s} {'new cap y1':>12s} {'new cap y5':>12s}  (thousand doses)")
    for p in V_p:
        print(f"{p:16s} {old_cap1[p]/1e3:12,.0f} {new_cap[p][1]/1e3:12,.0f} {new_cap[p][5]/1e3:12,.0f}")
    for v in vaccines:
        cov = sum(share[(v, p)] for p in P_v[v])
        print(f"  {v:10s} demand y1 {d_hat[v][1]/1e3:10,.0f}k  shares sum {cov:.2f}  producers {P_v[v]}")
    print("wrote", cap_out.name, "and", scen_out.name)


if len(sys.argv) > 1 and sys.argv[1].lower() == "full":
    make_full(float(sys.argv[2]) if len(sys.argv) > 2 else 1.02)
    sys.exit(0)

HEADROOM = float(sys.argv[1]) if len(sys.argv) > 1 else 1.02
CAP_IN = DATA / "production_capacity_scenarios_NEW_6OCT.xlsx"
SCEN_IN = DATA / "scenario_pairs_new_1_scenario_6OCT.json"
DEM_IN = DATA / "Demand_Scenarios_Base.xlsx"
CAP_OUT = DATA / "EXCURSION_production_capacity_scenarios_MMR_balanced.xlsx"
SCEN_OUT = DATA / "EXCURSION_scenario_pairs_1_scenario_MMR_balanced.json"

VACCINES_OF_ANTIGEN = {"Measles": ["MMR", "MR", "M"], "Mumps": ["MMR"], "Rubella": ["MMR", "MR"]}
SHARED = "Serum_Institute"
SHARED_VACCINES = ["MMR", "MR", "M"]
DEDICATED = {"GSK": "MMR", "Biological_E": "MR", "PT_Bio": "M"}

# ---- vaccine demand d_hat (raw doses) ----
ws = openpyxl.load_workbook(DEM_IN, data_only=True)["Medium_Demand_calc"]
years = [c for c in next(ws.iter_rows(min_row=1, max_row=1, values_only=True))[1:] if isinstance(c, (int, float))]
years = [int(y) for y in years]
d_hat = {}
for row in ws.iter_rows(min_row=2, values_only=True):
    if row[0] in SHARED_VACCINES and row[0] not in d_hat:   # first row, as the Julia loader
        d_hat[row[0]] = {t: float(row[i + 1]) for i, t in enumerate(years)}
missing = set(SHARED_VACCINES) - set(d_hat)
if missing:
    sys.exit(f"Vaccine demand rows not found: {missing}")

# ---- capacity workbook: current capacity of the shared producer ----
wb = openpyxl.load_workbook(CAP_IN)
cap_ws = wb["base_capacity"]
header = [c.value for c in cap_ws[1]]
col_of_year = {int(h): j for j, h in enumerate(header) if isinstance(h, (int, float))}
row_of = {cap_ws.cell(r, 1).value: r for r in range(2, cap_ws.max_row + 1)}
for p in [SHARED, *DEDICATED]:
    if p not in row_of:
        sys.exit(f"Producer {p} not in base_capacity")
cap_years = sorted(t for t in col_of_year if t in years)

new_cap = {}
for t in cap_years:
    shared_cap = float(cap_ws.cell(row_of[SHARED], col_of_year[t] + 1).value)
    total_dem = sum(d_hat[v][t] for v in SHARED_VACCINES)
    for p, v in DEDICATED.items():
        shared_part = shared_cap * d_hat[v][t] / total_dem
        cap = HEADROOM * d_hat[v][t] - shared_part
        if cap <= 0:
            sys.exit(f"{p} would get capacity {cap} in year {t}; Serum Institute alone exceeds demand for {v}")
        new_cap.setdefault(p, {})[t] = cap

for p, caps in new_cap.items():
    for t, cap in caps.items():
        cap_ws.cell(row_of[p], col_of_year[t] + 1).value = cap
wb.save(CAP_OUT)

# ---- scenario JSON: capacity[t][p] and demand[t][a] ----
scen = json.loads(SCEN_IN.read_text())
for key, s in scen.items():
    for t_str in s["capacity"]:
        t = int(t_str)
        for p in DEDICATED:
            if t in new_cap[p]:
                s["capacity"][t_str][p] = new_cap[p][t]
            elif p in s["capacity"][t_str]:
                print(f"warning: year {t} not in capacity workbook; {p} left unchanged in JSON")
    for t_str in s["demand"]:
        t = int(t_str)
        if t in years:
            for a, vs in VACCINES_OF_ANTIGEN.items():
                s["demand"][t_str][a] = sum(d_hat[v][t] for v in vs)
SCEN_OUT.write_text(json.dumps(scen, indent=2))

# ---- report ----
print(f"HEADROOM = {HEADROOM}")
for t in cap_years[:5]:
    shared_cap = float(cap_ws.cell(row_of[SHARED], col_of_year[t] + 1).value)
    total_cap = shared_cap + sum(new_cap[p][t] for p in DEDICATED)
    total_dem = sum(d_hat[v][t] for v in SHARED_VACCINES)
    print(f"year {t}: capacity {total_cap/1e3:,.0f}k  vaccine demand {total_dem/1e3:,.0f}k  ratio {total_cap/total_dem:.3f}  "
          + "  ".join(f"{p} {new_cap[p][t]/1e3:,.0f}k" for p in DEDICATED))
print("wrote", CAP_OUT.name, "and", SCEN_OUT.name)
