# import json
# import os
# import numpy as np
# import pandas as pd
# from scipy.spatial.distance import cosine
# from sklearn.metrics.pairwise import cosine_similarity
# import matplotlib.pyplot as plt
# import seaborn as sns

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

# def create_boxplot_visualizations(metrics_df, output_dir='/home/claude'):
#     """Create comprehensive box plot visualizations"""
    
#     # Set style
#     sns.set_style("whitegrid")
#     plt.rcParams['figure.facecolor'] = 'white'
    
#     # Get vaccine columns (exclude trial, filename, and metric columns)
#     vaccine_cols = [col for col in metrics_df.columns 
#                    if col not in ['trial', 'filename', 'total_scheduled', 
#                                  'avg_distance', 'min_distance', 'max_distance', 'avg_similarity']]
    
#     # Figure 1: Multi-panel box plots for all metrics
#     fig, axes = plt.subplots(2, 3, figsize=(18, 12))
#     fig.suptitle('Distribution of Metrics Across All Trials', fontsize=16, fontweight='bold', y=0.995)
    
#     # Total Scheduled Periods
#     ax = axes[0, 0]
#     sns.boxplot(y=metrics_df['total_scheduled'], ax=ax, color='skyblue')
#     sns.swarmplot(y=metrics_df['total_scheduled'], ax=ax, color='darkblue', alpha=0.6, size=8)
#     ax.set_ylabel('Count', fontsize=11)
#     ax.set_title('Total Scheduled Periods', fontsize=12, fontweight='bold')
#     ax.grid(axis='y', alpha=0.3)
    
#     # Average Distance to Other Files
#     ax = axes[0, 1]
#     sns.boxplot(y=metrics_df['avg_distance'], ax=ax, color='salmon')
#     sns.swarmplot(y=metrics_df['avg_distance'], ax=ax, color='darkred', alpha=0.6, size=8)
#     ax.set_ylabel('Distance', fontsize=11)
#     ax.set_title('Avg Cosine Distance to Other Trials', fontsize=12, fontweight='bold')
#     ax.grid(axis='y', alpha=0.3)
    
#     # Average Similarity to Other Files
#     ax = axes[0, 2]
#     sns.boxplot(y=metrics_df['avg_similarity'], ax=ax, color='lightgreen')
#     sns.swarmplot(y=metrics_df['avg_similarity'], ax=ax, color='darkgreen', alpha=0.6, size=8)
#     ax.set_ylabel('Similarity', fontsize=11)
#     ax.set_title('Avg Cosine Similarity to Other Trials', fontsize=12, fontweight='bold')
#     ax.grid(axis='y', alpha=0.3)
    
#     # Min Distance
#     ax = axes[1, 0]
#     sns.boxplot(y=metrics_df['min_distance'], ax=ax, color='plum')
#     sns.swarmplot(y=metrics_df['min_distance'], ax=ax, color='purple', alpha=0.6, size=8)
#     ax.set_ylabel('Distance', fontsize=11)
#     ax.set_title('Min Distance to Any Other Trial', fontsize=12, fontweight='bold')
#     ax.grid(axis='y', alpha=0.3)
    
#     # Max Distance
#     ax = axes[1, 1]
#     sns.boxplot(y=metrics_df['max_distance'], ax=ax, color='peachpuff')
#     sns.swarmplot(y=metrics_df['max_distance'], ax=ax, color='darkorange', alpha=0.6, size=8)
#     ax.set_ylabel('Distance', fontsize=11)
#     ax.set_title('Max Distance to Any Other Trial', fontsize=12, fontweight='bold')
#     ax.grid(axis='y', alpha=0.3)
    
#     # Summary statistics text
#     ax = axes[1, 2]
#     ax.axis('off')
    
#     summary_text = f"""Summary Statistics:
    
# Total Scheduled Periods:
#   Mean: {metrics_df['total_scheduled'].mean():.1f}
#   Std:  {metrics_df['total_scheduled'].std():.2f}
  
# Avg Distance to Others:
#   Mean: {metrics_df['avg_distance'].mean():.4f}
#   Std:  {metrics_df['avg_distance'].std():.4f}
  
