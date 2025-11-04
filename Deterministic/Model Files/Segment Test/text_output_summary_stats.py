import pandas as pd
import numpy as np
import re
from typing import Dict, List, Tuple
import os 

unit = 1000

def parse_objective_values(file_path: str) -> List[Dict]:
    # read bytes and try sensible decodings (handles UTF-16 BOM files)
    with open(file_path, "rb") as fb:
        b = fb.read()
    for enc in ("utf-8", "utf-8-sig", "utf-16", "utf-16-le", "utf-16-be", "cp1252", "latin-1"):
        try:
            text = b.decode(enc)
            break
        except Exception:
            text = None
    if text is None:
        text = b.decode("utf-8", errors="replace")

    lines = text.splitlines()
    trial_blocks = []
    current_trial = None
    objective_values = {}

    pattern_trial = re.compile(r'\btrial:\s*(\d+)', re.IGNORECASE)
    pattern_obj = re.compile(
        r'^(?:Manual calculation of the objective value function:)?\s*'
        r'([FQSILY]|Total)\s+Objective value:\s*([\d.+eE-]+)',
        re.IGNORECASE
    )

    for line in lines:
        s = line.strip()

        # detect trial number
        tm = pattern_trial.search(s)
        if tm:
            if current_trial is not None and objective_values:
                trial_blocks.append({'trial': current_trial, **objective_values})
            current_trial = int(tm.group(1))
            objective_values = {}
            continue

        # detect objective lines
        om = pattern_obj.search(s)
        if om:
            key, val = om.groups()
            try:
                objective_values[key] = float(val)
            except ValueError:
                # tolerate weird formatting by replacing commas etc.
                objective_values[key] = float(val.replace(",", "").strip())

    # append final trial
    if current_trial is not None and objective_values:
        trial_blocks.append({'trial': current_trial, **objective_values})

    return trial_blocks


def calculate_statistics(trials_data: List[Dict], unit) -> pd.DataFrame:
    """
    Calculate summary statistics for objective function values.
    
    Parameters:
    -----------
    trials_data : List[Dict]
        List of dictionaries containing trial data
    
    Returns:
    --------
    pd.DataFrame
        DataFrame with summary statistics (mean, min, max, std, count)
    """
    if not trials_data:
        return pd.DataFrame()
    
    # Convert to DataFrame
    df = pd.DataFrame(trials_data)
    
    # Get all objective columns (exclude 'trial' column)
    obj_columns = [col for col in df.columns if col != 'trial']
    
    # Calculate statistics
    stats = []
    for col in obj_columns:
        values = df[col].dropna()
        stats.append({
            'OBJ Component': col,
            'Mean': values.mean() * unit,
            'Min_Lower': values.min() * unit,
            'Max_Upper': values.max() * unit,
            'Std_Dev': values.std() * unit
        })
    
    stats_df = pd.DataFrame(stats)
    
    # Set Component as index for better readability
    # stats_df.set_index('OBJ Component', inplace=True)
    
    return stats_df


def analyze_objective_functions(file_path: str) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """
    Complete analysis pipeline: parse file and calculate statistics.
    
    Parameters:
    -----------
    file_path : str
        Path to the output text file
    
    Returns:
    --------
    Tuple[pd.DataFrame, pd.DataFrame]
        - trials_df: DataFrame with all trial data
        - stats_df: DataFrame with summary statistics
    """
    # Parse the file
    trials_data = parse_objective_values(file_path)
    
    # Create trials DataFrame
    trials_df = pd.DataFrame(trials_data)
    
    # Calculate statistics
    stats_df = calculate_statistics(trials_data, unit)
    
    return trials_df, stats_df


def format_dataframe_display(df: pd.DataFrame, scientific_notation: bool = True) -> pd.DataFrame:
    """
    Format DataFrame for better display with scientific notation for large numbers.
    
    Parameters:
    -----------
    df : pd.DataFrame
        DataFrame to format
    scientific_notation : bool
        Whether to use scientific notation for large numbers
    
    Returns:
    --------
    pd.DataFrame
        Formatted DataFrame (returns a copy)
    """
    df_copy = df.copy()
    
    if scientific_notation:
        # Format numeric columns with scientific notation for values > 1e6
        numeric_cols = df_copy.select_dtypes(include=[np.number]).columns
        for col in numeric_cols:
            df_copy[col] = df_copy[col].apply(
                lambda x: f'{x:.4e}' if abs(x) >= 1e6 else f'{x:.2f}'
            )
    
    return df_copy


# Example usage
if __name__ == "__main__":
    # Path to your file

    script_dir = os.path.dirname(os.path.abspath(__file__))
    file_path = os.path.join(script_dir, "results/2 segments/MP/MP_output_2_segments.txt")
    
    # Run analysis
    trials_df, stats_df = analyze_objective_functions(file_path)
    
    # Display results
    print("=" * 80)
    print("TRIAL DATA")
    print("=" * 80)
    print(f"\nFound {len(trials_df)} trials\n")
    print(trials_df.to_string(index=False))
    
    print("\n" + "=" * 80)
    print("SUMMARY STATISTICS")
    print("=" * 80)
    print("\n")
    print(stats_df)
    
    # Optional: Save to CSV
    prefix = "MP_2_segments_"

    trials_df.to_csv(os.path.join(script_dir, f"{prefix}trials_data.csv"), index=False)
    stats_df.to_csv(os.path.join(script_dir, f"{prefix}summary_statistics.csv"), index=False)


    
    print("\n" + "=" * 80)
    print("Files saved:")
    print("  - trials_data.csv")
    print("  - summary_statistics.csv")
    print("=" * 80)