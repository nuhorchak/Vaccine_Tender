# ─────────────────────────────────────────────────────────────────────────────
# 9. BUILD EXCEL OUTPUT
# ─────────────────────────────────────────────────────────────────────────────

# Color palette
BLUE_FONT   = 'FF0000FF'
BLACK_FONT  = 'FF000000'
GREEN_FONT  = 'FF008000'
HEADER_FILL = 'FF1F4E79'
ALT_FILL    = 'FFD6E4F0'
WHITE_FILL  = 'FFFFFFFF'
SECTION_FILL = 'FFD9E1F2'

def make_font(bold=False, color=BLACK_FONT, size=10, name='Arial'):
    return Font(bold=bold, color=color, size=size, name=name)

def make_fill(hex_color):
    return PatternFill('solid', start_color=hex_color, fgColor=hex_color)

def header_style(ws, cell_ref, value, bold=True):
    cell = ws[cell_ref]
    cell.value = value
    cell.font = Font(bold=bold, color='FFFFFFFF', size=10, name='Arial')
    cell.fill = make_fill(HEADER_FILL)
    cell.alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)

def num_fmt(cell, fmt='#,##0'):
    cell.number_format = fmt

def border_thin():
    thin = Side(style='thin', color='FFB8CCE4')
    return Border(left=thin, right=thin, top=thin, bottom=thin)

def apply_table_style(ws, row, col, value, is_alt=False, blue_input=False, formula=False):
    cell = ws.cell(row=row, column=col, value=value)
    cell.border = border_thin()
    cell.alignment = Alignment(horizontal='right', vertical='center')
    if blue_input:
        cell.font = make_font(color=BLUE_FONT)
    elif formula:
        cell.font = make_font(color=BLACK_FONT)
    else:
        cell.font = make_font()
    if is_alt:
        cell.fill = make_fill(ALT_FILL)
    else:
        cell.fill = make_fill(WHITE_FILL)
    cell.number_format = '#,##0'
    return cell

def build_excel(sheets, cap_df, projections, antigen_demand, scenario_data, actual_md):
    wb = Workbook()

    # Remove default sheet
    wb.remove(wb.active)

    # ── Sheet 1: vaccine-producer list (copied) ──────────────────────────────
    _copy_reference_sheet(wb, sheets, 'vaccine-producer list', 'Vaccine-Producer List')

    # ── Sheet 2: vaccine-antigen list (copied) ────────────────────────────────
    _copy_reference_sheet(wb, sheets, 'vaccine-antigen list', 'Vaccine-Antigen List')

    # ── Sheet 3: total_capacity_calcs ─────────────────────────────────────────
    _build_capacity_sheet(wb, cap_df, projections)

    # ── Sheet 4: Medium_Demand_calc ───────────────────────────────────────────
    _build_demand_calc_sheet(wb, antigen_demand, actual_md)

    # ── Sheet 5: Medium_Demand (final) ────────────────────────────────────────
    _build_medium_demand_sheet(wb, scenario_data, actual_md)

    return wb


def _copy_reference_sheet(wb, sheets, src_name, dst_name):
    ws = wb.create_sheet(dst_name)
    df = sheets[src_name]
    ws.freeze_panes = 'B2'

    for r_idx, row in enumerate(df.values, start=1):
        for c_idx, val in enumerate(row, start=1):
            cell = ws.cell(row=r_idx, column=c_idx, value=val if pd.notna(val) else None)
            if r_idx == 1:
                cell.font = Font(bold=True, color='FFFFFFFF', name='Arial', size=9)
                cell.fill = make_fill(HEADER_FILL)
                cell.alignment = Alignment(horizontal='center', wrap_text=True)
            elif c_idx == 1:
                cell.font = Font(bold=True, name='Arial', size=9)
                cell.fill = make_fill(SECTION_FILL)
            else:
                cell.font = Font(name='Arial', size=9)
                if r_idx % 2 == 0:
                    cell.fill = make_fill(ALT_FILL)

    for col in ws.columns:
        max_len = max((len(str(c.value)) if c.value else 0) for c in col)
        ws.column_dimensions[get_column_letter(col[0].column)].width = min(max_len + 2, 30)


