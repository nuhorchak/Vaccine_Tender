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
    calculate_ratios_DF['Ratio'] = calculate_ratios_DF.apply(lambda row: 0 if row['Total_Coverage'] == 0 else row['Total_Coverage'] / row[year], axis=1)


    # print(f"Ratio DF:\n{calculate_ratios_DF[['antigen', 'Ratio']]}")

    return calculate_ratios_DF, total_coverage_df

def fulfill_demand(vaccine_price_list, antigen, interim_demand, manufacturer_capacities_df, inventory_DF, year, total_price, A_v): #add total price to track
    # Create a copy of the demand DataFrame to work with
    # interim_demand = interim_demand_DF

    # Check if the given year exists in the DataFrame
    if year not in manufacturer_capacities_df.columns:
        raise KeyError(f"Year {year} is not a valid column in the manufacturer capacities DataFrame.")
    
    # Sort the list by price to ensure we start with the lowest price - this is a techincal re-sort, since the initial list is sorted alredy
    vaccine_price_list.sort(key=lambda x: x['Price'])
    
    # Initialize variables
    total_demand_filled = 0
    demand_unfilled = []
    # message = ["None"]
    inventory_used = []

    for entry in vaccine_price_list: 
        print(f"ENTRY: {entry['Vaccine']}")
        manufacturer = entry['Manufacturer']
        vaccine = entry['Vaccine']
        price = entry['Price']

        manufacturer_row = manufacturer_capacities_df[manufacturer_capacities_df['Manufacturer'] == manufacturer]
        if not manufacturer_row.empty:
            capacity = manufacturer_row.iloc[0][year+1]
            # print(f"Current capacity: {capacity} for {manufacturer}")
        else:
            raise ValueError(f"Manufacturer '{manufacturer}' not found in the list of manufacturers.")
        
        # Check the demand for the current vaccine in interim_demand
        if antigen in interim_demand.iloc[:, 0].tolist():
            antigen_demand = interim_demand.loc[interim_demand['antigen'] == antigen, year + 1].iloc[0]
            print(f"antigen {antigen} demand: {antigen_demand}")
        else:
            raise ValueError(f"Antigen '{antigen}' not found in the list of antigens.")
        
        if antigen_demand == 0: #stop checking if demand is satisfied
            break
        

        if capacity > 0 and antigen_demand >0:
            print("Winning")
            pairs = {'antigen_demand': antigen_demand, 'producer_capacity': capacity}
            # print(pairs)
            min_key = min(pairs, key=pairs.get)
            amount_to_fill = pairs[min_key]
            print(f"Amount to fill: {amount_to_fill}, from {min_key}")
            #update interim_demand for antigen
            # print(f"previous interim {antigen} demand: {interim_demand.loc[interim_demand['antigen'] == antigen, year+1].iloc[0]}")
            interim_demand.loc[interim_demand['antigen'] == antigen, year+1] -= amount_to_fill
            # print(f"updated interim {antigen} demand: {interim_demand.loc[interim_demand['antigen'] == antigen, year+1].iloc[0]}")
            # print("Updating other antigen future demand for year + 1")
            antigens = A_v.get(vaccine, [])
            if antigen in antigens:
                antigens.remove(antigen)
            else:
                continue
            # print(f"other antigens: {antigens}")
            for ant in antigens:
                interim_demand.loc[interim_demand['antigen'] == ant, year+1] -= amount_to_fill
                # print(f"updating demand for {ant}")
                # print(f"updated interim {ant} demand: {interim_demand.loc[interim_demand['antigen'] == ant, year+1].iloc[0]}")
            dict = {manufacturer: amount_to_fill}
            inventory_used.append(dict) #used for reporting and charting post run
            total_demand_filled += amount_to_fill
            total_price += amount_to_fill * price
            #inventory year + 1 + AMOUNT_TO_FILL
            inventory_DF.loc[inventory_DF['Vaccine']==vaccine, 'Amount'] += amount_to_fill
            #capacity year + 1 - amount_to_fill
            manufacturer_capacities_df.loc[manufacturer_capacities_df['Manufacturer']==manufacturer, year + 1] -= amount_to_fill
    message = ["Demand fully fulfilled" if interim_demand.loc[interim_demand['antigen'] == antigen, year+1].iloc[0] == 0 else f"Demand not fully fulfilled"] 

    #need to return the following items here:
    #I need to return the interim_demand somehow to update the interim_demand_DF outside this function
    return {
    'Inventory_Used': inventory_used,
    'Demand_Filled': total_demand_filled,
    'Demand_unfilled': demand_unfilled,
    'Total_Price': total_price,
    # 'Details': details,
    'Message': message
    }

#I need to figure out lexicographical scoping of variables to make this work