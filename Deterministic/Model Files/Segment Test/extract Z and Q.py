import json
import os
import re
from pathlib import Path
import pandas as pd

def read_mvp_files(folder_path):
    """
    Read all JSON files matching the MVP_DE_results naming pattern.
    
    Args:
        folder_path: Path to the folder containing JSON files
        
    Returns:
        List of dictionaries containing filename, parameters, and data
    """
    # Define the regex pattern for the filename
    pattern = r'MVP_DE_results_T_(\d+)_delta_(\d+)_scen_(\d+)_trial_(\d+)_inv_(\d+)_cap\._(\d+)_cap\.inc\._(\d+)\.json'
    
    results = []
    folder = Path(folder_path)
    
    # Iterate through all files in the folder
    for file_path in folder.glob('*.json'):
        filename = file_path.name
        
        # Check if filename matches the pattern and extract parameters
        match = re.match(pattern, filename)
        if match:
            try:
                with open(file_path, 'r') as f:
                    data = json.load(f)
                    results.append({
                        'filename': filename,
                        'filepath': str(file_path),
                        'T': int(match.group(1)),
                        'delta': int(match.group(2)),
                        'scenario': int(match.group(3)),
                        'trial': int(match.group(4)),
                        'inv': int(match.group(5)),
                        'cap': int(match.group(6)),
                        'cap_inc': int(match.group(7)),
                        'data': data
                    })
                print(f"Successfully loaded: {filename}")
            except Exception as e:
                print(f"Error loading {filename}: {e}")
    
    return results

def extract_z_to_dataframe(z_data):
    """
    Convert Z data to a dataframe.
    Z is indexed as Z[vaccine][producer][time][segment]
    
    Args:
        z_data: Dictionary containing Z data
        
    Returns:
        DataFrame with columns: vaccine, producer, time, segment, Z_value
    """
    rows = []
    
    for vaccine, producers in z_data.items():
        for producer, times in producers.items():
            for time, segments in times.items():
                for segment, value in segments.items():
                    rows.append({
                        'vaccine': vaccine,
                        'producer': producer,
                        'time': int(time),
                        'segment': int(segment),
                        'Z_value': value
                    })
    
    return pd.DataFrame(rows)

def extract_q_to_dataframe(q_data):
    """
    Convert Q data to a dataframe.
    Q is indexed as Q[vaccine][producer][start_time][end_time][segment]
    
    Args:
        q_data: Dictionary containing Q data
        
    Returns:
        DataFrame with columns: vaccine, producer, start_time, end_time, segment, Q_value
    """
    rows = []
    
    for vaccine, producers in q_data.items():
        for producer, start_times in producers.items():
            for start_time, end_times in start_times.items():
                for end_time, segments in end_times.items():
                    for segment, value in segments.items():
                        rows.append({
                            'vaccine': vaccine,
                            'producer': producer,
                            'start_time': int(start_time),
                            'end_time': int(end_time),
                            'segment': int(segment),
                            'Q_value': value
                        })
    
    return pd.DataFrame(rows)

def merge_z_q_dataframes(z_df, q_df):
    """
    Merge Z and Q dataframes on vaccine, producer, and time.
    Merges where Z['time'] = Q['start_time']
    
    Args:
        z_df: DataFrame with Z data
        q_df: DataFrame with Q data
        
    Returns:
        Merged DataFrame
    """
    # Rename start_time to time in Q dataframe for merging
    q_df_renamed = q_df.rename(columns={'start_time': 'time'})
    
    # Merge on vaccine, producer, time, and segment
    merged_df = pd.merge(
        z_df,
        q_df_renamed,
        on=['vaccine', 'producer', 'time', 'segment'],
        how='outer'
    )
    
    return merged_df

def process_all_files(folder_path):
    """
    Process all files and create merged dataframes per trial.
    
    Args:
        folder_path: Path to the folder containing JSON files
        
    Returns:
        Dictionary mapping trial number to merged dataframe
    """
    # Read all files
    results = read_mvp_files(folder_path)
    
    if not results:
        print("No matching files found!")
        return {}
    
    # Group by trial number
    trial_dataframes = {}
    
    for result in results:
        trial_num = result['trial']
        data = result['data']
        
        # Extract Z and Q data
        z_data = data.get('Z', {})
        q_data = data.get('Q', {})
        
        if not z_data and not q_data:
            print(f"Warning: No Z or Q data found in {result['filename']}")
            continue
        
        # Convert to dataframes
        z_df = extract_z_to_dataframe(z_data) if z_data else pd.DataFrame()
        q_df = extract_q_to_dataframe(q_data) if q_data else pd.DataFrame()
        
        # Merge dataframes
        if not z_df.empty and not q_df.empty:
            merged_df = merge_z_q_dataframes(z_df, q_df)
        elif not z_df.empty:
            merged_df = z_df
        elif not q_df.empty:
            merged_df = q_df
        else:
            continue
        
        # Add metadata columns
        merged_df['trial'] = trial_num
        merged_df['T'] = result['T']
        merged_df['delta'] = result['delta']
        merged_df['scenario'] = result['scenario']
        merged_df['inv'] = result['inv']
        merged_df['cap'] = result['cap']
        merged_df['cap_inc'] = result['cap_inc']
        merged_df['filename'] = result['filename']
        
        trial_dataframes[trial_num] = merged_df
        
        print(f"\nTrial {trial_num}: {len(merged_df)} rows")
        print(f"  Columns: {list(merged_df.columns)}")
    
    return trial_dataframes

def analyze_merged_data(trial_dataframes):
    """
    Provide summary statistics for merged dataframes.
    
    Args:
        trial_dataframes: Dictionary of trial number to dataframe
    """
    print("\n" + "="*70)
    print("MERGED DATA SUMMARY")
    print("="*70)
    
    for trial_num, df in trial_dataframes.items():
        print(f"\n--- Trial {trial_num} ---")
        print(f"Total rows: {len(df)}")
        print(f"Unique vaccines: {df['vaccine'].nunique()}")
        print(f"Unique producers: {df['producer'].nunique()}")
        print(f"Time range: {df['time'].min()} to {df['time'].max()}")
        print(f"\nFirst few rows:")
        print(df.head())
        print(f"\nData types:")
        print(df.dtypes)

# Example usage
if __name__ == "__main__":
    # Specify your folder path here
    script_dir = os.path.dirname(os.path.abspath(__file__))
    folder_path = os.path.join(script_dir, "results/2 segments/UG")

    # Process all files
    print("Processing files...")
    trial_dfs = process_all_files(folder_path)
    
    if trial_dfs:
        # Analyze the merged data
        analyze_merged_data(trial_dfs)
        
        # Example: Access specific trial data
        print("\n" + "="*70)
        print("EXAMPLE: Accessing Trial Data")
        print("="*70)
        
        # Get data for trial 1
        if 1 in trial_dfs:
            trial_1_df = trial_dfs[1]
            print(f"\nTrial 1 data shape: {trial_1_df.shape}")
            
            # Example: Filter for specific vaccine and producer
            pcv_pfizer = trial_1_df[
                (trial_1_df['vaccine'] == 'PCV') & 
                (trial_1_df['producer'] == 'Pfizer')
            ]
            print(f"\nPCV from Pfizer: {len(pcv_pfizer)} rows")
            
            # Save to CSV (optional)
            trial_1_df.to_csv('trial_1_data.csv', index=False)