# Avg Similarity to Others:
#   Mean: {metrics_df['avg_similarity'].mean():.4f}
#   Std:  {metrics_df['avg_similarity'].std():.4f}
  
# Number of Trials: {len(metrics_df)}
# """
    
#     ax.text(0.1, 0.5, summary_text, fontsize=11, verticalalignment='center',
#             fontfamily='monospace', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.3))
    
#     plt.tight_layout()
#     plt.savefig(f'{output_dir}/metrics_boxplots.png', dpi=300, bbox_inches='tight')
#     plt.close()
#     print(f"Metrics box plots saved to: {output_dir}/metrics_boxplots.png")
    
#     # Figure 2: Vaccine-specific scheduled periods
#     fig, ax = plt.subplots(figsize=(14, 8))
    
#     # Prepare data for grouped box plot
#     vaccine_data = []
#     for vaccine in vaccine_cols:
#         for value in metrics_df[vaccine]:
#             vaccine_data.append({'Vaccine': vaccine, 'Scheduled Periods': value})
    
#     vaccine_df = pd.DataFrame(vaccine_data)
    
#     sns.boxplot(data=vaccine_df, x='Vaccine', y='Scheduled Periods', ax=ax, palette='Set2')
#     sns.swarmplot(data=vaccine_df, x='Vaccine', y='Scheduled Periods', ax=ax, 
#                   color='black', alpha=0.5, size=6)
    
#     ax.set_title('Scheduled Periods per Vaccine Across All Trials', 
#                 fontsize=14, fontweight='bold', pad=20)
#     ax.set_xlabel('Vaccine Type', fontsize=12, fontweight='bold')
#     ax.set_ylabel('Number of Scheduled Periods', fontsize=12, fontweight='bold')
#     ax.grid(axis='y', alpha=0.3)
#     plt.xticks(rotation=45, ha='right')
    
#     plt.tight_layout()
#     plt.savefig(f'{output_dir}/vaccine_schedules_boxplot.png', dpi=300, bbox_inches='tight')
#     plt.close()
#     print(f"Vaccine schedules box plot saved to: {output_dir}/vaccine_schedules_boxplot.png")
    
#     # Figure 3: Individual trial comparison (bar plot with error ranges)
#     fig, ax = plt.subplots(figsize=(14, 8))
    
#     x = np.arange(len(metrics_df))
#     width = 0.8
    
#     # Plot bars for each trial
#     colors = plt.cm.viridis(np.linspace(0, 1, len(metrics_df)))
#     bars = ax.bar(x, metrics_df['avg_distance'], width, 
#                   label='Avg Distance', color=colors, alpha=0.7, edgecolor='black')
    
#     # Add error bars showing min to max range
#     yerr_lower = metrics_df['avg_distance'] - metrics_df['min_distance']
#     yerr_upper = metrics_df['max_distance'] - metrics_df['avg_distance']
    
#     ax.errorbar(x, metrics_df['avg_distance'], 
#                yerr=[yerr_lower, yerr_upper],
#                fmt='none', ecolor='black', capsize=5, capthick=2, alpha=0.6,
#                label='Min-Max Range')
    
#     # Add value labels on bars
#     for i, (bar, val) in enumerate(zip(bars, metrics_df['avg_distance'])):
#         height = bar.get_height()
#         ax.text(bar.get_x() + bar.get_width()/2., height,
#                f'{val:.3f}',
#                ha='center', va='bottom', fontsize=9, fontweight='bold')
    
#     ax.set_xlabel('Trial Number', fontsize=12, fontweight='bold')
#     ax.set_ylabel('Cosine Distance', fontsize=12, fontweight='bold')
#     ax.set_title('Average Distance to Other Trials (with Min-Max Range)', 
#                 fontsize=14, fontweight='bold', pad=20)
#     ax.set_xticks(x)
#     ax.set_xticklabels([f"Trial {t}" for t in metrics_df['trial']])
#     ax.legend(fontsize=10)
#     ax.grid(axis='y', alpha=0.3)
    
