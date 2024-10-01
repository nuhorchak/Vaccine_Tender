import pandas as pd
import numpy as np
from collections import Counter
from collections import defaultdict

def get_manufacturer_vaccine_price(antigen, price_data, Vax_ant_dict, prod_vax_dict, year, find_lowest=False):
    """
    Retrieves a list of manufacturers, vaccines, and prices for a given antigen.

    This function identifies all vaccines that cover a specified antigen by looking 
    up the relevant vaccines in the `Vax_ant_dict` dictionary. It then matches these 
    vaccines to the corresponding manufacturers using the `prod_vax_dict` dictionary 
    and extracts the price information from the provided price data.

    Args:
        antigen (str): The antigen for which to retrieve manufacturer, vaccine, 
                       and price information (e.g., "Measles").
        price_data (dict): A dictionary containing price data with sheet names 
                           as keys (representing vaccines) and DataFrames as values. 
                           Each DataFrame should have a "Manufacturer" column and 
                           price columns.
        Vax_ant_dict (dict): A dictionary mapping antigens to vaccines that include 
                             that antigen.
        prod_vax_dict (dict): A dictionary mapping vaccines to their corresponding 
                              manufacturers.
        find_lowest (bool): If True, returns only the entry with the lowest price. 
                            Default is False.

    Returns:
        list or dict or None: A list of dictionaries, where each dictionary contains 
                              the following keys:
                              - 'Manufacturer': The name of the manufacturer.
                              - 'Vaccine': The name of the vaccine.
                              - 'Price': The price of the vaccine for the given 
                                         manufacturer.
                              If `find_lowest` is True, returns only the dictionary 
                              with the lowest price, or None if no prices are found.
    """
    if antigen not in Vax_ant_dict:
        return f"Antigen pricing not available for {antigen}"


    vaccines = Vax_ant_dict[antigen]
    result = []

    seen_combinations = set()

    for vaccine in vaccines:
        producers = prod_vax_dict[vaccine]
        
        for producer in producers:
            for sheet_name, df in price_data.items():
                if vaccine in sheet_name and producer in df['Manufacturer'].values:

                    if year >= len(df.columns):
                        print(f"Year {year} is out of bounds for the price data columns. Exiting function.")
                        return None

                    # Ensure each manufacturer-vaccine combination is only added once
                    combination = (producer, vaccine)
                    if combination not in seen_combinations:
                        price = df.loc[df['Manufacturer'] == producer, df.columns[year]].values[0]
                        result.append({"Manufacturer": producer, "Vaccine": vaccine, "Price": price})
                        seen_combinations.add(combination)
    
    if not result:
        return None
    
    # Sort the result by vaccine and then by price
    # sorted_result = sorted(result, key=lambda x: (x['Vaccine'], x['Price']))
    sorted_result = sorted(result, key=lambda x: (x['Price']))
    
    if find_lowest:
        return sorted_result[0]
    
    return sorted_result

def calculate_coverage_and_ratios(inventory_DF, demand_DF, V_a, year):
    """
    Calculates the total coverage of antigens based on vaccine inventory and computes 
    the supply-to-demand ratios for a given year.

    This function takes an inventory DataFrame and a demand DataFrame, along with a 
    dictionary mapping vaccines to antigens, and calculates the total antigen coverage 
    based on the inventory. It then merges this coverage data with the demand data 
    for the specified year to compute the ratio of supply to demand for each antigen.

    Args: 
        inventory_DF (pd.DataFrame): A DataFrame containing inventory data with columns 
                                     'Vaccine' and 'Amount', representing the vaccine 
                                     type and the quantity available.
        demand_DF (pd.DataFrame): A DataFrame containing demand data with the first 
                                  column representing antigens and subsequent columns 
                                  representing demand for each year.
        V_a (dict): A dictionary where keys are antigens and values are lists of vaccines 
                    that cover each antigen.
        year (int): The year for which to calculate the supply-to-demand ratio, referring 
                    to the column index in the demand DataFrame.

    Returns:
        tuple: A tuple containing two DataFrames:
            - calculate_ratios_DF (pd.DataFrame): A DataFrame with columns 'antigen', 
              'Total_Coverage', and 'Ratio', representing the supply-to-demand ratio for 
              each antigen.
            - total_coverage_df (pd.DataFrame): A DataFrame with columns 'antigen' and 
              'Total_Coverage', representing the total coverage of each antigen based 
              on the inventory data.
    """

    total_coverage = {antigen: 0 for antigen in V_a.keys()}

    # Iterate across each row in the inventory DataFrame
    for index, row in inventory_DF.iterrows():
        vaccine = row['Vaccine']
        amount = row['Amount']
        
        # For each antigen covered by the vaccine, add the amount to the coverage
        for antigen in V_a.keys():
            if vaccine in V_a[antigen]:
                total_coverage[antigen] += amount

    # Convert the total coverage dictionary to a DataFrame
    total_coverage_df = pd.DataFrame(list(total_coverage.items()), columns=['antigen', 'Total_Coverage'])
    # print(total_coverage_df)

    # Calculate ratio of supply and demand
    calculate_ratios_DF = pd.merge(demand_DF.iloc[:, [0, year]], total_coverage_df, left_on='antigen', right_on='antigen')
    # print(calculate_ratios_DF)
    # calculate_ratios_DF['Ratio'] = calculate_ratios_DF.apply(lambda row: 0 if row['Total_Coverage'] == 0 else row['Total_Coverage'] / row[year], axis=1)
    calculate_ratios_DF['Ratio'] = calculate_ratios_DF.apply(
    lambda row: 0 if row['Total_Coverage'] == 0 or row[year] == 0 else row['Total_Coverage'] / row[year], axis=1)


    return calculate_ratios_DF, total_coverage_df

