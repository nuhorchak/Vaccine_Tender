# import json
# import os
# import numpy as np
# import pandas as pd
# from scipy.spatial.distance import cosine
# from sklearn.metrics.pairwise import cosine_similarity
# import matplotlib.pyplot as plt
# import seaborn as sns
# from matplotlib.patches import Rectangle

# def load_json_files(directory):
#     """Load all JSON files from directory and extract F key"""
#     files_data = {}
    
#     json_files = sorted([f for f in os.listdir(directory) if f.endswith('.json')])
    
#     for filename in json_files:
#         filepath = os.path.join(directory, filename)
#         with open(filepath, 'r') as f:
#             data = json.load(f)
#             if 'F' in data:
#                 files_data[filename] = data['F']
    
#     return files_data

# def flatten_f_to_vector(f_data):
#     """Flatten the nested F dictionary into a single vector"""
#     all_keys = []
#     for outer_key in sorted(f_data.keys()):
#         for middle_key in sorted(f_data[outer_key].keys()):
#             for inner_key in sorted(f_data[outer_key][middle_key].keys()):
#                 all_keys.append((outer_key, middle_key, inner_key))
    
#     vector = []
#     for outer_key, middle_key, inner_key in all_keys:
#         value = f_data[outer_key][middle_key][inner_key]
#         binary_value = 1 if value > 0.5 else 0
#         vector.append(binary_value)
    
#     return np.array(vector), all_keys

# def create_feature_matrix(files_data):
#     """Create a matrix where each row is a file"""
#     filenames = sorted(files_data.keys())
#     first_file = filenames[0]
#     _, feature_names = flatten_f_to_vector(files_data[first_file])
    
#     matrix = []
#     for filename in filenames:
#         vector, _ = flatten_f_to_vector(files_data[filename])
#         matrix.append(vector)
    
#     return np.array(matrix), filenames, feature_names

# def compute_metrics_per_file(files_data, matrix, filenames):
#     """Compute various metrics for each file"""
#     metrics = []
    
#     # Compute cosine similarity matrix
#     similarity_matrix = cosine_similarity(matrix)
#     distance_matrix = 1 - similarity_matrix
    
#     for i, filename in enumerate(filenames):
#         f_data = files_data[filename]
#         vector = matrix[i]
        
#         # Extract trial number from filename
#         trial_num = None
#         if 'trial_' in filename:
#             try:
#                 trial_num = int(filename.split('trial_')[1].split('_')[0])
#             except:
#                 trial_num = i + 1
#         else:
#             trial_num = i + 1
        
#         # Total scheduled periods
#         total_scheduled = int(vector.sum())
        
#         # Scheduled periods per vaccine
#         vaccine_schedules = {}
#         for outer_key in sorted(f_data.keys()):
#             count = 0
#             for middle_key in f_data[outer_key]:
#                 for inner_key in f_data[outer_key][middle_key]:
#                     if f_data[outer_key][middle_key][inner_key] > 0.5:
#                         count += 1
#             vaccine_schedules[outer_key] = count
        
#         # Average distance to all other files
#         other_distances = [distance_matrix[i, j] for j in range(len(filenames)) if j != i]
#         avg_distance_to_others = np.mean(other_distances) if other_distances else 0
#         min_distance_to_others = np.min(other_distances) if other_distances else 0
#         max_distance_to_others = np.max(other_distances) if other_distances else 0
        
#         # Average similarity to all other files
#         other_similarities = [similarity_matrix[i, j] for j in range(len(filenames)) if j != i]
#         avg_similarity_to_others = np.mean(other_similarities) if other_similarities else 0
        
#         metrics.append({
#             'trial': trial_num,
#             'filename': filename,
#             'total_scheduled': total_scheduled,
#             'avg_distance': avg_distance_to_others,
#             'min_distance': min_distance_to_others,
#             'max_distance': max_distance_to_others,
#             'avg_similarity': avg_similarity_to_others,
#             **vaccine_schedules
#         })
    
#     return pd.DataFrame(metrics)

# def create_improved_visualizations(metrics_df, output_dir='/home/claude'):
#     """Create improved visualizations for small number of trials"""
    
#     # Set style
#     sns.set_style("whitegrid")
#     plt.rcParams['figure.facecolor'] = 'white'
    
#     # Get vaccine columns
#     vaccine_cols = [col for col in metrics_df.columns 
#                    if col not in ['trial', 'filename', 'total_scheduled', 
#                                  'avg_distance', 'min_distance', 'max_distance', 'avg_similarity']]
    
#     # Color palette
#     trial_colors = sns.color_palette("husl", len(metrics_df))
    
#     # ========================================================================
#     # Figure 1: Radar/Spider Chart for Distance Metrics per Trial
#     # ========================================================================
#     fig = plt.figure(figsize=(12, 10))
#     ax = fig.add_subplot(111, projection='polar')
    
#     # Metrics to plot
#     metrics_to_plot = ['avg_distance', 'min_distance', 'max_distance', 'avg_similarity']
#     metric_labels = ['Avg Distance', 'Min Distance', 'Max Distance', 'Avg Similarity']
    
