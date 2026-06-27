import json
import pandas as pd
import numpy as np
from pathlib import Path
import matplotlib.pyplot as plt
import seaborn as sns
from collections import defaultdict
import os

# Set style for plots
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (14, 8)

def load_all_q_data(directory):
    """Load Q data from all JSON files in directory"""
    dir_path = Path(directory)
    
    # Check if directory exists
    if not dir_path.exists():
        print(f"Warning: Directory '{directory}' does not exist!")
        return []
    
    files = list(dir_path.glob("*.json"))
    print(f"Found {len(files)} JSON files in {directory}")
    
    all_data = []
    
    for file_path in sorted(files):
        with open(file_path, 'r') as f:
            data = json.load(f)
            trial_num = file_path.stem.split('trial_')[1].split('_')[0]
            all_data.append({
                'trial': trial_num,
                'filename': file_path.name,
                'Q': data['Q']
            })
    
    return all_data

def flatten_q_to_dataframe(all_data):
    """Convert nested Q dictionaries to a flat DataFrame"""
    rows = []
    
    for trial_data in all_data:
        trial = trial_data['trial']
        Q = trial_data['Q']
        
        for vaccine, mfr_dict in Q.items():
            for manufacturer, start_dict in mfr_dict.items():
                for time_period_start, end_dict in start_dict.items():
                    for time_period_end, discount_dict in end_dict.items():
                        if discount_dict:  # Skip empty dicts
                            for discount_level, quantity in discount_dict.items():
                                rows.append({
                                    'trial': trial,
                                    'vaccine': vaccine,
                                    'manufacturer': manufacturer,
                                    'time_period_start': int(time_period_start),
                                    'time_period_end': int(time_period_end),
                                    'discount_level': discount_level,
                                    'quantity': quantity
                                })
    
    return pd.DataFrame(rows)

def compute_statistics(df):
    """Compute comprehensive statistics"""
    stats = {}
    
    # Overall statistics
    stats['overall'] = {
        'total_records': len(df),
        'mean_quantity': df['quantity'].mean(),
        'median_quantity': df['quantity'].median(),
        'std_quantity': df['quantity'].std(),
        'min_quantity': df['quantity'].min(),
        'max_quantity': df['quantity'].max(),
        'sum_quantity': df['quantity'].sum(),
        'non_zero_pct': (df['quantity'] > 0).sum() / len(df) * 100
    }
    
    # By vaccine
    stats['by_vaccine'] = df.groupby('vaccine')['quantity'].agg([
        'count', 'mean', 'median', 'std', 'min', 'max', 'sum'
    ]).round(2)
    
    # By manufacturer
    stats['by_manufacturer'] = df.groupby('manufacturer')['quantity'].agg([
        'count', 'mean', 'median', 'std', 'min', 'max', 'sum'
    ]).round(2)
    
    # By time period start
    stats['by_time_start'] = df.groupby('time_period_start')['quantity'].agg([
        'count', 'mean', 'median', 'std', 'min', 'max', 'sum'
    ]).round(2)
    
    # By time period end
    stats['by_time_end'] = df.groupby('time_period_end')['quantity'].agg([
        'count', 'mean', 'median', 'std', 'min', 'max', 'sum'
    ]).round(2)
    
    # By discount level
    stats['by_discount'] = df.groupby('discount_level')['quantity'].agg([
        'count', 'mean', 'median', 'std', 'min', 'max', 'sum'
    ]).round(2)
    
    # By trial
    stats['by_trial'] = df.groupby('trial')['quantity'].agg([
        'count', 'mean', 'median', 'std', 'min', 'max', 'sum'
    ]).round(2)
    
    # By time period duration (end - start)
    df['period_duration'] = df['time_period_end'] - df['time_period_start']
    stats['by_duration'] = df.groupby('period_duration')['quantity'].agg([
        'count', 'mean', 'median', 'std', 'min', 'max', 'sum'
    ]).round(2)
    
    return stats

