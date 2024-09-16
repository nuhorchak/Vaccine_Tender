import pandas as pd
import numpy as np
from collections import Counter
from collections import defaultdict

# Load demand data
demand_path = 'data/real/antigen_demand_80_20_2_scenarios.csv'
data = pd.read_csv(demand_path)
# Create the two dataframes based on the 'prob' column
demand_80 = data[data['prob'] == 0.8]
demand_80 = demand_80.drop(columns=['prob', 'demand_SID'])
# Expanding the 'demands' column into 10 separate columns
demand_80_expanded = demand_80['demands'].apply(lambda x: pd.Series(eval(x)))
# Renaming the columns to 1-10
demand_80_expanded.columns = range(1, 11)
# Concatenating the expanded demands columns back to the original antigen column
demand_80_final = pd.concat([demand_80['antigen'], demand_80_expanded], axis=1)
#added 11th year to capture any left overdemand at the end of year 10.
demand_80_final[11] = 0.1

file_path = 'data/real/Starting_point.xlsx'

# Load the sheets 'F_start', 'I_start', 'S_start' into their own DataFrames
f_start = pd.read_excel(file_path, sheet_name='F_start')
i_start = pd.read_excel(file_path, sheet_name='I_start')
s_start = pd.read_excel(file_path, sheet_name='S_start')

# Load the Excel file, skipping the first two sheets
money_path = 'data/Vaccine_price_data.xlsx'
sheet_names = pd.ExcelFile(money_path).sheet_names

# Load the remaining sheets into a dictionary of DataFrames
# data = {sheet: pd.read_excel(file_path, sheet_name=sheet) for sheet in sheet_names[2:5]}
price_data = {sheet_names[i]: pd.read_excel(money_path, sheet_name=i).rename(columns=lambda x: "Manufacturer" if x == pd.read_excel(money_path, sheet_name=i).columns[0] else x) for i in range(2, 5)}

# Load the Excel file, only reading the first sheet
capacity_path = 'data/production_capacity_scenarios.xlsx'
sheet_names = pd.ExcelFile(capacity_path).sheet_names

capacity_data = pd.read_excel(capacity_path, sheet_name='base_capacity')
# capacity_data

#tender length
delta = 3
vaccine_consumption_percent = 1
years = 10

# Creating an empty DataFrame with the specified structure for calculating ratios
antigens = f_start['Antigen']
columns = ['Antigen',1]

ratio_DF = pd.DataFrame(columns=columns)
ratio_DF['Antigen'] = antigens
ratio_DF[1] = np.zeros(len(antigens))

# create DF to store tender schedule
tender_schedules = f_start.copy()

########################################################
#create DF to store current inventory
inventory_DF = i_start.copy()
##########################################################
#create DF to store missed doses
antigens = f_start['Antigen']
columns = ['Antigen','Missed Doses']

missed_doses = pd.DataFrame(columns=columns)
missed_doses['Antigen'] = antigens
missed_doses['Missed Doses'] = np.zeros(len(antigens))

#CREATE TO STORE VACCINES "PURCHASED" THROUGH TENDERS
vaccine_purchases = defaultdict(list)

#tender length
delta = 3
vaccine_consumption_percent = 1
years = 10

# Creating an empty DataFrame with the specified structure for calculating ratios
antigens = f_start['Antigen']
columns = ['Antigen',1]

ratio_DF = pd.DataFrame(columns=columns)
ratio_DF['Antigen'] = antigens
ratio_DF[1] = np.zeros(len(antigens))

# create DF to store tender schedule
tender_schedules = f_start.copy()

########################################################
#create DF to store current inventory
inventory_DF = i_start.copy()
##########################################################
#create DF to store missed doses
antigens = f_start['Antigen']
columns = ['Antigen','Missed Doses']

missed_doses = pd.DataFrame(columns=columns)
missed_doses['Antigen'] = antigens
missed_doses['Missed Doses'] = np.zeros(len(antigens))

#CREATE TO STORE VACCINES "PURCHASED" THROUGH TENDERS
vaccine_purchases = defaultdict(list)

A = ["Measles", "Mumps", "Rubella"]
V = ["M", "MR", "MMR"]

A_v = {
    "M": ["Measles"],
    "MR": ["Measles", "Rubella"],
    "MMR": ["Measles", "Mumps", "Rubella"]
}

P = ["Biological_E", 
    "GSK","PT_Bio", 
    "Serum_Institute"
]

P_v = {
    "M": ["Serum_Institute", "PT_Bio"],
    "MR": ["Serum_Institute", "Biological_E"],
    "MMR": ["Serum_Institute", "GSK"]
}

P_v = {
    "M": ["Serum_Institute", "PT_Bio"],
    "MR": ["Serum_Institute", "Biological_E"],
    "MMR": ["Serum_Institute", "GSK"]
}


#translate vaccine - antigen, to antigen - vaccine
V_a = {a: [v for v in A_v if a in A_v[v]] for a in A}

V_p = {p: [v for v in P_v if p in P_v[v]] for p in P}

P_a = {a: list(set(p for v in V_a[a] for p in P_v[v])) for a in A}

A_p = {p: [a for a in P_a if p in P_a[a]] for p in P}