#     # Normalize metrics to 0-1 scale for better visualization
#     normalized_data = metrics_df[metrics_to_plot].copy()
#     for col in metrics_to_plot:
#         min_val = normalized_data[col].min()
#         max_val = normalized_data[col].max()
#         if max_val > min_val:
#             normalized_data[col] = (normalized_data[col] - min_val) / (max_val - min_val)
    
#     # Number of variables
#     num_vars = len(metrics_to_plot)
#     angles = np.linspace(0, 2 * np.pi, num_vars, endpoint=False).tolist()
#     angles += angles[:1]  # Complete the circle
    
#     # Plot each trial
#     for idx, row in normalized_data.iterrows():
#         values = row.tolist()
#         values += values[:1]  # Complete the circle
        
#         trial_num = metrics_df.iloc[idx]['trial']
#         ax.plot(angles, values, 'o-', linewidth=2, 
#                label=f'Trial {trial_num}', color=trial_colors[idx])
#         ax.fill(angles, values, alpha=0.15, color=trial_colors[idx])
    
#     ax.set_xticks(angles[:-1])
#     ax.set_xticklabels(metric_labels, size=11)
#     ax.set_ylim(0, 1)
#     ax.set_title('Distance & Similarity Metrics Comparison Across Trials', 
#                 size=14, fontweight='bold', pad=20)
#     ax.legend(loc='upper right', bbox_to_anchor=(1.3, 1.1))
#     ax.grid(True)
    
#     plt.tight_layout()
#     plt.savefig(f'{output_dir}/radar_chart_metrics.png', dpi=300, bbox_inches='tight')
#     plt.close()
#     print(f"Radar chart saved to: {output_dir}/radar_chart_metrics.png")
    
#     # ========================================================================
#     # Figure 2: Grouped Bar Chart for Vaccine Schedules
#     # ========================================================================
#     fig, ax = plt.subplots(figsize=(14, 8))
    
#     x = np.arange(len(vaccine_cols))
#     width = 0.15  # Width of bars
    
#     # Plot bars for each trial
#     for i, (idx, row) in enumerate(metrics_df.iterrows()):
#         trial_num = row['trial']
#         values = [row[vaccine] for vaccine in vaccine_cols]
#         offset = (i - len(metrics_df)/2 + 0.5) * width
        
#         bars = ax.bar(x + offset, values, width, 
#                      label=f'Trial {trial_num}', 
#                      color=trial_colors[i], alpha=0.8, edgecolor='black', linewidth=0.5)
        
#         # Add value labels on top of bars
#         for bar in bars:
#             height = bar.get_height()
#             ax.text(bar.get_x() + bar.get_width()/2., height,
#                    f'{int(height)}',
#                    ha='center', va='bottom', fontsize=8)
    
#     ax.set_xlabel('Vaccine Type', fontsize=12, fontweight='bold')
#     ax.set_ylabel('Number of Scheduled Periods', fontsize=12, fontweight='bold')
#     ax.set_title('Scheduled Periods per Vaccine Across Trials', 
#                 fontsize=14, fontweight='bold', pad=20)
#     ax.set_xticks(x)
#     ax.set_xticklabels(vaccine_cols, rotation=45, ha='right')
#     ax.legend(fontsize=10, ncol=5, loc='upper center', bbox_to_anchor=(0.5, -0.15))
#     ax.grid(axis='y', alpha=0.3)
    
#     plt.tight_layout()
#     plt.savefig(f'{output_dir}/grouped_bar_vaccines.png', dpi=300, bbox_inches='tight')
#     plt.close()
#     print(f"Grouped bar chart saved to: {output_dir}/grouped_bar_vaccines.png")
    
#     # ========================================================================
#     # Figure 3: Lollipop Chart for Distance Metrics
#     # ========================================================================
#     fig, axes = plt.subplots(2, 2, figsize=(16, 10))
#     fig.suptitle('Distance & Similarity Metrics by Trial', fontsize=16, fontweight='bold')
    
#     metrics_plot = [
#         ('avg_distance', 'Average Distance to Other Trials', axes[0, 0]),
#         ('avg_similarity', 'Average Similarity to Other Trials', axes[0, 1]),
#         ('min_distance', 'Minimum Distance to Any Trial', axes[1, 0]),
#         ('max_distance', 'Maximum Distance to Any Trial', axes[1, 1])
#     ]
    
#     for metric, title, ax in metrics_plot:
#         trials = metrics_df['trial'].values
#         values = metrics_df[metric].values
        
#         # Create lollipop chart
#         ax.hlines(y=trials, xmin=0, xmax=values, color='gray', alpha=0.4, linewidth=2)
#         ax.scatter(values, trials, color=trial_colors, s=200, alpha=0.8, edgecolor='black', linewidth=1.5)
        
#         # Add value labels
#         for i, (trial, value) in enumerate(zip(trials, values)):
#             ax.text(value, trial, f'  {value:.4f}', 
#                    va='center', fontsize=10, fontweight='bold')
        
#         ax.set_yticks(trials)
#         ax.set_yticklabels([f'Trial {t}' for t in trials])
#         ax.set_xlabel('Value', fontsize=11, fontweight='bold')
#         ax.set_ylabel('Trial', fontsize=11, fontweight='bold')
#         ax.set_title(title, fontsize=12, fontweight='bold')
#         ax.grid(axis='x', alpha=0.3)
#         ax.invert_yaxis()  # Highest trial at top
    
