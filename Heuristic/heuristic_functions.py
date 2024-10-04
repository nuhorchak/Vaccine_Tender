import pandas as pd
import numpy as np
# from collections import Counter
# from collections import defaultdict
from copy import deepcopy

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


# Function to search for a vaccine and return the diseases
def search_vaccine(vaccine, A_v_list, antigen):
    if vaccine in A_v_list:
        values = A_v_list[vaccine]
        print(f"this vaccine contains: {values}")
        if antigen in values:
            print(f"checking for {antigen} in {vaccine}")
            values.remove(antigen)
            print(f"removing antigen {antigen}")
            print(f"updated list is: {values}")
            if not values:
                return None
            else:
                return values
        else:
            print("Antigen not present")
            return None
    else:
        return f"Vaccine '{vaccine}' not found."
    
def build_tenders_partial_redux(antigen, interim_demand, capacity_data, inventory_DF, year, max_tender_length, total_price, price_data, V_a, P_v, tender_cost, A_v):
    # Initialize variables
    inventory_used = []
    new_tender = None

    # Validate year
    if year not in capacity_data.columns:
        print(f"Year {year} is not valid. Exiting function.")
        return {
            'New_Tender': None,
            'Message': "Invalid year",
        }

    # Loop over tender years
    for tender_year in range(year + 1, year + 1 + max_tender_length): 
        print(f"CHECKING YEAR: {tender_year} FOR CAPACITY!")
        
        # Validate antigen existence in interim_demand
        if antigen not in interim_demand['antigen'].tolist():
            raise ValueError(f"Antigen '{antigen}' not found in the list of antigens.")
        
        # Get antigen demand for the current year
        antigen_demand = interim_demand.loc[interim_demand['antigen'] == antigen, tender_year].iloc[0]
        starting_antigen_demand = deepcopy(antigen_demand)
        # print(f"the INTERIM DEMAND DF VALUE FOR demand for antigen {antigen} is {antigen_demand}")

        # print(f"Getting price list for vaccines with antigen: {antigen}?")   
        price_list = get_manufacturer_vaccine_price(antigen, price_data, V_a, P_v, tender_year)
        
        while price_list and antigen_demand > 0:
            A_v_list_new = deepcopy(A_v)
            A_v_list_new = dict(sorted(A_v_list_new.items(), key=lambda item: len(item[1]), reverse=True))
            entry = price_list.pop(0)
            manufacturer = entry['Manufacturer']
            # print(f"manufacturer: {manufacturer}")
            vaccine = entry['Vaccine']
            # print(f"vaccine: {vaccine}")
            price = entry['Price'] 

            # Get manufacturer capacity for the current tender year
            manufacturer_row = capacity_data[capacity_data['Manufacturer'] == manufacturer]
            if not manufacturer_row.empty:
                capacity = capacity_data.loc[capacity_data['Manufacturer'] == manufacturer, tender_year].iloc[0]
            else:
                raise ValueError(f"Manufacturer '{manufacturer}' not found in the list of manufacturers.")

            # Check if capacity can fulfill antigen demand
            if capacity > antigen_demand:
                # print("capacity > demand, total tender fill")
                #demand = 0
                interim_demand.loc[interim_demand['antigen']==antigen, tender_year] = 0
                
                
                #capacity - demand
                capacity_data.loc[capacity_data['Manufacturer']==manufacturer, tender_year] -= - antigen_demand
                #update inventory
                inventory_DF.loc[inventory_DF['Vaccine']==vaccine, 'Amount'] += antigen_demand
                #vax fulfilled
                vax_filled = {
                    'Manufacturer': manufacturer,
                    'Vaccine': vaccine,
                    'Doses': antigen_demand,
                    'Year': tender_year
                }
                # total price = demand * price
                total_price += antigen_demand * price
                #check for additional antigens in the vaccine in question!
                
                remaining_antigens = search_vaccine(vaccine, A_v_list_new, antigen)
                if remaining_antigens is not None:
                    # print(f"remaining antigens: {remaining_antigens}")
                    for ant in remaining_antigens:
                        # print(f"decermenting: {ant} from {interim_demand.loc[interim_demand['antigen']== ant, tender_year].iloc[0]} to {interim_demand.loc[interim_demand['antigen']== ant, tender_year].iloc[0] - antigen_demand}")
                        interim_demand.loc[interim_demand['antigen']== ant, tender_year] = max( interim_demand.loc[interim_demand['antigen']== ant, tender_year].iloc[0] - antigen_demand, 0)
                # else:
                #     print("No other antigens to update")
                
                antigen_demand = 0
                # print(f"updated demand is : {interim_demand.loc[interim_demand['antigen']==antigen, tender_year]}")

            elif capacity == antigen_demand:
                # print("cap = demand")
                #demand = 0
                interim_demand.loc[interim_demand['antigen']==antigen, tender_year] = 0
                
                
                #capacity = 0
                capacity_data.loc[capacity_data['Manufacturer']==manufacturer, tender_year] = 0
                #update inventory
                inventory_DF.loc[inventory_DF['Vaccine']==vaccine, 'Amount'] += antigen_demand
                #vax filled
                vax_filled = {
                    'Manufacturer': manufacturer,
                    'Vaccine': vaccine,
                    'Doses': antigen_demand,
                    'Year': tender_year
                }
                # total_price = price * antigen_demand
                total_price += antigen_demand * price
                remaining_antigens = search_vaccine(vaccine, A_v_list_new, antigen)
                if remaining_antigens is not None:
                    # print(f"remaining antigens: {remaining_antigens}")
                    for ant in remaining_antigens:
                        # print(f"decermenting: {ant} from {interim_demand.loc[interim_demand['antigen']== ant, tender_year].iloc[0]} to {interim_demand.loc[interim_demand['antigen']== ant, tender_year].iloc[0] - antigen_demand}")
                        interim_demand.loc[interim_demand['antigen']== ant, tender_year] = max( interim_demand.loc[interim_demand['antigen']== ant, tender_year].iloc[0] - antigen_demand, 0)
                # else:
                #     print("No other antigens to update")

                antigen_demand = 0
                # print(f"updated demand is : {interim_demand.loc[interim_demand['antigen']==antigen, tender_year]}")

            else:
                # print("capacity less than demand, cannot fulfill total demand")
                #demand - capacity
                interim_demand.loc[interim_demand['antigen']==antigen, tender_year] -= capacity

                #capacity = 0
                capacity_data.loc[capacity_data['Manufacturer']==manufacturer, tender_year] = 0
                #update inventory
                inventory_DF.loc[inventory_DF['Vaccine']==vaccine, 'Amount'] += capacity
                #vax fulfilled
                vax_filled = {
                    'Manufacturer': manufacturer,
                    'Vaccine': vaccine,
                    'Doses': antigen_demand,
                    'Year': tender_year -1
                }
                # total price = capacity * price
                total_price += capacity * price
                #check for additional antigens in the vaccine in question!
                remaining_antigens = search_vaccine(vaccine, A_v_list_new, antigen)
                if remaining_antigens is not None:
                    # print(f"remaining antigens: {remaining_antigens}")
                    for ant in remaining_antigens:
                        # print(f"decermenting: {ant} from {interim_demand.loc[interim_demand['antigen']== ant, tender_year].iloc[0]} to {interim_demand.loc[interim_demand['antigen']== ant, tender_year].iloc[0] - capacity}")
                        interim_demand.loc[interim_demand['antigen']== ant, tender_year] = max( interim_demand.loc[interim_demand['antigen']== ant, tender_year].iloc[0] - capacity, 0)
                # else:
                #     print("No other antigens to update")
                
                antigen_demand -= capacity
                # print(f"updated demand is : {interim_demand.loc[interim_demand['antigen']==antigen, tender_year]}")

            inventory_used.append(vax_filled)


        # if capacity remains, then we return partial tender, otherwise, demand was satisfied.
        if starting_antigen_demand == 0:
            # print('started with ZERO demand')
            new_tender = {
                'Antigen': antigen,
                'Starting': 0,
                'Ending': 0,
                'Fill': '0'
            }
            break
        elif antigen_demand > 0:
            # print(f"IN THE YEAR OF OUR LORD {tender_year}, WE SHALL NOT FULFILL DEMAND FULLY")
            new_tender = {
                'Antigen': antigen,
                'Starting': year,
                'Ending': tender_year,
                'Fill': 'Partial'
            }
            total_price += tender_cost
            break
        else:
            # print(f"Demand fulfilled in year {tender_year}")
            new_tender = {
                'Antigen': antigen,
                'Starting': year,
                'Ending': tender_year,
                'Fill': 'Full'
            }
            total_price += tender_cost
    new_tender_df = pd.DataFrame([new_tender])

    results = {
        'New_Tender': new_tender_df,
        'Inventory_Used': inventory_used,
        'Total_Price': total_price
        }

    return results