def create_visualizations(df, output_dir):
    """Create comprehensive visualizations"""
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    # 1. Distribution of quantities
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    
    # Histogram
    df[df['quantity'] > 0]['quantity'].hist(bins=50, ax=axes[0], edgecolor='black')
    axes[0].set_title('Distribution of Non-Zero Quantities', fontsize=14, fontweight='bold')
    axes[0].set_xlabel('Quantity')
    axes[0].set_ylabel('Frequency')
    
    # Box plot
    df[df['quantity'] > 0].boxplot(column='quantity', ax=axes[1])
    axes[1].set_title('Box Plot of Non-Zero Quantities', fontsize=14, fontweight='bold')
    axes[1].set_ylabel('Quantity')
    
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '01_quantity_distribution.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 2. Quantities by Vaccine
    fig, ax = plt.subplots(figsize=(12, 6))
    vaccine_data = df.groupby('vaccine')['quantity'].sum().sort_values(ascending=False)
    vaccine_data.plot(kind='bar', ax=ax, color='steelblue', edgecolor='black')
    ax.set_title('Total Quantity by Vaccine Type', fontsize=14, fontweight='bold')
    ax.set_xlabel('Vaccine')
    ax.set_ylabel('Total Quantity')
    plt.xticks(rotation=45, ha='right')
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '02_quantity_by_vaccine.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 3. Quantities by Manufacturer
    fig, ax = plt.subplots(figsize=(10, 6))
    mfr_data = df.groupby('manufacturer')['quantity'].sum().sort_values(ascending=False)
    mfr_data.plot(kind='bar', ax=ax, color='coral', edgecolor='black')
    ax.set_title('Total Quantity by Manufacturer', fontsize=14, fontweight='bold')
    ax.set_xlabel('Manufacturer')
    ax.set_ylabel('Total Quantity')
    plt.xticks(rotation=45, ha='right')
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '03_quantity_by_manufacturer.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 4. Quantities over Time (by start period)
    fig, ax = plt.subplots(figsize=(12, 6))
    time_data = df.groupby('time_period_start')['quantity'].sum().sort_index()
    ax.plot(time_data.index, time_data.values, marker='o', linewidth=2, markersize=8, color='green')
    ax.set_title('Total Quantity by Time Period Start', fontsize=14, fontweight='bold')
    ax.set_xlabel('Time Period Start')
    ax.set_ylabel('Total Quantity')
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '04_quantity_by_time_start.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 5. Heatmap: Vaccine x Manufacturer
    fig, ax = plt.subplots(figsize=(12, 8))
    pivot = df.groupby(['vaccine', 'manufacturer'])['quantity'].sum().unstack(fill_value=0)
    sns.heatmap(pivot, annot=True, fmt='.0f', cmap='YlOrRd', ax=ax, cbar_kws={'label': 'Total Quantity'})
    ax.set_title('Quantity Heatmap: Vaccine × Manufacturer', fontsize=14, fontweight='bold')
    ax.set_xlabel('Manufacturer')
    ax.set_ylabel('Vaccine')
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '05_vaccine_manufacturer_heatmap.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 6. Comparison across trials
    fig, ax = plt.subplots(figsize=(10, 6))
    trial_data = df.groupby('trial')['quantity'].sum().sort_index()
    trial_data.plot(kind='bar', ax=ax, color='purple', edgecolor='black')
    ax.set_title('Total Quantity by Trial', fontsize=14, fontweight='bold')
    ax.set_xlabel('Trial')
    ax.set_ylabel('Total Quantity')
    plt.xticks(rotation=0)
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '06_quantity_by_trial.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 7. Quantities by Discount Level
    fig, ax = plt.subplots(figsize=(8, 6))
    discount_data = df.groupby('discount_level')['quantity'].sum().sort_values(ascending=False)
    discount_data.plot(kind='bar', ax=ax, color='teal', edgecolor='black')
    ax.set_title('Total Quantity by Discount Level', fontsize=14, fontweight='bold')
    ax.set_xlabel('Discount Level')
    ax.set_ylabel('Total Quantity')
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '07_quantity_by_discount.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 8. Quantities by Time Period Duration
    df['period_duration'] = df['time_period_end'] - df['time_period_start']
    fig, ax = plt.subplots(figsize=(10, 6))
    duration_data = df.groupby('period_duration')['quantity'].sum().sort_index()
    duration_data.plot(kind='bar', ax=ax, color='orange', edgecolor='black')
    ax.set_title('Total Quantity by Time Period Duration', fontsize=14, fontweight='bold')
    ax.set_xlabel('Period Duration (End - Start)')
    ax.set_ylabel('Total Quantity')
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '08_quantity_by_duration.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 9. Heatmap: Time Period Start x End
    fig, ax = plt.subplots(figsize=(10, 10))
    time_pivot = df.groupby(['time_period_start', 'time_period_end'])['quantity'].sum().unstack(fill_value=0)
    sns.heatmap(time_pivot, annot=True, fmt='.0f', cmap='viridis', ax=ax, cbar_kws={'label': 'Total Quantity'})
    ax.set_title('Quantity Heatmap: Time Period Start × End', fontsize=14, fontweight='bold')
    ax.set_xlabel('Time Period End')
    ax.set_ylabel('Time Period Start')
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '09_time_period_heatmap.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    print(f"\n✓ All visualizations saved to {output_dir}/")