def _build_capacity_sheet(wb, cap_df, projections):
    ws = wb.create_sheet('Capacity_Calcs')
    ws.freeze_panes = 'D2'

    years = list(range(2000, 2031))
    headers = ['Vaccine', 'Income Group'] + [str(y) for y in years]

    # Title row
    ws.merge_cells('A1:AJ1')
    title = ws['A1']
    title.value = 'Total Capacity Calculations by Vaccine & Income Group (2000–2030)'
    title.font = Font(bold=True, color='FFFFFFFF', size=12, name='Arial')
    title.fill = make_fill(HEADER_FILL)
    title.alignment = Alignment(horizontal='center', vertical='center')
    ws.row_dimensions[1].height = 22

    # Headers
    for c, h in enumerate(headers, start=1):
        cell = ws.cell(row=2, column=c, value=h)
        cell.font = Font(bold=True, color='FFFFFFFF', size=9, name='Arial')
        cell.fill = make_fill(HEADER_FILL)
        cell.alignment = Alignment(horizontal='center', wrap_text=True)
        cell.border = border_thin()

    # Data
    cur_vaccine = None
    for r_idx, ((vaccine, status), row) in enumerate(cap_df.iterrows(), start=3):
        is_alt = r_idx % 2 == 0
        bg = ALT_FILL if is_alt else WHITE_FILL

        if vaccine != cur_vaccine:
            cur_vaccine = vaccine
            ws.cell(row=r_idx, column=1, value=vaccine).font = Font(bold=True, size=9, name='Arial')
        else:
            ws.cell(row=r_idx, column=1, value='').fill = make_fill(bg)

        ws.cell(row=r_idx, column=2, value=status)

        for c_idx, yr in enumerate(years, start=3):
            val = row.get(yr, None)
            cell = ws.cell(row=r_idx, column=c_idx,
                           value=val if (pd.notna(val) if val is not None else False) else None)
            cell.number_format = '#,##0'
            cell.font = Font(size=9, name='Arial',
                             color=BLUE_FONT if c_idx <= 25 else BLACK_FONT)
            if is_alt:
                cell.fill = make_fill(ALT_FILL)
            cell.border = border_thin()
            cell.alignment = Alignment(horizontal='right')

    ws.column_dimensions['A'].width = 28
    ws.column_dimensions['B'].width = 22
    for i in range(3, len(headers) + 1):
        ws.column_dimensions[get_column_letter(i)].width = 13

    # Legend note
    last_row = ws.max_row + 2
    ws.cell(row=last_row, column=1, value='Note: Blue = historical input; Black = formula projection').font = \
        Font(italic=True, size=8, color='FF595959', name='Arial')


def _build_demand_calc_sheet(wb, antigen_demand, actual_md):
    ws = wb.create_sheet('Medium_Demand_Calc')
    ws.freeze_panes = 'B3'

    periods = list(range(1, 21))  # updated: 20 periods

    # Title — widened to cover 20 period columns (col A + 20 period cols = col V)
    ws.merge_cells('A1:V1')
    t = ws['A1']
    t.value = 'Medium Demand Calculation – Vaccine Format Aggregations'
    t.font = Font(bold=True, color='FFFFFFFF', size=12, name='Arial')
    t.fill = make_fill(HEADER_FILL)
    t.alignment = Alignment(horizontal='center', vertical='center')
    ws.row_dimensions[1].height = 22

    # Header row
    ws.cell(row=2, column=1, value='Vaccine / Antigen').font = Font(bold=True, color='FFFFFFFF', size=9, name='Arial')
    ws.cell(row=2, column=1).fill = make_fill(HEADER_FILL)
    for p in periods:
        cell = ws.cell(row=2, column=p + 1, value=f'Period {p}')
        cell.font = Font(bold=True, color='FFFFFFFF', size=9, name='Arial')
        cell.fill = make_fill(HEADER_FILL)
        cell.alignment = Alignment(horizontal='center')

    # Section 1: Vaccine-level demand (from source)
    vac_order = ['M', 'MR', 'MMR', 'TT', 'Td', 'DT', 'DTwP', 'DTwP-Hib',
                 'Penta', 'Hexa', 'IPV', 'OPV', 'HPV', 'HepB', 'Hib', 'Rotavirus', 'PCV']

    # Try to get actual medium_demand_calc values
    src = pd.read_excel(SOURCE, sheet_name='Medium_Demand_calc', header=None)
    actual_vac = {}
    for _, row in src.iterrows():
        label = row.iloc[0]
        if pd.isna(label) or str(label).strip() in ('', '1'):
            continue
        label = str(label).strip()
        vals = [float(row.iloc[i]) if pd.notna(row.iloc[i]) else 0.0 for i in range(1, 21)]  # updated: 21
        actual_vac[label] = vals

    row_num = 3
    ws.cell(row=row_num, column=1, value='VACCINE FORMAT DEMAND').font = \
        Font(bold=True, size=9, color=BLUE_FONT, name='Arial')
    ws.cell(row=row_num, column=1).fill = make_fill(SECTION_FILL)
    row_num += 1

    for vac in vac_order:
        is_alt = row_num % 2 == 0
        cell = ws.cell(row=row_num, column=1, value=vac)
        cell.font = Font(bold=True, size=9, name='Arial')
        cell.fill = make_fill(SECTION_FILL if not is_alt else ALT_FILL)

        vals = actual_vac.get(vac, antigen_demand.get(vac, [0]*20))  # updated: 20
        for p_idx, val in enumerate(vals[:20]):  # updated: 20
            c = apply_table_style(ws, row_num, p_idx + 2, val, is_alt=is_alt, formula=True)
        row_num += 1

    row_num += 1

    # Section 2: Antigen aggregation
    ws.cell(row=row_num, column=1, value='ANTIGEN-LEVEL AGGREGATION').font = \
        Font(bold=True, size=9, color=BLUE_FONT, name='Arial')
    ws.cell(row=row_num, column=1).fill = make_fill(SECTION_FILL)
    row_num += 1

    for antigen in ALL_ANTIGENS:
        is_alt = row_num % 2 == 0
        cell = ws.cell(row=row_num, column=1, value=antigen)
        cell.font = Font(bold=True, size=9, name='Arial')
        cell.fill = make_fill(SECTION_FILL if not is_alt else ALT_FILL)

        vals = antigen_demand.get(antigen, [0]*20)  # updated: 20
        for p_idx, val in enumerate(vals[:20]):  # updated: 20
            c = apply_table_style(ws, row_num, p_idx + 2, val, is_alt=is_alt, formula=True)
        row_num += 1

    ws.column_dimensions['A'].width = 30
    for i in range(2, 23):  # updated: 23 (covers 20 period columns)
        ws.column_dimensions[get_column_letter(i)].width = 16


