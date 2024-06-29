import numpy as np
import pandas as pd


def generate_time_series(df: pd.DataFrame, n: int, years: np.ndarray = np.arange(1, 11), mu_col: str = "mu", std_col: str = "std", lower_col: str = "lower", upper_col: str = "upper") -> pd.DataFrame:
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
        capped_values = np.clip(values, lower_bound, upper_bound)
        # Store the values in the DataFrame
        ts[year] = capped_values
        
    # Assign scenario index 
    ts["sid"] = ts.index + 1
    # Assign equal probabilities to each scenario
    ts["prob"] = 1 / n
    return ts
