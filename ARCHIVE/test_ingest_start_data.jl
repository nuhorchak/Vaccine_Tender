using DataFrames
using ExcelReaders

# Function to read Excel file and create F matrix
function process_excel_file(file_path)
    # Read Excel file
    df = DataFrame(readxlsheet(file_path, "Sheet1"))

    # Extract relevant columns
    antigens = df.Vaccine
    t_values = df.t
    tau_values = df.tau
    tender_lengths = [1, 2, 3, 4, 5]

    # Get unique antigens
    unique_antigens = unique(antigens)

    # Initialize F matrix
    F = zeros(Int, length(unique_antigens), length(tender_lengths))

    # Assign values to F based on conditions using only "t" and "tau"
    for (i, antigen) in enumerate(unique_antigens)
        antigen_indices = findall(x -> x == antigen, antigens)
        
        for (j, tender_length) in enumerate(tender_lengths)
            F[i, j] = any((t_values[antigen_indices] .== tender_length) .& (tau_values[antigen_indices] .== tender_length))
        end
    end

    return F
end

# Example usage
file_path = "tenders_start.xlsx"
F_matrix = process_excel_file(file_path)
print(F_matrix)

# F_matrix now contains the desired values with antigen indexing using only "t" and "tau"
