import sys
from io import BytesIO
from math import floor, log

import matplotlib.colors as mcolors
import matplotlib.dates as mdates
import matplotlib.gridspec as gridspec
import matplotlib.patches as patches
import matplotlib.patheffects as path_effects
import matplotlib.pyplot as plt
import plotly
import plotly.express as px
import plotly.graph_objects as go
import seaborn as sns
import seaborn.objects as so
from anytree.exporter import UniqueDotExporter
from flexitext import flexitext
from IPython.display import HTML, display
from matplotlib.collections import PolyCollection
from matplotlib.dates import DateFormatter
from matplotlib.lines import Line2D
from matplotlib.ticker import (FixedLocator, FormatStrFormatter, FuncFormatter,
                               MaxNLocator, MultipleLocator,
                               StrMethodFormatter)
from PIL import Image
from scripts.default_import import *

ext_path_effects = [path_effects.withStroke(linewidth=2, foreground="white")]

d3_colors = [
    "#1F77B4",
    "#FF7F0E",
    "#2CA02C",
    "#D62728",
    "#9467BD",
    "#8C564B",
    "#E377C2",
    "#7F7F7F",
    "#BCBD22",
    "#17BECF",
]

# Set the default style for the Matplotlib plots
plt.rcParams.update(
    {
        "font.family": "serif",
        "font.serif": "CMU Serif",
        "text.usetex": True,
        "text.latex.preamble": r"\usepackage{amsmath}",
        "font.size": 12,
        "font.weight": "normal",
        "figure.titlesize": "medium",
        "xtick.color": "black",
        "ytick.color": "black",
        "axes.labelcolor": "black",
        "text.color": "black",
        "savefig.dpi": 300,
        "figure.dpi": 150,
        "savefig.bbox": "tight",
    }
)

#! MATPLOTLIB
def human_format_yaxis(number, pos):
    if number == 0:  # Check for 0 to avoid log(0)
        return "0"

    units = ["", "K", "M", "B", "T", "P"]
    k = 1000.0
    # Preventing negative values for magnitude when number is between 0 and 1
    magnitude = int(floor(log(max(number, 1), k)))
    return f"{number / k**magnitude:.2f}{units[magnitude]}"


def add_grid(
    ax, grid_axis: str = "both", thousand_sep: bool = False, human_readable: bool = False, include_legend: bool = False
):
    ax.set_axisbelow(True)
    ax.grid(True, which="both", axis=grid_axis, ls="--", c="0.8")
    ax.spines.right.set_visible(False)
    ax.spines.top.set_visible(False)
    ax.yaxis.set_major_formatter(StrMethodFormatter("{x:,.0f}")) if thousand_sep else None
    (
        ax.legend(loc="best", fancybox=True, framealpha=1, borderpad=0.5, facecolor="white", fontsize=10)
        if include_legend
        else None
    )
    ax.yaxis.set_major_formatter(FuncFormatter(human_format_yaxis)) if human_readable else None

