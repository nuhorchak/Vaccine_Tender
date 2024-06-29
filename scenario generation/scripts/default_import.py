import sys, os, glob, time, socket
from loguru import logger
from tabulate import tabulate
import pandas as pd
import numpy as np

# Add the path to the code directory to the system path
code_path = "/Users/htbui/Active Projects/Vaccine Tender/Github/Vaccine_Tender/scenario generation"
Github_path = "/Users/htbui/Active Projects/Vaccine Tender/Github/Vaccine_Tender"

if code_path not in sys.path:
    sys.path.insert(0, code_path)

image_path = f"{Github_path}/visualization"
# data_path = "/Users/htbui/Active Projects/Vaccine Tender/data"

host_name = socket.gethostname()
cpu_count = os.cpu_count()
memory_available = int(os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / (1024.0**3))
python_version = sys.version.split()[0]
conda_env_name = os.environ["CONDA_DEFAULT_ENV"]

class bcolors:
    HEADER = "\033[95m"
    OKBLUE = "\033[94m"
    OKGREEN = "\033[92m"
    WARNING = "\033[93m"
    FAIL = "\033[91m"
    ENDC = "\033[0m"
    BOLD = "\033[1m"
    UNDERLINE = "\033[4m"

d3_colors = ['#1F77B4', '#FF7F0E', '#2CA02C', '#D62728', '#9467BD', '#8C564B', '#E377C2', '#7F7F7F', '#BCBD22', '#17BECF']

def print_machine_info():

    data = [
        ["Host name", host_name],
        ["CPU count", cpu_count],
        ["Memory available", f"{memory_available} GB"],
        ["Python version", python_version],
        ["Conda environment", conda_env_name],
    ]

    # Use tabulate to format the data
    table = tabulate(data, tablefmt="rounded_outline")

    # Print the table using logger
    logger.info(f"\n{table}")


def format_time(elapsed_seconds):
    """Formats time based on the duration (in seconds)."""
    if elapsed_seconds >= 3600:
        # Format as hours and minutes if more than an hour
        hours = elapsed_seconds // 3600
        minutes = (elapsed_seconds % 3600) // 60
        return f"{hours}h{minutes}m"
    else:
        # Format as minutes and seconds otherwise
        minutes = elapsed_seconds // 60
        seconds = elapsed_seconds % 60
        return f"{minutes}m{seconds}s"


def log_format(record):
    """Custom log format for the logger."""
    # Format the log message with fixed width and centered alignment
    level = f"{record['level'].name:^8}"  # Center within 8 characters
    total_time_str = format_time(record["elapsed"].seconds)
    total_time = f"{total_time_str:^8}"  # Center within 8 characters

    return f"| {level} | Total: {total_time} | {record['message']}\n"


# Set up the logger with some initial settings
logger.remove()  # Remove the default handler
logger.add(
    f"{code_path}/logs/running.log",
    colorize=True,
    rotation="20 MB",
    compression="zip",
    backtrace=True,
    diagnose=True,
    format=log_format,
)
logger.add(
    sys.stderr,
    colorize=True,
    format=log_format,
    level="DEBUG",
)


# LoguruAdapter class definition
class LoguruAdapter:
    def __init__(self):
        self.buffer = ""

    def write(self, message):
        self.buffer += message
        if "\n" in self.buffer:
            lines = self.buffer.split("\n")
            for line in lines[:-1]:
                logger.info(line.strip())
            self.buffer = lines[-1]

    def flush(self):
        pass

    def __enter__(self):
        sys.stdout = self
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        sys.stdout = sys.__stdout__


# Create the LoguruAdapter instance
loguru_adapter = LoguruAdapter()