#     plt.tight_layout()
#     plt.savefig(f'{output_dir}/lollipop_metrics.png', dpi=300, bbox_inches='tight')
#     plt.close()
#     print(f"Lollipop chart saved to: {output_dir}/lollipop_metrics.png")
    
#     # ========================================================================
#     # Figure 4: Heatmap showing all metrics side by side
#     # ========================================================================
#     fig, ax = plt.subplots(figsize=(12, 8))
    
#     # Select metrics for heatmap
#     heatmap_cols = ['total_scheduled', 'avg_distance', 'avg_similarity', 
#                     'min_distance', 'max_distance'] + vaccine_cols
    
#     # Create normalized version for heatmap
#     heatmap_data = metrics_df[heatmap_cols].copy()
    
#     # Normalize each column to 0-1 for better color visualization
#     normalized_heatmap = heatmap_data.copy()
#     for col in heatmap_cols:
#         min_val = heatmap_data[col].min()
#         max_val = heatmap_data[col].max()
#         if max_val > min_val:
#             normalized_heatmap[col] = (heatmap_data[col] - min_val) / (max_val - min_val)
#         else:
#             normalized_heatmap[col] = 0.5
    
#     # Create labels with actual values
#     annot_labels = heatmap_data.values.astype(str)
#     for i in range(len(heatmap_data)):
#         for j in range(len(heatmap_cols)):
#             val = heatmap_data.iloc[i, j]
#             if j < 5:  # Distance/similarity metrics
#                 annot_labels[i, j] = f'{val:.3f}'
#             else:  # Vaccine counts
#                 annot_labels[i, j] = f'{int(val)}'
    
#     sns.heatmap(normalized_heatmap, annot=annot_labels, fmt='', 
#                cmap='YlOrRd', cbar_kws={'label': 'Normalized Value'},
#                linewidths=0.5, linecolor='gray', ax=ax,
#                yticklabels=[f'Trial {t}' for t in metrics_df['trial']])
    
#     ax.set_title('All Metrics Heatmap (Annotated with Actual Values)', 
#                 fontsize=14, fontweight='bold', pad=20)
#     plt.xticks(rotation=45, ha='right')
#     plt.tight_layout()
#     plt.savefig(f'{output_dir}/heatmap_all_metrics.png', dpi=300, bbox_inches='tight')
#     plt.close()
#     print(f"Heatmap saved to: {output_dir}/heatmap_all_metrics.png")
    
#     # ========================================================================
#     # Figure 5: Parallel Coordinates Plot
#     # ========================================================================
#     from pandas.plotting import parallel_coordinates
    
#     fig, ax = plt.subplots(figsize=(16, 8))
    
#     # Prepare data for parallel coordinates
#     plot_data = metrics_df[['trial', 'total_scheduled', 'avg_distance', 
#                             'avg_similarity'] + vaccine_cols[:5]].copy()  # First 5 vaccines
#     plot_data['trial'] = plot_data['trial'].astype(str)
    
#     # Normalize for better visualization
#     for col in plot_data.columns:
#         if col != 'trial':
#             min_val = plot_data[col].min()
#             max_val = plot_data[col].max()
#             if max_val > min_val:
#                 plot_data[col] = (plot_data[col] - min_val) / (max_val - min_val)
    
#     parallel_coordinates(plot_data, 'trial', colormap='Set1', 
#                         linewidth=2.5, alpha=0.7, ax=ax)
    
#     ax.set_title('Parallel Coordinates Plot (Normalized Metrics)', 
#                 fontsize=14, fontweight='bold', pad=20)
#     ax.set_ylabel('Normalized Value (0-1)', fontsize=11, fontweight='bold')
#     ax.grid(axis='y', alpha=0.3)
#     plt.xticks(rotation=45, ha='right')
#     plt.legend(title='Trial', loc='upper left', bbox_to_anchor=(1.02, 1))
#     plt.tight_layout()
#     plt.savefig(f'{output_dir}/parallel_coordinates.png', dpi=300, bbox_inches='tight')
#     plt.close()
#     print(f"Parallel coordinates plot saved to: {output_dir}/parallel_coordinates.png")
    
#     # ========================================================================
#     # Figure 6: Summary Dashboard
#     # ========================================================================
#     fig = plt.figure(figsize=(16, 10))
#     gs = fig.add_gridspec(3, 3, hspace=0.3, wspace=0.3)
    
#     # Top row: Main metrics
#     ax1 = fig.add_subplot(gs[0, :])
#     trials = metrics_df['trial'].values
#     x_pos = np.arange(len(trials))
    
#     ax1_twin = ax1.twinx()
    
#     # Bar plot for total scheduled
#     bars1 = ax1.bar(x_pos - 0.2, metrics_df['total_scheduled'], 0.4, 
#                     label='Total Scheduled', color='steelblue', alpha=0.7)
    
#     # Line plot for avg distance
#     line1 = ax1_twin.plot(x_pos, metrics_df['avg_distance'], 
#                           'o-', linewidth=2.5, markersize=10,
#                           label='Avg Distance', color='crimson')
    
#     # Line plot for avg similarity
#     line2 = ax1_twin.plot(x_pos, metrics_df['avg_similarity'], 
#                           's-', linewidth=2.5, markersize=10,
#                           label='Avg Similarity', color='green')
    
