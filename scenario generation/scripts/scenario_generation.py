
import sys
from typing import Tuple
code_path = "C:/Users/nicho/OneDrive/Desktop/Vaccine_Tender/Github/Vaccine_Tender/scenario generation"

if code_path not in sys.path:
    sys.path.insert(0, code_path)
    
from scripts.default_import import *

def generate_time_series(
    df: pd.DataFrame,
    n: int,
    years: np.ndarray = np.arange(1, 11),
    mu_col: str = "mu",
    std_col: str = "std",
    lower_col: str = "lower",
    upper_col: str = "upper",
) -> pd.DataFrame:
    # Prepare a DataFrame to store the results
    ts = pd.DataFrame(index=range(n), columns=years)

    # Generate random values for each year
    for year in years:
        # Extract the mean and standard deviation for the year
        mu = df.loc[year, mu_col]
        sigma = df.loc[year, std_col]
        lower_bound = df.loc[year, lower_col]
        upper_bound = df.loc[year, upper_col]

        # Generate random values from a normal distribution with the given mean and standard deviation
        values = np.random.normal(mu, sigma, n)
        # Clip the values to the lower and upper bounds
        # capped_values = np.clip(values, max(lower_bound,0), upper_bound)
        capped_values = np.where(values < 0, max(lower_bound, 0), values)
        capped_values = np.where(capped_values > upper_bound, upper_bound, capped_values)
        # Store the values in the DataFrame
        ts[year] = capped_values

    # Assign scenario index
    ts["sid"] = ts.index + 1
    # Assign equal probabilities to each scenario
    ts["prob"] = 1 / n
    return ts


def roulette_wheel_selection(df: pd.DataFrame, verbose: bool = True) -> Tuple[pd.DataFrame, float]:
    portfolio = {}
    #  Create a random number generator
    rng = np.random.default_rng()
    for antigen, antigen_data in df.groupby("antigen"):
        probabilities = antigen_data["probability"].tolist()
        # Select a random index based on the probabilities
        selected_idx = rng.choice(antigen_data.index, size=1, p=probabilities)
        # Get the demand, probability, and sid of the selected scenario
        selected_demand = antigen_data.loc[selected_idx, "demand"].values[0]
        selected_probability = antigen_data.loc[selected_idx, "probability"].values[0]
        selected_sid = antigen_data.loc[selected_idx, "sid"].values[0]
        print(f"Selected {selected_sid} with probability {selected_probability:.1%}") if verbose else None
        portfolio[antigen] = {"demand": selected_demand, "probability": selected_probability, "sid": selected_sid}
    portfolio_df = pd.DataFrame.from_dict(portfolio, orient="index").reset_index()
    combined_prob = portfolio_df["probability"].prod()
    return portfolio_df, combined_prob


def create_portfolios(df: pd.DataFrame, n_scenarios: int, verbose: bool = True):
    demand_scenarios = []
    prob_dict = {}
    for i in range(n_scenarios):
        print(f"Creating demand scenario {i+1}...") if verbose else None
        demand_scenario, prob = roulette_wheel_selection(df, verbose=verbose)
        demand_scenario["demand_scenario"] = i + 1
        demand_scenarios.append(demand_scenario)
        prob_dict[i + 1] = prob
        
    demand_scenario_df = pd.concat(demand_scenarios, ignore_index=True)
    demand_scenario_df.rename(columns={"index": "antigen"}, inplace=True)
    # Calculate the sum of all probabilities
    total_sum = sum(prob_dict.values())
    # Scale the probabilities so they sum up to 1
    scaled_probabilities = {k: v / total_sum for k, v in prob_dict.items()}
    demand_scenario_df["demand_scenario_probability"] = demand_scenario_df["demand_scenario"].map(scaled_probabilities)
    
    return demand_scenario_df


def combine_reduced_scenarios(reduce_dict: dict, years:int=np.arange(1, 11)) -> pd.DataFrame:
    # Combine all the reduced scenarios of all antigens into one dataframe
    reduced_dfs = []
    for antigen in ANTIGENS:
        temp = reduce_dict[antigen]
        temp_df = pd.DataFrame(temp["scenarios_Q"], columns=years)
        temp_df["demand"] = temp_df[years].values.tolist()
        temp_df["probability"] = temp["probabilities_Q"]
        temp_df["antigen"] = antigen
        temp_df["sid"] = [f"{antigen}_S{i+1}" for i in temp_df.index]
        temp_df.drop(years, axis=1, inplace=True)
        reduced_dfs.append(temp_df)

    reduced_df = pd.concat(reduced_dfs, ignore_index=True)
    return reduced_df
