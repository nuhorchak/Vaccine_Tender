import re
import matplotlib.pyplot as plt
import numpy as np
import os

def parse_objectives(filename):
    """
    Parse objective values from file.
    Returns a dictionary with trial numbers as keys and objective dictionaries as values.
    """
    # Read bytes and try sensible decodings (handles UTF-16 BOM files)
    with open(filename, "rb") as fb:
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
    trials = {}
    current_trial = None
    
    pattern_trial = re.compile(r'\btrial:\s*(\d+)', re.IGNORECASE)
    pattern_obj = re.compile(
        r'^(?:Manual calculation of the objective value function:)?\s*'
        r'([FQSI]|Total)\s+Objective value:\s*([\d.+eE-]+)',
        re.IGNORECASE
    )
    
    for line in lines:
        s = line.strip()
        
        # Detect trial number
        tm = pattern_trial.search(s)
        if tm:
            current_trial = int(tm.group(1))
            trials[current_trial] = {}
            continue
        
        # Detect objective lines
        if current_trial is not None:
            om = pattern_obj.search(s)
            if om:
                key, val = om.groups()
                try:
                    trials[current_trial][key] = float(val)
                except ValueError:
                    # Tolerate weird formatting by replacing commas etc.
                    trials[current_trial][key] = float(val.replace(",", "").strip())
    
    return trials

def is_pareto_efficient(costs):
    """
    Find the Pareto efficient points (minimization).
    costs: An (n_points, n_costs) array
    Returns: A boolean array indicating which points are Pareto efficient
    """
    is_efficient = np.ones(costs.shape[0], dtype=bool)
    for i, c in enumerate(costs):
        if is_efficient[i]:
            # Remove dominated points
            is_efficient[is_efficient] = np.any(costs[is_efficient] < c, axis=1)
            is_efficient[i] = True
    return is_efficient


def plot_pareto_frontiers(trials):
    """
    Plot Pareto frontier for each objective value with improved formatting.
    """
    objectives = ['F', 'Q', 'S', 'I', 'Total']
    
    # Extract data
    trial_nums = sorted(trials.keys())
    data = {obj: [] for obj in objectives}
    
    for trial in trial_nums:
        for obj in objectives:
            if obj in trials[trial]:
                data[obj].append(trials[trial][obj])
            else:
                data[obj].append(None)
    
    # Create subplots
    fig, axes = plt.subplots(3, 3, figsize=(18, 14))
    axes = axes.flatten()
    
    for idx, obj in enumerate(objectives):
        ax = axes[idx]
        values = [v for v in data[obj] if v is not None]
        trial_indices = [i for i, v in enumerate(data[obj]) if v is not None]
        
        if not values:
            ax.set_title(f'{obj} Objective - No Data', fontsize=14, fontweight='bold')
            continue
        
        # Sort by trial number for plotting
        sorted_pairs = sorted(zip(trial_indices, values))
        x_vals = [p[0] + 1 for p in sorted_pairs]  # Trial numbers (1-indexed)
        y_vals = [p[1] for p in sorted_pairs]
        
        # Plot all points
        ax.scatter(x_vals, y_vals, alpha=0.6, s=80, label='All trials', color='#3498db')
        
        # Find and highlight Pareto frontier (minimization)
        if len(values) > 1:
            costs = np.column_stack([x_vals, y_vals])
            pareto_mask = is_pareto_efficient(costs)
            pareto_x = np.array(x_vals)[pareto_mask]
            pareto_y = np.array(y_vals)[pareto_mask]
            
            # Sort Pareto points for line plotting
            pareto_sorted = sorted(zip(pareto_x, pareto_y))
            pareto_x_sorted = [p[0] for p in pareto_sorted]
            pareto_y_sorted = [p[1] for p in pareto_sorted]
            
            ax.scatter(pareto_x_sorted, pareto_y_sorted, color='#e74c3c', s=150, 
                      marker='*', label='Pareto frontier', zorder=5, edgecolors='darkred', linewidths=1.5)
            ax.plot(pareto_x_sorted, pareto_y_sorted, color='#e74c3c', linestyle='--', 
                   alpha=0.7, linewidth=2.5)
        
        # Format axes
        ax.set_xlabel('Trial Number', fontsize=12, fontweight='bold')
        ax.set_ylabel('Objective Value (×10⁸)', fontsize=12, fontweight='bold')
        ax.set_title(f'{obj} Objective', fontsize=14, fontweight='bold', pad=10)
        
        # Scale Y-axis to e8 (divide by 1e8)
        y_ticks = ax.get_yticks()
        ax.set_yticklabels([f'{tick/1e8:.2f}' for tick in y_ticks])
        
        # Alternatively, use scientific notation formatter
        from matplotlib.ticker import FuncFormatter
        def format_e8(x, pos):
            return f'{x/1e8:.2f}'
        ax.yaxis.set_major_formatter(FuncFormatter(format_e8))
        
        # Improve X-axis
        ax.set_xlim(left=0, right=max(x_vals) + 1)
        ax.xaxis.set_major_locator(plt.MaxNLocator(integer=True, nbins=10))
        
        # Styling
        ax.legend(loc='best', fontsize=10, framealpha=0.9)
        ax.grid(True, alpha=0.3, linestyle='--', linewidth=0.8)
        ax.spines['top'].set_visible(False)
        ax.spines['right'].set_visible(False)
        ax.tick_params(labelsize=10)
    
    # Hide extra subplots
    for idx in range(len(objectives), len(axes)):
        axes[idx].axis('off')
    
    fig.suptitle('Pareto Frontiers for Balance Model - Varying Discounts to Manufacturers of Hexa/Penta', fontsize=16, fontweight='bold', y=0.995)
    plt.tight_layout(pad=2.0)
    plt.savefig('pareto_frontiers.png', dpi=300, bbox_inches='tight')
    plt.show()
    
    return data