def _build_medium_demand_sheet(wb, scenario_data, actual_md):
    ws = wb.create_sheet('Medium_Demand')
    ws.freeze_panes = 'B4'

    periods = list(range(1, 21))  # updated: 20 periods

    # Title — widened to cover 20 period columns (col A + 20 period cols = col V)
    ws.merge_cells('A1:V1')
    t = ws['A1']
    t.value = 'Medium Demand Forecast – Antigen-Level (20 Forecast Periods)'  # updated
    t.font = Font(bold=True, color='FFFFFFFF', size=12, name='Arial')
    t.fill = make_fill(HEADER_FILL)
    t.alignment = Alignment(horizontal='center', vertical='center')
    ws.row_dimensions[1].height = 22

    ws.merge_cells('A2:V2')  # updated
    sub = ws['A2']
    sub.value = ('Demand in doses. Columns 1–20 represent forecast periods. '  # updated
                 'Antigens aggregated from contributing vaccine formats.')
    sub.font = Font(italic=True, size=9, color='FF595959', name='Arial')
    sub.alignment = Alignment(horizontal='left')

    # Header row
    ws.cell(row=3, column=1, value='Antigen').font = Font(bold=True, color='FFFFFFFF', size=10, name='Arial')
    ws.cell(row=3, column=1).fill = make_fill(HEADER_FILL)
    ws.cell(row=3, column=1).alignment = Alignment(horizontal='center')
    for p in periods:
        cell = ws.cell(row=3, column=p + 1, value=f'Period {p}')
        cell.font = Font(bold=True, color='FFFFFFFF', size=10, name='Arial')
        cell.fill = make_fill(HEADER_FILL)
        cell.alignment = Alignment(horizontal='center')

    # Use actual source data if available, else model projections
    source_antigens = []
    if actual_md is not None:
        source_antigens = list(actual_md.index)

    medium_data = scenario_data['Medium']

    # Priority: use actual source data
    row_num = 4
    display_antigens = source_antigens if source_antigens else list(medium_data.keys())

    for antigen in display_antigens:
        is_alt = row_num % 2 == 0
        cell = ws.cell(row=row_num, column=1, value=antigen)
        cell.font = Font(bold=True, size=10, name='Arial')
        cell.fill = make_fill(SECTION_FILL if not is_alt else ALT_FILL)
        cell.border = border_thin()

        if actual_md is not None and antigen in actual_md.index:
            vals = actual_md.loc[antigen].values[:20]  # updated: 20
        else:
            vals = medium_data.get(antigen, [0]*20)  # updated: 20

        for p_idx, val in enumerate(vals[:20]):  # updated: 20
            c = apply_table_style(ws, row_num, p_idx + 2,
                                  float(val) if pd.notna(val) else 0.0,
                                  is_alt=is_alt, formula=True)
        row_num += 1

    # Totals row
    row_num += 1
    ws.cell(row=row_num, column=1, value='TOTAL (All Antigens)').font = \
        Font(bold=True, size=10, color=BLUE_FONT, name='Arial')
    ws.cell(row=row_num, column=1).fill = make_fill(SECTION_FILL)
    ws.cell(row=row_num, column=1).border = border_thin()

    start_data = 4
    end_data = row_num - 2
    for p in range(1, 21):  # updated: 21
        col = p + 1
        col_letter = get_column_letter(col)
        formula = f'=SUM({col_letter}{start_data}:{col_letter}{end_data})'
        cell = ws.cell(row=row_num, column=col, value=formula)
        cell.font = Font(bold=True, size=10, color=BLACK_FONT, name='Arial')
        cell.fill = make_fill(SECTION_FILL)
        cell.number_format = '#,##0'
        cell.border = border_thin()
        cell.alignment = Alignment(horizontal='right')

    # Scenario summary block
    row_num += 3
    ws.cell(row=row_num, column=1, value='SCENARIO COMPARISON SUMMARY').font = \
        Font(bold=True, size=11, color=BLUE_FONT, name='Arial')
    ws.cell(row=row_num, column=1).fill = make_fill(SECTION_FILL)
    ws.merge_cells(start_row=row_num, start_column=1, end_row=row_num, end_column=21)  # updated: 21
    row_num += 1

    for p in periods:
        cell = ws.cell(row=row_num, column=p + 1, value=f'P{p}')
        cell.font = Font(bold=True, color='FFFFFFFF', size=9, name='Arial')
        cell.fill = make_fill(HEADER_FILL)
        cell.alignment = Alignment(horizontal='center')
    ws.cell(row=row_num, column=1, value='Scenario').font = Font(bold=True, color='FFFFFFFF', size=9, name='Arial')
    ws.cell(row=row_num, column=1).fill = make_fill(HEADER_FILL)
    row_num += 1

    scenario_colors = {'Low': 'FFFFD700', 'Medium': 'FF90EE90', 'High': 'FFFFB6C1'}
    for scenario, factor in SCENARIOS.items():
        is_alt = row_num % 2 == 0
        cell = ws.cell(row=row_num, column=1, value=f'{scenario} ({factor:.0%})')
        cell.font = Font(bold=True, size=9, name='Arial')
        cell.fill = make_fill(scenario_colors[scenario])
        cell.border = border_thin()

        for p_idx in range(20):  # updated: 20
            total = sum(
                float(v) if pd.notna(v) else 0.0
                for antigen, vals in scenario_data[scenario].items()
                for i, v in enumerate([vals[p_idx]])
            )
            c = ws.cell(row=row_num, column=p_idx + 2, value=total)
            c.number_format = '#,##0'
            c.font = Font(size=9, name='Arial')
            c.fill = make_fill(scenario_colors[scenario])
            c.border = border_thin()
            c.alignment = Alignment(horizontal='right')
        row_num += 1

    ws.column_dimensions['A'].width = 22
    for i in range(2, 23):  # updated: 23 (covers 20 period columns)
        ws.column_dimensions[get_column_letter(i)].width = 16

    # Notes
    row_num += 2
    notes = [
        'Model Notes:',
        '• Demand = sum of projected supply capacity across all vaccine formats containing each antigen',
        '• Projections use weighted 5-year moving average with dampened linear trend extrapolation',
        '• Market shares applied per producer allocation table (sheet: Vaccine-Producer List)',
        '• Low scenario = Base × 0.85 | Medium = Base × 1.00 | High = Base × 1.15',
        '• Source data: Demand_Scenarios_Base.xlsx | Periods 1-20 = 2021-2040',  # updated
    ]
    for note in notes:
        cell = ws.cell(row=row_num, column=1, value=note)
        cell.font = Font(italic=(not note.endswith(':')), size=8, name='Arial',
                         bold=note.endswith(':'))
        cell.alignment = Alignment(wrap_text=True)
        ws.merge_cells(start_row=row_num, start_column=1, end_row=row_num, end_column=21)  # updated: 21
        row_num += 1