#     plt.tight_layout()
#     plt.savefig(f'{output_dir}/trial_distances_comparison.png', dpi=300, bbox_inches='tight')
#     plt.close()
#     print(f"Trial distances comparison saved to: {output_dir}/trial_distances_comparison.png")
    
#     # Figure 4: Correlation heatmap of metrics
#     fig, ax = plt.subplots(figsize=(10, 8))
    
#     # Select numeric columns for correlation
#     numeric_cols = ['total_scheduled', 'avg_distance', 'min_distance', 
#                    'max_distance', 'avg_similarity'] + vaccine_cols
#     corr_matrix = metrics_df[numeric_cols].corr()
    
#     sns.heatmap(corr_matrix, annot=True, fmt='.2f', cmap='coolwarm', 
#                center=0, square=True, ax=ax, cbar_kws={'label': 'Correlation'})
    
#     ax.set_title('Correlation Matrix of All Metrics', fontsize=14, fontweight='bold', pad=20)
#     plt.tight_layout()
#     plt.savefig(f'{output_dir}/metrics_correlation_heatmap.png', dpi=300, bbox_inches='tight')
#     plt.close()
#     print(f"Metrics correlation heatmap saved to: {output_dir}/metrics_correlation_heatmap.png")

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
    
#     # Display summary
#     print("\n" + "=" * 80)
#     print("METRICS PER TRIAL")
#     print("=" * 80)
#     display_cols = ['trial', 'total_scheduled', 'avg_distance', 'avg_similarity']
#     print(metrics_df[display_cols].to_string(index=False))
#     print()
    
#     # Save detailed metrics
#     metrics_df.to_csv('/home/claude/trial_metrics_detailed.csv', index=False)
#     print("Detailed metrics saved to: trial_metrics_detailed.csv\n")
    
#     # Create visualizations
#     print("=" * 80)
#     print("CREATING BOX PLOT VISUALIZATIONS")
#     print("=" * 80)
#     create_boxplot_visualizations(metrics_df)
    
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