import pandas as pd

def create_objectives_dataframe(trials):
    """
    Create a pandas DataFrame from the trials dictionary.
    
    Parameters:
    -----------
    trials : dict
        Dictionary with trial numbers as keys and objective dictionaries as values
    
    Returns:
    --------
    pd.DataFrame
        DataFrame with trial numbers as index and objectives as columns
    """
    objectives = ['F', 'Q', 'S', 'I', 'Total']
    
    # Create lists for DataFrame
    data_dict = {'Trial': []}
    for obj in objectives:
        data_dict[obj] = []
    
    # Populate the dictionary
    for trial_num in sorted(trials.keys()):
        data_dict['Trial'].append(trial_num)
        for obj in objectives:
            data_dict[obj].append(trials[trial_num].get(obj, np.nan))
    
    # Create DataFrame
    df = pd.DataFrame(data_dict)
    df.set_index('Trial', inplace=True)
    
    return df

def print_summary(trials, data):
    """Print summary statistics."""
    print(f"\nTotal trials parsed: {len(trials)}")
    print("\nObjective Statistics:")
    print("-" * 60)
    
    for obj in ['F', 'Q', 'S', 'I', 'Total']:
        values = [v for v in data[obj] if v is not None]
        if values:
            print(f"{obj:6} - Min: {min(values):.4e}, Max: {max(values):.4e}, "
                  f"Mean: {np.mean(values):.4e}")

if __name__ == "__main__":
    # Replace with your filename
    script_dir = os.path.dirname(os.path.abspath(__file__))
    file_path = os.path.join(script_dir, "results/manufacturer discounts/2 segments/UG pareto frontier/UG_output_2_segments_penta_hexa_inverse_pareto_frontier.txt")

    # filename = "Deterministic/Model Files/Segment Test/results/2 segments/UG pareto frontier/UG_output_2_segments_penta_hexa_inverse_pareto_frontier.txt"
    
    print("Parsing objective values...")
    trials = parse_objectives(file_path)
    
    if not trials:
        print("No trials found in file. Please check the file format.")
    else:
        print(f"Found {len(trials)} trials")

        # Create DataFrame
        df = create_objectives_dataframe(trials)
        print("\nObjectives DataFrame:")
        print(df)
        
        # Optionally save to CSV
        df.to_csv('Pareto_objectives_data.csv')
        print("\nDataFrame saved as 'objectives_data.csv'")

        data = plot_pareto_frontiers(trials)
        print_summary(trials, data)
        print("\nPareto frontier plot saved as 'pareto_frontiers.png'")