def generate_report(stats, df, output_file):
    """Generate a comprehensive text report"""
    with open(output_file, 'w') as f:
        f.write("="*80 + "\n")
        f.write("STATISTICAL ANALYSIS REPORT - Q Data\n")
        f.write("="*80 + "\n\n")
        
        # Overall Statistics
        f.write("OVERALL STATISTICS\n")
        f.write("-"*80 + "\n")
        for key, value in stats['overall'].items():
            f.write(f"{key:.<40} {value:>15.2f}\n")
        
        f.write("\n" + "="*80 + "\n\n")
        
        # By Vaccine
        f.write("STATISTICS BY VACCINE\n")
        f.write("-"*80 + "\n")
        f.write(stats['by_vaccine'].to_string())
        
        f.write("\n\n" + "="*80 + "\n\n")
        
        # By Manufacturer
        f.write("STATISTICS BY MANUFACTURER\n")
        f.write("-"*80 + "\n")
        f.write(stats['by_manufacturer'].to_string())
        
        f.write("\n\n" + "="*80 + "\n\n")
        
        # By Time Period Start
        f.write("STATISTICS BY TIME PERIOD START\n")
        f.write("-"*80 + "\n")
        f.write(stats['by_time_start'].to_string())
        
        f.write("\n\n" + "="*80 + "\n\n")
        
        # By Time Period End
        f.write("STATISTICS BY TIME PERIOD END\n")
        f.write("-"*80 + "\n")
        f.write(stats['by_time_end'].to_string())
        
        f.write("\n\n" + "="*80 + "\n\n")
        
        # By Discount Level
        f.write("STATISTICS BY DISCOUNT LEVEL\n")
        f.write("-"*80 + "\n")
        f.write(stats['by_discount'].to_string())
        
        f.write("\n\n" + "="*80 + "\n\n")
        
        # By Time Period Duration
        f.write("STATISTICS BY TIME PERIOD DURATION (END - START)\n")
        f.write("-"*80 + "\n")
        f.write(stats['by_duration'].to_string())
        
        f.write("\n\n" + "="*80 + "\n\n")
        
        # By Trial
        f.write("STATISTICS BY TRIAL\n")
        f.write("-"*80 + "\n")
        f.write(stats['by_trial'].to_string())
        
        f.write("\n\n" + "="*80 + "\n")
    
    print(f"\n✓ Report saved to {output_file}")

def main():
    # Get current working directory
    base_dir = Path.cwd()
    print(f"Current working directory: {base_dir}\n")
    
    # Define paths relative to current directory
    # Adjust this path to where your JSON files are located
    input_dir = base_dir / 'Deterministic' / 'Model objective analysis' / 'quantity discount' / 'results' / 'buyer discounts' / '2 segments penta hexa' / 'SB'
    
    # Create analysis output directory
    analysis_dir = base_dir / 'analysis'
    analysis_dir.mkdir(exist_ok=True)
    
    plots_dir = analysis_dir / 'Q_plots'
    
    # Load data
    print("Loading Q data from all files...")
    all_data = load_all_q_data(input_dir)
    print(f"✓ Loaded {len(all_data)} files")
    
    if len(all_data) == 0:
        print("\n⚠ WARNING: No data files found!")
        print(f"Looking in: {input_dir}")
        print("\nPlease check:")
        print("  1. The 'results/buyer discounts/2 segments/UG' directory exists")
        print("  2. There are JSON files in that directory")
        print("  3. The JSON files follow the 'trial_X_*.json' naming pattern")
        return
    
    # Flatten to DataFrame
    print("\nFlattening nested dictionaries to DataFrame...")
    df = flatten_q_to_dataframe(all_data)
    print(f"✓ Created DataFrame with {len(df)} records")
    
    if len(df) == 0:
        print("\n⚠ WARNING: No records found in data!")
        print("The JSON files may not contain the expected 'Q' structure.")
        return
    
    # Save raw data
    csv_path = analysis_dir / 'q_data_flattened.csv'
    df.to_csv(csv_path, index=False)
    print(f"✓ Saved flattened data to {csv_path}")
    
    # Compute statistics
    print("\nComputing statistics...")
    stats = compute_statistics(df)
    print("✓ Statistics computed")
    
    # Generate report
    print("\nGenerating text report...")
    report_path = analysis_dir / 'statistical_report.txt'
    generate_report(stats, df, report_path)
    
    # Create visualizations
    print("\nCreating visualizations...")
    create_visualizations(df, plots_dir)
    
    # Save statistics to Excel
    print("\nSaving statistics to Excel...")
    excel_path = analysis_dir / 'q_statistics.xlsx'
    with pd.ExcelWriter(excel_path, engine='openpyxl') as writer:
        stats['by_vaccine'].to_excel(writer, sheet_name='By Vaccine')
        stats['by_manufacturer'].to_excel(writer, sheet_name='By Manufacturer')
        stats['by_time_start'].to_excel(writer, sheet_name='By Time Start')
        stats['by_time_end'].to_excel(writer, sheet_name='By Time End')
        stats['by_discount'].to_excel(writer, sheet_name='By Discount Level')
        stats['by_duration'].to_excel(writer, sheet_name='By Duration')
        stats['by_trial'].to_excel(writer, sheet_name='By Trial')
    print(f"✓ Statistics saved to {excel_path}")
    
    print("\n" + "="*80)
    print("ANALYSIS COMPLETE!")
    print("="*80)
    print(f"\nGenerated files in '{analysis_dir}':")
    print("  1. q_data_flattened.csv - Raw flattened data")
    print("  2. statistical_report.txt - Comprehensive text report")
    print("  3. q_statistics.xlsx - Statistics in Excel format")
    print(f"  4. {plots_dir.name}/ - 9 visualization charts")

if __name__ == "__main__":
    main()