#     ax1.set_xlabel('Trial', fontsize=12, fontweight='bold')
#     ax1.set_ylabel('Total Scheduled Periods', fontsize=11, fontweight='bold', color='steelblue')
#     ax1_twin.set_ylabel('Distance / Similarity', fontsize=11, fontweight='bold')
#     ax1.set_xticks(x_pos)
#     ax1.set_xticklabels([f'Trial {t}' for t in trials])
#     ax1.set_title('Overview: Scheduled Periods vs. Distance Metrics', 
#                  fontsize=13, fontweight='bold')
#     ax1.grid(axis='y', alpha=0.3)
    
#     # Combine legends
#     lines1, labels1 = ax1.get_legend_handles_labels()
#     lines2, labels2 = ax1_twin.get_legend_handles_labels()
#     ax1_twin.legend(lines1 + lines2, labels1 + labels2, loc='upper right')
    
#     # Middle row: Top 3 vaccines
#     for i, vaccine in enumerate(vaccine_cols[:3]):
#         ax = fig.add_subplot(gs[1, i])
#         values = metrics_df[vaccine].values
        
#         bars = ax.barh(trials, values, color=trial_colors, alpha=0.7, edgecolor='black')
        
#         for bar, val in zip(bars, values):
#             width = bar.get_width()
#             ax.text(width, bar.get_y() + bar.get_height()/2, 
#                    f' {int(val)}', va='center', fontweight='bold')
        
#         ax.set_xlabel('Scheduled Periods', fontsize=10)
#         ax.set_ylabel('Trial', fontsize=10)
#         ax.set_title(vaccine, fontsize=11, fontweight='bold')
#         ax.set_yticks(trials)
#         ax.grid(axis='x', alpha=0.3)
#         ax.invert_yaxis()
    
#     # Bottom row: Statistics and comparisons
#     ax_stats = fig.add_subplot(gs[2, :])
#     ax_stats.axis('off')
    
#     stats_text = f"""
#     SUMMARY STATISTICS:
    
#     Total Trials: {len(metrics_df)}
    
#     Total Scheduled Periods:
#         Mean: {metrics_df['total_scheduled'].mean():.1f} | Std: {metrics_df['total_scheduled'].std():.2f} | Range: [{metrics_df['total_scheduled'].min()}, {metrics_df['total_scheduled'].max()}]
    
#     Average Distance to Other Trials:
#         Mean: {metrics_df['avg_distance'].mean():.4f} | Std: {metrics_df['avg_distance'].std():.4f} | Range: [{metrics_df['avg_distance'].min():.4f}, {metrics_df['avg_distance'].max():.4f}]
    
#     Average Similarity to Other Trials:
#         Mean: {metrics_df['avg_similarity'].mean():.4f} | Std: {metrics_df['avg_similarity'].std():.4f} | Range: [{metrics_df['avg_similarity'].min():.4f}, {metrics_df['avg_similarity'].max():.4f}]
    
#     Most Similar Trials: Trial {metrics_df.loc[metrics_df['avg_distance'].idxmin(), 'trial']} (avg distance: {metrics_df['avg_distance'].min():.4f})
#     Most Different Trial: Trial {metrics_df.loc[metrics_df['avg_distance'].idxmax(), 'trial']} (avg distance: {metrics_df['avg_distance'].max():.4f})
#     """
    
#     ax_stats.text(0.1, 0.5, stats_text, fontsize=11, verticalalignment='center',
#                  fontfamily='monospace', 
#                  bbox=dict(boxstyle='round', facecolor='lightblue', alpha=0.3, pad=1))
    
#     fig.suptitle('Trial Comparison Dashboard', fontsize=16, fontweight='bold', y=0.98)
#     plt.savefig(f'{output_dir}/dashboard_summary.png', dpi=300, bbox_inches='tight')
#     plt.close()
#     print(f"Dashboard summary saved to: {output_dir}/dashboard_summary.png")

# # Main execution
# if __name__ == "__main__":
#     # Load data
#     upload_dir = '/mnt/user-data/uploads'
#     files_data = load_json_files(upload_dir)
    
#     print(f"Loaded {len(files_data)} JSON files\n")
    
#     if len(files_data) == 0:
#         print("No JSON files found!")
#         exit(1)
    
#     # Create feature matrix
#     matrix, filenames, feature_names = create_feature_matrix(files_data)
    
#     # Compute metrics
#     print("Computing metrics for each trial...")
#     metrics_df = compute_metrics_per_file(files_data, matrix, filenames)
    
#     print("\n" + "=" * 80)
#     print("CREATING IMPROVED VISUALIZATIONS")
#     print("=" * 80)
#     create_improved_visualizations(metrics_df)
    
#     print("\n" + "=" * 80)
#     print("ANALYSIS COMPLETE!")
#     print("=" * 80)


import json
import os
import numpy as np
import pandas as pd
from pathlib import Path
from scipy.spatial.distance import cosine
from sklearn.metrics.pairwise import cosine_similarity
import matplotlib.pyplot as plt
import seaborn as sns
from matplotlib.patches import Rectangle

