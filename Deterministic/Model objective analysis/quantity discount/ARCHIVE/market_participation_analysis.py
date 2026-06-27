import json
import pandas as pd
import numpy as np
from pathlib import Path
import matplotlib.pyplot as plt
import seaborn as sns

# Set style
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (16, 10)

def load_all_q_data(directory):
    """Load Q data from all JSON files"""
    dir_path = Path(directory)
    
    # Check if directory exists
    if not dir_path.exists():
        print(f"Warning: Directory '{directory}' does not exist!")
        return []
    
    files = list(dir_path.glob("*.json"))
    print(f"Found {len(files)} JSON files in {directory}")
    
    all_data = []
    errors = []
    
    for file_path in sorted(files):
        try:
            with open(file_path, 'r') as f:
                data = json.load(f)
                
                # Check if 'Q' key exists
                if 'Q' not in data:
                    errors.append(f"  ⚠ {file_path.name}: Missing 'Q' key")
                    continue
                
                # Extract trial number from filename
                try:
                    trial_num = file_path.stem.split('trial_')[1].split('_')[0]
                except IndexError:
                    errors.append(f"  ⚠ {file_path.name}: Cannot extract trial number from filename")
                    continue
                
                all_data.append({
                    'trial': trial_num,
                    'Q': data['Q']
                })
                
        except json.JSONDecodeError as e:
            errors.append(f"  ✗ {file_path.name}: JSON decode error - {str(e)}")
        except Exception as e:
            errors.append(f"  ✗ {file_path.name}: {type(e).__name__} - {str(e)}")
    
    # Report results
    if errors:
        print(f"⚠ Encountered {len(errors)} error(s):")
        for error in errors:
            print(error)
    
    return all_data

def flatten_q_to_dataframe(all_data):
    """Convert nested Q dictionaries to flat DataFrame"""
    rows = []
    
    for trial_data in all_data:
        trial = trial_data['trial']
        Q = trial_data['Q']
        
        for vaccine, mfr_dict in Q.items():
            for manufacturer, start_dict in mfr_dict.items():
                for time_period_start, end_dict in start_dict.items():
                    for time_period_end, discount_dict in end_dict.items():
                        if discount_dict:
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

def analyze_market_participation(df):
    """Analyze market participation patterns"""
    
    # Create binary participation indicator (1 if quantity > 0, else 0)
    df['participates'] = (df['quantity'] > 0).astype(int)
    
    # Market share by manufacturer and discount level
    market_share = df.groupby(['manufacturer', 'discount_level'])['quantity'].sum().reset_index()
    total_by_discount = df.groupby('discount_level')['quantity'].sum()
    market_share['market_share_pct'] = market_share.apply(
        lambda x: (x['quantity'] / total_by_discount[x['discount_level']] * 100) if total_by_discount[x['discount_level']] > 0 else 0, 
        axis=1
    )
    
    # Participation rate by manufacturer and discount level
    participation = df.groupby(['manufacturer', 'discount_level']).agg({
        'participates': 'mean',  # Percentage of times they participate
        'quantity': ['count', 'sum', 'mean']
    }).reset_index()
    participation.columns = ['manufacturer', 'discount_level', 'participation_rate', 'opportunities', 'total_quantity', 'avg_quantity']
    participation['participation_rate'] *= 100  # Convert to percentage
    
    # Vaccine-specific participation
    vaccine_participation = df.groupby(['vaccine', 'discount_level']).agg({
        'participates': 'mean',
        'quantity': ['sum', 'mean']
    }).reset_index()
    vaccine_participation.columns = ['vaccine', 'discount_level', 'participation_rate', 'total_quantity', 'avg_quantity']
    vaccine_participation['participation_rate'] *= 100
    
    # Manufacturer-Vaccine combinations by discount
    mfr_vaccine_discount = df.groupby(['manufacturer', 'vaccine', 'discount_level']).agg({
        'participates': 'mean',
        'quantity': 'sum'
    }).reset_index()
    mfr_vaccine_discount.columns = ['manufacturer', 'vaccine', 'discount_level', 'participation_rate', 'total_quantity']
    mfr_vaccine_discount['participation_rate'] *= 100
    
    return market_share, participation, vaccine_participation, mfr_vaccine_discount