def create_boxplot_visualizations(metrics_df, output_dir):
    """Create comprehensive box plot visualizations"""
    
    # Create output directory
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    # Set style
    sns.set_style("whitegrid")
    plt.rcParams['figure.facecolor'] = 'white'
    
    # Get vaccine columns (exclude trial, filename, and metric columns)
    vaccine_cols = [col for col in metrics_df.columns 
                   if col not in ['trial', 'filename', 'total_scheduled', 
                                 'avg_distance', 'min_distance', 'max_distance', 'avg_similarity']]
    
    # Figure 1: Multi-panel box plots for all metrics
    fig, axes = plt.subplots(2, 3, figsize=(18, 12))
    fig.suptitle('Distribution of Metrics Across All Trials', fontsize=16, fontweight='bold', y=0.995)
    
    # Total Scheduled Periods
    ax = axes[0, 0]
    sns.boxplot(y=metrics_df['total_scheduled'], ax=ax, color='skyblue')
    sns.swarmplot(y=metrics_df['total_scheduled'], ax=ax, color='darkblue', alpha=0.6, size=8)
    ax.set_ylabel('Count', fontsize=11)
    ax.set_title('Total Scheduled Periods', fontsize=12, fontweight='bold')
    ax.grid(axis='y', alpha=0.3)
    
    # Average Distance to Other Files
    ax = axes[0, 1]
    sns.boxplot(y=metrics_df['avg_distance'], ax=ax, color='salmon')
    sns.swarmplot(y=metrics_df['avg_distance'], ax=ax, color='darkred', alpha=0.6, size=8)
    ax.set_ylabel('Distance', fontsize=11)
    ax.set_title('Avg Cosine Distance to Other Trials', fontsize=12, fontweight='bold')
    ax.grid(axis='y', alpha=0.3)
    
    # Average Similarity to Other Files
    ax = axes[0, 2]
    sns.boxplot(y=metrics_df['avg_similarity'], ax=ax, color='lightgreen')
    sns.swarmplot(y=metrics_df['avg_similarity'], ax=ax, color='darkgreen', alpha=0.6, size=8)
    ax.set_ylabel('Similarity', fontsize=11)
    ax.set_title('Avg Cosine Similarity to Other Trials', fontsize=12, fontweight='bold')
    ax.grid(axis='y', alpha=0.3)
    
    # Min Distance
    ax = axes[1, 0]
    sns.boxplot(y=metrics_df['min_distance'], ax=ax, color='plum')
    sns.swarmplot(y=metrics_df['min_distance'], ax=ax, color='purple', alpha=0.6, size=8)
    ax.set_ylabel('Distance', fontsize=11)
    ax.set_title('Min Distance to Any Other Trial', fontsize=12, fontweight='bold')
    ax.grid(axis='y', alpha=0.3)
    
    # Max Distance
    ax = axes[1, 1]
    sns.boxplot(y=metrics_df['max_distance'], ax=ax, color='peachpuff')
    sns.swarmplot(y=metrics_df['max_distance'], ax=ax, color='darkorange', alpha=0.6, size=8)
    ax.set_ylabel('Distance', fontsize=11)
    ax.set_title('Max Distance to Any Other Trial', fontsize=12, fontweight='bold')
    ax.grid(axis='y', alpha=0.3)
    
    # Summary statistics text
    ax = axes[1, 2]
    ax.axis('off')
    
    summary_text = f"""Summary Statistics:
    
Total Scheduled Periods:
  Mean: {metrics_df['total_scheduled'].mean():.1f}
  Std:  {metrics_df['total_scheduled'].std():.2f}
  
Avg Distance to Others:
  Mean: {metrics_df['avg_distance'].mean():.4f}
  Std:  {metrics_df['avg_distance'].std():.4f}
  
Avg Similarity to Others:
  Mean: {metrics_df['avg_similarity'].mean():.4f}
  Std:  {metrics_df['avg_similarity'].std():.4f}
  
Number of Trials: {len(metrics_df)}
"""
    
    ax.text(0.1, 0.5, summary_text, fontsize=11, verticalalignment='center',
            fontfamily='monospace', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.3))
    
    plt.tight_layout()
    plt.savefig(Path(output_dir) / 'metrics_boxplots.png', dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Metrics box plots saved")
    
    # Figure 2: Vaccine-specific scheduled periods
    fig, ax = plt.subplots(figsize=(14, 8))
    
    # Prepare data for grouped box plot
    vaccine_data = []
    for vaccine in vaccine_cols:
        for value in metrics_df[vaccine]:
            vaccine_data.append({'Vaccine': vaccine, 'Scheduled Periods': value})
    
    vaccine_df = pd.DataFrame(vaccine_data)
    
    sns.boxplot(data=vaccine_df, x='Vaccine', y='Scheduled Periods', ax=ax, palette='Set2')
    sns.swarmplot(data=vaccine_df, x='Vaccine', y='Scheduled Periods', ax=ax, 
                  color='black', alpha=0.5, size=6)
    
    ax.set_title('Scheduled Periods per Vaccine Across All Trials', 
                fontsize=14, fontweight='bold', pad=20)
    ax.set_xlabel('Vaccine Type', fontsize=12, fontweight='bold')
    ax.set_ylabel('Number of Scheduled Periods', fontsize=12, fontweight='bold')
    ax.grid(axis='y', alpha=0.3)
    plt.xticks(rotation=45, ha='right')
    
    plt.tight_layout()
    plt.savefig(Path(output_dir) / 'vaccine_schedules_boxplot.png', dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Vaccine schedules box plot saved")
    
    # Figure 3: Individual trial comparison (bar plot with error ranges)
    fig, ax = plt.subplots(figsize=(14, 8))
    
    x = np.arange(len(metrics_df))
    width = 0.8
    
    # Plot bars for each trial
    colors = plt.cm.viridis(np.linspace(0, 1, len(metrics_df)))
    bars = ax.bar(x, metrics_df['avg_distance'], width, 
                  label='Avg Distance', color=colors, alpha=0.7, edgecolor='black')
    
    # Add error bars showing min to max range
    yerr_lower = metrics_df['avg_distance'] - metrics_df['min_distance']
    yerr_upper = metrics_df['max_distance'] - metrics_df['avg_distance']
    
    ax.errorbar(x, metrics_df['avg_distance'], 
               yerr=[yerr_lower, yerr_upper],
               fmt='none', ecolor='black', capsize=5, capthick=2, alpha=0.6,
               label='Min-Max Range')
    
    # Add value labels on bars
    for i, (bar, val) in enumerate(zip(bars, metrics_df['avg_distance'])):
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height,
               f'{val:.3f}',
               ha='center', va='bottom', fontsize=9, fontweight='bold')
    
    ax.set_xlabel('Trial Number', fontsize=12, fontweight='bold')
    ax.set_ylabel('Cosine Distance', fontsize=12, fontweight='bold')
    ax.set_title('Average Distance to Other Trials (with Min-Max Range)', 
                fontsize=14, fontweight='bold', pad=20)
    ax.set_xticks(x)
    ax.set_xticklabels([f"Trial {t}" for t in metrics_df['trial']])
    ax.legend(fontsize=10)
    ax.grid(axis='y', alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(Path(output_dir) / 'trial_distances_comparison.png', dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Trial distances comparison saved")
    
    # Figure 4: Correlation heatmap of metrics
    fig, ax = plt.subplots(figsize=(10, 8))
    
    # Select numeric columns for correlation
    numeric_cols = ['total_scheduled', 'avg_distance', 'min_distance', 
                   'max_distance', 'avg_similarity'] + vaccine_cols
    corr_matrix = metrics_df[numeric_cols].corr()
    
    sns.heatmap(corr_matrix, annot=True, fmt='.2f', cmap='coolwarm', 
               center=0, square=True, ax=ax, cbar_kws={'label': 'Correlation'})
    
    ax.set_title('Correlation Matrix of All Metrics', fontsize=14, fontweight='bold', pad=20)
    plt.tight_layout()
    plt.savefig(Path(output_dir) / 'metrics_correlation_heatmap.png', dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  ✓ Metrics correlation heatmap saved")
    
    print(f"\n✓ All visualizations saved to {output_dir}/")

# Main execution
if __name__ == "__main__":
    print("="*80)
    print("F DATA ANALYSIS - BOX PLOT VISUALIZATIONS")
    print("="*80 + "\n")
    
    # Get current working directory
    base_dir = Path.cwd()
    print(f"Current working directory: {base_dir}\n")
    
    # Define paths
    input_dir = base_dir / 'Deterministic' / 'Model objective analysis' / 'quantity discount' / 'results' / 'buyer discounts' / '2 segments penta hexa' / 'SB'
    
    # Create analysis output directory
    analysis_dir = base_dir / 'analysis'
    analysis_dir.mkdir(exist_ok=True)
    
    plots_dir = analysis_dir / 'F_boxplots'
    
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
    
    # Display summary
    print("=" * 80)
    print("METRICS PER TRIAL")
    print("=" * 80)
    display_cols = ['trial', 'total_scheduled', 'avg_distance', 'avg_similarity']
    print(metrics_df[display_cols].to_string(index=False))
    print()
    
    # Save detailed metrics
    metrics_csv = analysis_dir / 'trial_metrics_detailed.csv'
    metrics_df.to_csv(metrics_csv, index=False)
    print(f"✓ Detailed metrics saved to: {metrics_csv}\n")
    
    # Create visualizations
    print("=" * 80)
    print("CREATING BOX PLOT VISUALIZATIONS")
    print("=" * 80)
    create_boxplot_visualizations(metrics_df, plots_dir)
    
    print("\n" + "=" * 80)
    print("ANALYSIS COMPLETE!")
    print("=" * 80)
    print(f"\nGenerated files in '{analysis_dir}':")
    print("  1. trial_metrics_detailed.csv - Detailed metrics for each trial")
    print(f"  2. {plots_dir.name}/ - 4 box plot visualizations")
    print("     - metrics_boxplots.png")
    print("     - vaccine_schedules_boxplot.png")
    print("     - trial_distances_comparison.png")
    print("     - metrics_correlation_heatmap.png")