def load_json_files(directory):
    """Load all JSON files from directory and extract F key"""
    dir_path = Path(directory)
    
    # Check if directory exists
    if not dir_path.exists():
        print(f"Warning: Directory '{directory}' does not exist!")
        return {}
    
    files_data = {}
    json_files = sorted([f for f in os.listdir(dir_path) if f.endswith('.json')])
    
    print(f"Found {len(json_files)} JSON files in {directory}")
    
    errors = []
    for filename in json_files:
        filepath = dir_path / filename
        try:
            with open(filepath, 'r') as f:
                data = json.load(f)
                if 'F' in data:
                    files_data[filename] = data['F']
                else:
                    errors.append(f"  ⚠ {filename}: Missing 'F' key")
        except json.JSONDecodeError as e:
            errors.append(f"  ✗ {filename}: JSON decode error - {str(e)}")
        except Exception as e:
            errors.append(f"  ✗ {filename}: {type(e).__name__} - {str(e)}")
    
    if errors:
        print(f"⚠ Encountered {len(errors)} error(s):")
        for error in errors:
            print(error)
    
    return files_data

def flatten_f_to_vector(f_data):
    """Flatten the nested F dictionary into a single vector"""
    all_keys = []
    for outer_key in sorted(f_data.keys()):
        for middle_key in sorted(f_data[outer_key].keys()):
            for inner_key in sorted(f_data[outer_key][middle_key].keys()):
                all_keys.append((outer_key, middle_key, inner_key))
    
    vector = []
    for outer_key, middle_key, inner_key in all_keys:
        value = f_data[outer_key][middle_key][inner_key]
        binary_value = 1 if value > 0.5 else 0
        vector.append(binary_value)
    
    return np.array(vector), all_keys

def create_feature_matrix(files_data):
    """Create a matrix where each row is a file"""
    filenames = sorted(files_data.keys())
    first_file = filenames[0]
    _, feature_names = flatten_f_to_vector(files_data[first_file])
    
    matrix = []
    for filename in filenames:
        vector, _ = flatten_f_to_vector(files_data[filename])
        matrix.append(vector)
    
    return np.array(matrix), filenames, feature_names

def compute_metrics_per_file(files_data, matrix, filenames):
    """Compute various metrics for each file"""
    metrics = []
    
    # Compute cosine similarity matrix
    similarity_matrix = cosine_similarity(matrix)
    distance_matrix = 1 - similarity_matrix
    
    for i, filename in enumerate(filenames):
        f_data = files_data[filename]
        vector = matrix[i]
        
        # Extract trial number from filename
        trial_num = None
        if 'trial_' in filename:
            try:
                trial_num = int(filename.split('trial_')[1].split('_')[0])
            except:
                trial_num = i + 1
        else:
            trial_num = i + 1
        
        # Total scheduled periods
        total_scheduled = int(vector.sum())
        
        # Scheduled periods per vaccine
        vaccine_schedules = {}
        for outer_key in sorted(f_data.keys()):
            count = 0
            for middle_key in f_data[outer_key]:
                for inner_key in f_data[outer_key][middle_key]:
                    if f_data[outer_key][middle_key][inner_key] > 0.5:
                        count += 1
            vaccine_schedules[outer_key] = count
        
        # Average distance to all other files
        other_distances = [distance_matrix[i, j] for j in range(len(filenames)) if j != i]
        avg_distance_to_others = np.mean(other_distances) if other_distances else 0
        min_distance_to_others = np.min(other_distances) if other_distances else 0
        max_distance_to_others = np.max(other_distances) if other_distances else 0
        
        # Average similarity to all other files
        other_similarities = [similarity_matrix[i, j] for j in range(len(filenames)) if j != i]
        avg_similarity_to_others = np.mean(other_similarities) if other_similarities else 0
        
        metrics.append({
            'trial': trial_num,
            'filename': filename,
            'total_scheduled': total_scheduled,
            'avg_distance': avg_distance_to_others,
            'min_distance': min_distance_to_others,
            'max_distance': max_distance_to_others,
            'avg_similarity': avg_similarity_to_others,
            **vaccine_schedules
        })
    
    return pd.DataFrame(metrics)

