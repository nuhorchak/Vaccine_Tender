using JSON

def split_bounds(data, exclude_first_n=4):
    """Splits the given data into upper and lower bound lists, 
    excludes the first N points, and plots them."""
    lb, ub = data['lb'][exclude_first_n:], data['ub'][exclude_first_n:]
   
    return lb, ub  # Return the split data if needed