def build_tenders_partial(antigen, interim_demand, capacity_data, inventory_DF, year, max_tender_length, total_price, A_v, antigen_list):
    tender_start = year
    # tender_end = 0
    new_tender = None
    if year not in capacity_data.columns:
        print(f"Year {year} is not valid. Exiting function.")
        return {
            'Inventory_Used': [],
            'Demand_Filled': 0,
            'Demand_unfilled': [],
            'Total_Price': total_price,
            'Message': "Invalid year",
        }

    for tender_year in range(year + 1, year + max_tender_length + 1): 
        print(f"CHECKING YEAR: {tender_year} FOR CAPACITY!")
        # Check the demand
        if antigen in interim_demand.iloc[:, 0].tolist():
            antigen_demand = interim_demand.loc[interim_demand['antigen'] == antigen, tender_year].iloc[0]
            starting_antigen_demand = interim_demand.loc[interim_demand['antigen'] == antigen, tender_year].iloc[0]
            print(f"antigen {antigen} demand: {antigen_demand} in year {tender_year}")
        else:
            raise ValueError(f"Antigen '{antigen}' not found in the list of antigens.")

        print(f"can we find supply enough for {antigen}?????")
        # for the antigen, is there supply of a vaccine that can cover it?
        price_list = get_manufacturer_vaccine_price(row.loc['antigen'], price_data, V_a, P_v, tender_year)

        #sort price list based on most coverage, to least coverage


        for entry in price_list: #tenders can cover partial demand, so we need to update for that and also for othe antigen demands filled
            print(f"ENTRY: {entry['Vaccine']}")
            manufacturer = entry['Manufacturer']
            vaccine = entry['Vaccine']
            price = entry['Price'] # need to track cost still

            #supply
            manufacturer_row = capacity_data[capacity_data['Manufacturer'] == manufacturer]
            if not manufacturer_row.empty:
                # capacity = manufacturer_row.iloc[0][year]
                capacity = capacity_data.loc[capacity_data['Manufacturer']==manufacturer, tender_year].iloc[0]
                print(f"Current capacity: {capacity} for {manufacturer}")
            else:
                raise ValueError(f"Manufacturer '{manufacturer}' not found in the list of manufacturers.")
                        
            # print(antigen_demand)
            if capacity > antigen_demand: #we need to update inventory based on teh vaccine, so that we cover all antigens in all vaccines tendered for
                interim_demand.loc[interim_demand['antigen'] == antigen, tender_year] = 0

                # capacity_data.loc[capacity_data['Manufacturer'] == manufacturer, year] = capacity_data.loc[capacity_data['Manufacturer'] == manufacturer, tender_year].iloc[0] - antigen_demand
                capacity_data.loc[capacity_data['Manufacturer'] == manufacturer, year] = max(capacity_data.loc[capacity_data['Manufacturer'] == manufacturer, tender_year].iloc[0] - antigen_demand, 0)
                print(f"! Updated {antigen} demand: {interim_demand.loc[interim_demand['antigen'] == antigen, tender_year].iloc[0]}")
                inventory_DF.loc[inventory_DF['Vaccine'] == vaccine, 'Amount'] += antigen_demand
                break
            else:
                interim_demand.loc[interim_demand['antigen'] == antigen, tender_year] = max(interim_demand.loc[interim_demand['antigen'] == antigen, tender_year].iloc[0] - capacity, 0)

                print(f"Modified {antigen} demand: {interim_demand.loc[interim_demand['antigen'] == antigen, tender_year].iloc[0]}")
                capacity_data.loc[capacity_data['Manufacturer'] == manufacturer, tender_year] = 0
                inventory_DF.loc[inventory_DF['Vaccine'] == vaccine, 'Amount'] += capacity

                

        if interim_demand.loc[interim_demand['antigen'] == antigen, tender_year].iloc[0] == 0:
            # no tender for this year
            print(f"Year {tender_year}: Demand fully met.")
            new_tender = {
                'Antigen': antigen,
                'Starting': tender_start,
                'Ending': tender_year +1
            }
        elif starting_antigen_demand > interim_demand.loc[interim_demand['antigen'] == antigen, tender_year].iloc[0]:
            # tender
            print(f"Year {tender_year}: Demand partially met.")
            new_tender = {
                'Antigen': antigen,
                'Starting': tender_start,
                'Ending': tender_year +1
            }
        else:
            print(f"Year {tender_year}: Demand Not Met")
            new_tender = None
            break
            
        if new_tender is not None:
            new_tender = pd.DataFrame([new_tender])



    return new_tender