def create_improved_visualizations(metrics_df, output_dir):
    """Create improved visualizations for small number of trials"""
    
    # Create output directory
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    # Set style
    sns.set_style("whitegrid")
    plt.rcParams['figure.facecolor'] = 'white'
    
    # Get vaccine columns
    vaccine_cols = [col for col in metrics_df.columns 
                   if col not in ['trial', 'filename', 'total_scheduled', 
                                 'avg_distance', 'min_distance', 'max_distance', 'avg_similarity']]
    
    # Color palette
    trial_colors = sns.color_palette("husl", len(metrics_df))
    
    # ========================================================================
    # Figure 1: Radar/Spider Chart for Distance Metrics per Trial
    # ========================================================================
    fig = plt.figure(figsize=(12, 10))
    ax = fig.add_subplot(111, projection='polar')
    
    # Metrics to plot
    metrics_to_plot = ['avg_distance', 'min_distance', 'max_distance', 'avg_similarity']
    metric_labels = ['Avg Distance', 'Min Distance', 'Max Distance', 'Avg Similarity']
    
    # Normalize metrics to 0-1 scale for better visualization
    normalized_data = metrics_df[metrics_to_plot].copy()
    for col in metrics_to_plot:
        min_val = normalized_data[col].min()
        max_val = normalized_data[col].max()
        if max_val > min_val:
            normalized_data[col] = (normalized_data[col] - min_val) / (max_val - min_val)
    
    # Number of variables
    num_vars = len(metrics_to_plot)
    angles = np.linspace(0, 2 * np.pi, num_vars, endpoint=False).tolist()
    angles += angles[:1]  # Complete the circle
    
    # Plot each trial
    for idx, row in normalized_data.iterrows():
        values = row.tolist()
        values += values[:1]  # Complete the circle
        
        trial_num = metrics_df.iloc[idx]['trial']
        ax.plot(angles, values, 'o-', linewidth=2, 
               label=f'Trial {trial_num}', color=trial_colors[idx])
        ax.fill(angles, values, alpha=0.15, color=trial_colors[idx])
    
    ax.set_xticks(angles[:-1])
    ax.set_xticklabels(metric_labels, size=11)
    ax.set_ylim(0, 1)
    ax.set_title('Distance & Similarity Metrics Comparison Across Trials', 
                size=14, fontweight='bold', pad=20)
    ax.legend(loc='upper right', bbox_to_anchor=(1.3, 1.1))
    ax.grid(True)
    
    plt.tight_layout()
    plt.savefig(Path(output_dir) / 'radar_chart_metrics.png', dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Radar chart saved")
    
    # ========================================================================
    # Figure 2: Grouped Bar Chart for Vaccine Schedules
    # ========================================================================
    fig, ax = plt.subplots(figsize=(14, 8))
    
    x = np.arange(len(vaccine_cols))
    width = 0.15  # Width of bars
    
    # Plot bars for each trial
    for i, (idx, row) in enumerate(metrics_df.iterrows()):
        trial_num = row['trial']
        values = [row[vaccine] for vaccine in vaccine_cols]
        offset = (i - len(metrics_df)/2 + 0.5) * width
        
        bars = ax.bar(x + offset, values, width, 
                     label=f'Trial {trial_num}', 
                     color=trial_colors[i], alpha=0.8, edgecolor='black', linewidth=0.5)
        
        # Add value labels on top of bars
        for bar in bars:
            height = bar.get_height()
            ax.text(bar.get_x() + bar.get_width()/2., height,
                   f'{int(height)}',
                   ha='center', va='bottom', fontsize=8)
    
    ax.set_xlabel('Vaccine Type', fontsize=12, fontweight='bold')
    ax.set_ylabel('Number of Scheduled Periods', fontsize=12, fontweight='bold')
    ax.set_title('Scheduled Periods per Vaccine Across Trials', 
                fontsize=14, fontweight='bold', pad=20)
    ax.set_xticks(x)
    ax.set_xticklabels(vaccine_cols, rotation=45, ha='right')
    ax.legend(fontsize=10, ncol=5, loc='upper center', bbox_to_anchor=(0.5, -0.15))
    ax.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(Path(output_dir) / 'grouped_bar_vaccines.png', dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Grouped bar chart saved")
    
    # ========================================================================
    # Figure 3: Lollipop Chart for Distance Metrics
    # ========================================================================
    fig, axes = plt.subplots(2, 2, figsize=(16, 10))
    fig.suptitle('Distance & Similarity Metrics by Trial', fontsize=16, fontweight='bold')
    
    metrics_plot = [
        ('avg_distance', 'Average Distance to Other Trials', axes[0, 0]),
        ('avg_similarity', 'Average Similarity to Other Trials', axes[0, 1]),
        ('min_distance', 'Minimum Distance to Any Trial', axes[1, 0]),
        ('max_distance', 'Maximum Distance to Any Trial', axes[1, 1])
    ]
    
    for metric, title, ax in metrics_plot:
        trials = metrics_df['trial'].values
        values = metrics_df[metric].values
        
        # Create lollipop chart
        ax.hlines(y=trials, xmin=0, xmax=values, color='gray', alpha=0.4, linewidth=2)
        ax.scatter(values, trials, color=trial_colors, s=200, alpha=0.8, edgecolor='black', linewidth=1.5)
        
        # Add value labels
        for i, (trial, value) in enumerate(zip(trials, values)):
            ax.text(value, trial, f'  {value:.4f}', 
                   va='center', fontsize=10, fontweight='bold')
        
        ax.set_yticks(trials)
        ax.set_yticklabels([f'Trial {t}' for t in trials])
        ax.set_xlabel('Value', fontsize=11, fontweight='bold')
        ax.set_ylabel('Trial', fontsize=11, fontweight='bold')
        ax.set_title(title, fontsize=12, fontweight='bold')
        ax.grid(axis='x', alpha=0.3)
        ax.invert_yaxis()  # Highest trial at top
    
    plt.tight_layout()
    plt.savefig(Path(output_dir) / 'lollipop_metrics.png', dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Lollipop chart saved")
    
    # ========================================================================
    # Figure 4: Heatmap showing all metrics side by side
    # ========================================================================
    fig, ax = plt.subplots(figsize=(12, 8))
    
    # Select metrics for heatmap
    heatmap_cols = ['total_scheduled', 'avg_distance', 'avg_similarity', 
                    'min_distance', 'max_distance'] + vaccine_cols
    
    # Create normalized version for heatmap
    heatmap_data = metrics_df[heatmap_cols].copy()
    
    # Normalize each column to 0-1 for better color visualization
    normalized_heatmap = heatmap_data.copy()
    for col in heatmap_cols:
        min_val = heatmap_data[col].min()
        max_val = heatmap_data[col].max()
        if max_val > min_val:
            normalized_heatmap[col] = (heatmap_data[col] - min_val) / (max_val - min_val)
        else:
            normalized_heatmap[col] = 0.5
    
    # Create labels with actual values
    annot_labels = heatmap_data.values.astype(str)
    for i in range(len(heatmap_data)):
        for j in range(len(heatmap_cols)):
            val = heatmap_data.iloc[i, j]
            if j < 5:  # Distance/similarity metrics
                annot_labels[i, j] = f'{val:.3f}'
            else:  # Vaccine counts
                annot_labels[i, j] = f'{int(val)}'
    
    sns.heatmap(normalized_heatmap, annot=annot_labels, fmt='', 
               cmap='YlOrRd', cbar_kws={'label': 'Normalized Value'},
               linewidths=0.5, linecolor='gray', ax=ax,
               yticklabels=[f'Trial {t}' for t in metrics_df['trial']])
    
    ax.set_title('All Metrics Heatmap (Annotated with Actual Values)', 
                fontsize=14, fontweight='bold', pad=20)
    plt.xticks(rotation=45, ha='right')
    plt.tight_layout()
    plt.savefig(Path(output_dir) / 'heatmap_all_metrics.png', dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Heatmap saved")
    
    # ========================================================================
    # Figure 5: Parallel Coordinates Plot
    # ========================================================================
    from pandas.plotting import parallel_coordinates
    
    fig, ax = plt.subplots(figsize=(16, 8))
    
    # Prepare data for parallel coordinates
    plot_data = metrics_df[['trial', 'total_scheduled', 'avg_distance', 
                            'avg_similarity'] + vaccine_cols[:5]].copy()  # First 5 vaccines
    plot_data['trial'] = plot_data['trial'].astype(str)
    
    # Normalize for better visualization
    for col in plot_data.columns:
        if col != 'trial':
            min_val = plot_data[col].min()
            max_val = plot_data[col].max()
            if max_val > min_val:
                plot_data[col] = (plot_data[col] - min_val) / (max_val - min_val)
    
    parallel_coordinates(plot_data, 'trial', colormap='Set1', 
                        linewidth=2.5, alpha=0.7, ax=ax)
    
    ax.set_title('Parallel Coordinates Plot (Normalized Metrics)', 
                fontsize=14, fontweight='bold', pad=20)
    ax.set_ylabel('Normalized Value (0-1)', fontsize=11, fontweight='bold')
    ax.grid(axis='y', alpha=0.3)
    plt.xticks(rotation=45, ha='right')
    plt.legend(title='Trial', loc='upper left', bbox_to_anchor=(1.02, 1))
    plt.tight_layout()
    plt.savefig(Path(output_dir) / 'parallel_coordinates.png', dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Parallel coordinates plot saved")
    
    # ========================================================================
    # Figure 6: Summary Dashboard
    # ========================================================================
    fig = plt.figure(figsize=(16, 10))
    gs = fig.add_gridspec(3, 3, hspace=0.3, wspace=0.3)
    
    # Top row: Main metrics
    ax1 = fig.add_subplot(gs[0, :])
    trials = metrics_df['trial'].values
    x_pos = np.arange(len(trials))
    
    ax1_twin = ax1.twinx()
    
    # Bar plot for total scheduled
    bars1 = ax1.bar(x_pos - 0.2, metrics_df['total_scheduled'], 0.4, 
                    label='Total Scheduled', color='steelblue', alpha=0.7)
    
    # Line plot for avg distance
    line1 = ax1_twin.plot(x_pos, metrics_df['avg_distance'], 
                          'o-', linewidth=2.5, markersize=10,
                          label='Avg Distance', color='crimson')
    
    # Line plot for avg similarity
    line2 = ax1_twin.plot(x_pos, metrics_df['avg_similarity'], 
                          's-', linewidth=2.5, markersize=10,
                          label='Avg Similarity', color='green')
    
    ax1.set_xlabel('Trial', fontsize=12, fontweight='bold')
    ax1.set_ylabel('Total Scheduled Periods', fontsize=11, fontweight='bold', color='steelblue')
    ax1_twin.set_ylabel('Distance / Similarity', fontsize=11, fontweight='bold')
    ax1.set_xticks(x_pos)
    ax1.set_xticklabels([f'Trial {t}' for t in trials])
    ax1.set_title('Overview: Scheduled Periods vs. Distance Metrics', 
                 fontsize=13, fontweight='bold')
    ax1.grid(axis='y', alpha=0.3)
    
    # Combine legends
    lines1, labels1 = ax1.get_legend_handles_labels()
    lines2, labels2 = ax1_twin.get_legend_handles_labels()
    ax1_twin.legend(lines1 + lines2, labels1 + labels2, loc='upper right')
    
    # Middle row: Top 3 vaccines
    for i, vaccine in enumerate(vaccine_cols[:3]):
        ax = fig.add_subplot(gs[1, i])
        values = metrics_df[vaccine].values
        
        bars = ax.barh(trials, values, color=trial_colors, alpha=0.7, edgecolor='black')
        
        for bar, val in zip(bars, values):
            width = bar.get_width()
            ax.text(width, bar.get_y() + bar.get_height()/2, 
                   f' {int(val)}', va='center', fontweight='bold')
        
        ax.set_xlabel('Scheduled Periods', fontsize=10)
        ax.set_ylabel('Trial', fontsize=10)
        ax.set_title(vaccine, fontsize=11, fontweight='bold')
        ax.set_yticks(trials)
        ax.grid(axis='x', alpha=0.3)
        ax.invert_yaxis()
    
    # Bottom row: Statistics and comparisons
    ax_stats = fig.add_subplot(gs[2, :])
    ax_stats.axis('off')
    
    stats_text = f"""
    SUMMARY STATISTICS:
    
    Total Trials: {len(metrics_df)}
    
    Total Scheduled Periods:
        Mean: {metrics_df['total_scheduled'].mean():.1f} | Std: {metrics_df['total_scheduled'].std():.2f} | Range: [{metrics_df['total_scheduled'].min()}, {metrics_df['total_scheduled'].max()}]
    
    Average Distance to Other Trials:
        Mean: {metrics_df['avg_distance'].mean():.4f} | Std: {metrics_df['avg_distance'].std():.4f} | Range: [{metrics_df['avg_distance'].min():.4f}, {metrics_df['avg_distance'].max():.4f}]
    
    Average Similarity to Other Trials:
        Mean: {metrics_df['avg_similarity'].mean():.4f} | Std: {metrics_df['avg_similarity'].std():.4f} | Range: [{metrics_df['avg_similarity'].min():.4f}, {metrics_df['avg_similarity'].max():.4f}]
    
    Most Similar Trials: Trial {metrics_df.loc[metrics_df['avg_distance'].idxmin(), 'trial']} (avg distance: {metrics_df['avg_distance'].min():.4f})
    Most Different Trial: Trial {metrics_df.loc[metrics_df['avg_distance'].idxmax(), 'trial']} (avg distance: {metrics_df['avg_distance'].max():.4f})
    """
    
    ax_stats.text(0.1, 0.5, stats_text, fontsize=11, verticalalignment='center',
                 fontfamily='monospace', 
                 bbox=dict(boxstyle='round', facecolor='lightblue', alpha=0.3, pad=1))
    
    fig.suptitle('Trial Comparison Dashboard', fontsize=16, fontweight='bold', y=0.98)
    plt.savefig(Path(output_dir) / 'dashboard_summary.png', dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Dashboard summary saved")
    
    print(f"\n✓ All visualizations saved to {output_dir}/")

# Main execution
if __name__ == "__main__":
    print("="*80)
    print("F DATA ANALYSIS - TRIAL COMPARISON")
    print("="*80 + "\n")
    
    # Get current working directory
    base_dir = Path.cwd()
    print(f"Current working directory: {base_dir}\n")
    
    # Define paths
    input_dir = base_dir / 'Deterministic' / 'Model objective analysis' / 'quantity discount' / 'results' / 'buyer discounts' / '2 segments penta hexa' / 'SB'
    
    # Create analysis output directory
    analysis_dir = base_dir / 'analysis'
    analysis_dir.mkdir(exist_ok=True)
    
    plots_dir = analysis_dir / 'F_plots'
    
    # Load data
    print("Loading JSON files...")
    files_data = load_json_files(input_dir)
    
    print(f"✓ Loaded {len(files_data)} JSON files with 'F' data\n")
    
    if len(files_data) == 0:
        print("\n⚠ WARNING: No valid JSON files with 'F' key found!")
        print(f"Looking in: {input_dir}")
        print("\nPlease check:")
        print("  1. The directory exists and contains JSON files")
        print("  2. The JSON files contain an 'F' key")
        exit(1)
    
    # Create feature matrix
    print("Creating feature matrix...")
    matrix, filenames, feature_names = create_feature_matrix(files_data)
    print(f"✓ Created matrix with shape: {matrix.shape}\n")
    
    # Compute metrics
    print("Computing metrics for each trial...")
    metrics_df = compute_metrics_per_file(files_data, matrix, filenames)
    print(f"✓ Computed metrics for {len(metrics_df)} trials\n")
    
    # Save metrics to CSV
    metrics_csv = analysis_dir / 'F_trial_metrics.csv'
    metrics_df.to_csv(metrics_csv, index=False)
    print(f"✓ Saved metrics to {metrics_csv}\n")
    
    # Create visualizations
    print("=" * 80)
    print("CREATING VISUALIZATIONS")
    print("=" * 80)
    create_improved_visualizations(metrics_df, plots_dir)
    
    print("\n" + "=" * 80)
    print("ANALYSIS COMPLETE!")
    print("=" * 80)
    print(f"\nGenerated files in '{analysis_dir}':")
    print("  1. F_trial_metrics.csv - Detailed metrics for each trial")
    print(f"  2. {plots_dir.name}/ - 6 specialized visualizations")
    print("     - radar_chart_metrics.png")
    print("     - grouped_bar_vaccines.png")
    print("     - lollipop_metrics.png")
    print("     - heatmap_all_metrics.png")
    print("     - parallel_coordinates.png")
    print("     - dashboard_summary.png")