def create_market_visualizations(df, market_share, participation, vaccine_participation, mfr_vaccine_discount, output_dir):
    """Create comprehensive market participation visualizations"""
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    
    # 1. Market Share Heatmap by Manufacturer x Discount Level
    fig, ax = plt.subplots(figsize=(12, 10))
    pivot_share = market_share.pivot(index='manufacturer', columns='discount_level', values='market_share_pct')
    sns.heatmap(pivot_share, annot=True, fmt='.1f', cmap='YlGnBu', ax=ax, 
                cbar_kws={'label': 'Market Share (%)'}, linewidths=0.5)
    ax.set_title('Market Share by Manufacturer and Discount Level', fontsize=16, fontweight='bold', pad=20)
    ax.set_xlabel('Discount Level', fontsize=12)
    ax.set_ylabel('Manufacturer', fontsize=12)
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '01_market_share_heatmap.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 2. Participation Rate Heatmap by Manufacturer x Discount Level
    fig, ax = plt.subplots(figsize=(12, 10))
    pivot_part = participation.pivot(index='manufacturer', columns='discount_level', values='participation_rate')
    sns.heatmap(pivot_part, annot=True, fmt='.1f', cmap='RdYlGn', ax=ax, 
                cbar_kws={'label': 'Participation Rate (%)'}, linewidths=0.5)
    ax.set_title('Market Participation Rate by Manufacturer and Discount Level', fontsize=16, fontweight='bold', pad=20)
    ax.set_xlabel('Discount Level', fontsize=12)
    ax.set_ylabel('Manufacturer', fontsize=12)
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '02_participation_rate_heatmap.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 3. Stacked Bar Chart: Total Quantity by Discount Level (colored by manufacturer)
    fig, ax = plt.subplots(figsize=(14, 8))
    pivot_quantity = market_share.pivot(index='discount_level', columns='manufacturer', values='quantity').fillna(0)
    pivot_quantity.plot(kind='bar', stacked=True, ax=ax, colormap='tab20', edgecolor='black', linewidth=0.5)
    ax.set_title('Total Quantity Distribution by Discount Level and Manufacturer', fontsize=16, fontweight='bold', pad=20)
    ax.set_xlabel('Discount Level', fontsize=12)
    ax.set_ylabel('Total Quantity', fontsize=12)
    ax.legend(title='Manufacturer', bbox_to_anchor=(1.05, 1), loc='upper left', fontsize=9)
    plt.xticks(rotation=0)
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '03_quantity_by_discount_stacked.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 4. Bubble Chart: Participation Rate vs Market Share (sized by total quantity)
    fig, ax = plt.subplots(figsize=(14, 10))
    
    # Aggregate by manufacturer across all discount levels
    mfr_summary = df.groupby('manufacturer').agg({
        'quantity': 'sum',
        'participates': 'mean'
    }).reset_index()
    mfr_summary.columns = ['manufacturer', 'total_quantity', 'participation_rate']
    mfr_summary['participation_rate'] *= 100
    
    # Calculate overall market share
    total_quantity = mfr_summary['total_quantity'].sum()
    mfr_summary['market_share'] = (mfr_summary['total_quantity'] / total_quantity * 100)
    
    # Create bubble chart
    scatter = ax.scatter(mfr_summary['participation_rate'], 
                        mfr_summary['market_share'],
                        s=mfr_summary['total_quantity']/500,  # Size proportional to quantity
                        alpha=0.6, 
                        c=range(len(mfr_summary)), 
                        cmap='viridis',
                        edgecolors='black',
                        linewidth=1.5)
    
    # Add manufacturer labels
    for idx, row in mfr_summary.iterrows():
        ax.annotate(row['manufacturer'], 
                   (row['participation_rate'], row['market_share']),
                   fontsize=9, 
                   ha='center',
                   bbox=dict(boxstyle='round,pad=0.3', facecolor='white', alpha=0.7, edgecolor='gray'))
    
    ax.set_title('Market Participation vs Market Share by Manufacturer', fontsize=16, fontweight='bold', pad=20)
    ax.set_xlabel('Participation Rate (%)', fontsize=12)
    ax.set_ylabel('Market Share (%)', fontsize=12)
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '04_participation_vs_share_bubble.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 5. Vaccine Participation Heatmap by Discount Level
    fig, ax = plt.subplots(figsize=(10, 8))
    pivot_vaccine = vaccine_participation.pivot(index='vaccine', columns='discount_level', values='participation_rate')
    sns.heatmap(pivot_vaccine, annot=True, fmt='.1f', cmap='PuBu', ax=ax, 
                cbar_kws={'label': 'Participation Rate (%)'}, linewidths=0.5)
    ax.set_title('Vaccine Market Participation by Discount Level', fontsize=16, fontweight='bold', pad=20)
    ax.set_xlabel('Discount Level', fontsize=12)
    ax.set_ylabel('Vaccine', fontsize=12)
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '05_vaccine_participation_heatmap.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 6. Grouped Bar Chart: Average Quantity by Discount Level for Top Manufacturers
    fig, ax = plt.subplots(figsize=(14, 8))
    top_mfrs = participation.groupby('manufacturer')['total_quantity'].sum().nlargest(8).index
    top_data = participation[participation['manufacturer'].isin(top_mfrs)]
    
    pivot_avg = top_data.pivot(index='manufacturer', columns='discount_level', values='avg_quantity')
    pivot_avg.plot(kind='bar', ax=ax, colormap='Set2', edgecolor='black', linewidth=0.8)
    ax.set_title('Average Quantity per Participation by Discount Level (Top 8 Manufacturers)', 
                fontsize=16, fontweight='bold', pad=20)
    ax.set_xlabel('Manufacturer', fontsize=12)
    ax.set_ylabel('Average Quantity', fontsize=12)
    ax.legend(title='Discount Level', bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.xticks(rotation=45, ha='right')
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '06_avg_quantity_by_discount.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 7. Facet Grid: Manufacturer-Vaccine Participation by Discount
    # Select top manufacturers and vaccines for clarity
    top_vaccines = df.groupby('vaccine')['quantity'].sum().nlargest(6).index
    top_mfrs_for_facet = df.groupby('manufacturer')['quantity'].sum().nlargest(6).index
    
    facet_data = mfr_vaccine_discount[
        (mfr_vaccine_discount['vaccine'].isin(top_vaccines)) & 
        (mfr_vaccine_discount['manufacturer'].isin(top_mfrs_for_facet)) &
        (mfr_vaccine_discount['total_quantity'] > 0)
    ]
    
    fig, axes = plt.subplots(2, 3, figsize=(18, 12))
    axes = axes.flatten()
    
    for idx, vaccine in enumerate(sorted(top_vaccines)):
        ax = axes[idx]
        vaccine_data = facet_data[facet_data['vaccine'] == vaccine]
        
        if not vaccine_data.empty:
            pivot = vaccine_data.pivot(index='manufacturer', columns='discount_level', values='participation_rate').fillna(0)
            pivot.plot(kind='bar', ax=ax, colormap='viridis', edgecolor='black', linewidth=0.5)
            ax.set_title(f'{vaccine}', fontsize=12, fontweight='bold')
            ax.set_xlabel('')
            ax.set_ylabel('Participation Rate (%)', fontsize=10)
            ax.legend(title='Discount', fontsize=8, title_fontsize=9)
            ax.tick_params(axis='x', rotation=45, labelsize=9)
            ax.grid(True, alpha=0.3, axis='y')
    
    plt.suptitle('Manufacturer Participation by Discount Level across Top Vaccines', 
                fontsize=16, fontweight='bold', y=1.00)
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '07_vaccine_manufacturer_discount_facets.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 8. Line Plot: Market Share Evolution by Discount Level
    fig, ax = plt.subplots(figsize=(14, 8))
    
    # Get top 8 manufacturers by total quantity
    top_8_mfrs = market_share.groupby('manufacturer')['quantity'].sum().nlargest(8).index
    top_share_data = market_share[market_share['manufacturer'].isin(top_8_mfrs)]
    
    for mfr in top_8_mfrs:
        mfr_data = top_share_data[top_share_data['manufacturer'] == mfr].sort_values('discount_level')
        ax.plot(mfr_data['discount_level'], mfr_data['market_share_pct'], 
               marker='o', linewidth=2.5, markersize=8, label=mfr)
    
    ax.set_title('Market Share Evolution by Discount Level (Top 8 Manufacturers)', 
                fontsize=16, fontweight='bold', pad=20)
    ax.set_xlabel('Discount Level', fontsize=12)
    ax.set_ylabel('Market Share (%)', fontsize=12)
    ax.legend(title='Manufacturer', bbox_to_anchor=(1.05, 1), loc='upper left', fontsize=10)
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(Path(output_dir) / '08_market_share_evolution.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    print(f"\n✓ All market participation visualizations saved to {output_dir}/")

def create_summary_report(market_share, participation, vaccine_participation, output_file):
    """Generate market participation summary report"""
    with open(output_file, 'w') as f:
        f.write("="*80 + "\n")
        f.write("MARKET PARTICIPATION ANALYSIS REPORT\n")
        f.write("="*80 + "\n\n")
        
        # Top manufacturers by market share
        f.write("TOP 10 MANUFACTURERS BY TOTAL MARKET SHARE\n")
        f.write("-"*80 + "\n")
        top_mfrs = market_share.groupby('manufacturer')['quantity'].sum().sort_values(ascending=False).head(10)
        total = market_share['quantity'].sum()
        for mfr, qty in top_mfrs.items():
            share = (qty / total * 100)
            f.write(f"{mfr:.<40} {share:>8.2f}% (Qty: {qty:>15,.0f})\n")
        
        f.write("\n" + "="*80 + "\n\n")
        
        # Participation rates by discount level
        f.write("AVERAGE PARTICIPATION RATE BY DISCOUNT LEVEL\n")
        f.write("-"*80 + "\n")
        avg_part = participation.groupby('discount_level')['participation_rate'].mean().sort_index()
        for discount, rate in avg_part.items():
            f.write(f"Discount Level {discount}:............... {rate:>8.2f}%\n")
        
        f.write("\n" + "="*80 + "\n\n")
        
        # Most active manufacturers (highest participation rates)
        f.write("TOP 10 MANUFACTURERS BY PARTICIPATION RATE\n")
        f.write("-"*80 + "\n")
        avg_mfr_part = participation.groupby('manufacturer')['participation_rate'].mean().sort_values(ascending=False).head(10)
        for mfr, rate in avg_mfr_part.items():
            f.write(f"{mfr:.<40} {rate:>8.2f}%\n")
        
        f.write("\n" + "="*80 + "\n\n")
        
        # Vaccine participation summary
        f.write("VACCINE PARTICIPATION SUMMARY\n")
        f.write("-"*80 + "\n")
        vaccine_summary = vaccine_participation.groupby('vaccine').agg({
            'participation_rate': 'mean',
            'total_quantity': 'sum'
        }).sort_values('total_quantity', ascending=False)
        
        f.write(f"{'Vaccine':<20} {'Avg Part. Rate':>15} {'Total Quantity':>20}\n")
        f.write("-"*80 + "\n")
        for vaccine, row in vaccine_summary.iterrows():
            f.write(f"{vaccine:<20} {row['participation_rate']:>14.2f}% {row['total_quantity']:>20,.0f}\n")
        
        f.write("\n" + "="*80 + "\n")
    
    print(f"✓ Market participation report saved to {output_file}")

def main():
    print("="*80)
    print("MARKET PARTICIPATION ANALYSIS")
    print("="*80 + "\n")
    
    # Get current working directory
    base_dir = Path.cwd()
    print(f"Current working directory: {base_dir}\n")
    
    # Define paths relative to current directory
    input_dir = base_dir / 'Deterministic' / 'Model objective analysis' / 'quantity discount' / 'results' / 'buyer discounts' / '2 segments penta hexa' / 'SB'
    
    # Create analysis output directory
    analysis_dir = base_dir / 'analysis'
    analysis_dir.mkdir(exist_ok=True)
    
    plots_dir = analysis_dir / 'market_plots'
    
    # Load data
    print("Loading Q data from all files...")
    all_data = load_all_q_data(input_dir)
    print(f"✓ Loaded {len(all_data)} files\n")
    
    if len(all_data) == 0:
        print("\n⚠ WARNING: No data files found!")
        print(f"Looking in: {input_dir}")
        print("\nPlease check:")
        print("  1. The 'results/buyer discounts/2 segments/UG' directory exists")
        print("  2. There are JSON files in that directory")
        print("  3. The JSON files follow the expected naming pattern")
        return
    
    # Flatten to DataFrame
    print("Flattening nested dictionaries...")
    df = flatten_q_to_dataframe(all_data)
    print(f"✓ Created DataFrame with {len(df)} records\n")
    
    if len(df) == 0:
        print("\n⚠ WARNING: No records found in data!")
        print("The JSON files may not contain the expected 'Q' structure.")
        return
    
    # Analyze market participation
    print("Analyzing market participation patterns...")
    market_share, participation, vaccine_participation, mfr_vaccine_discount = analyze_market_participation(df)
    print("✓ Analysis complete\n")
    
    # Save detailed data
    print("Saving detailed market data...")
    market_share.to_csv(analysis_dir / 'market_share_by_discount.csv', index=False)
    participation.to_csv(analysis_dir / 'participation_by_manufacturer_discount.csv', index=False)
    vaccine_participation.to_csv(analysis_dir / 'vaccine_participation_by_discount.csv', index=False)
    mfr_vaccine_discount.to_csv(analysis_dir / 'manufacturer_vaccine_discount.csv', index=False)
    print("✓ Data files saved\n")
    
    # Create visualizations
    print("Creating market participation visualizations...")
    create_market_visualizations(df, market_share, participation, vaccine_participation, mfr_vaccine_discount, plots_dir)
    
    # Create summary report
    print("\nGenerating summary report...")
    report_path = analysis_dir / 'market_participation_report.txt'
    create_summary_report(market_share, participation, vaccine_participation, report_path)
    
    print("\n" + "="*80)
    print("ANALYSIS COMPLETE!")
    print("="*80)
    print(f"\nGenerated files in '{analysis_dir}':")
    print("  1. market_share_by_discount.csv")
    print("  2. participation_by_manufacturer_discount.csv")
    print("  3. vaccine_participation_by_discount.csv")
    print("  4. manufacturer_vaccine_discount.csv")
    print("  5. market_participation_report.txt")
    print(f"  6. {plots_dir.name}/ - 8 specialized visualizations")

if __name__ == "__main__":
    main()