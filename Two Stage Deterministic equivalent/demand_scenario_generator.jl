#example - creates 2 scenarios, from the current random CI's, and saves to excel in the same folder it is run
#random_data = data_generation(2, "../DATA/antigen_CI_Random_generator.xlsx", true)


using Distributions
using Random
using XLSX
using DataFrames

function number_generation(avg::Float64, sd::Float64, lower_bound::Float64, upper_bound::Float64)
    dist = Normal(avg, sd)
    quantile_value = rand(dist)
    return clamp(quantile_value, lower_bound, upper_bound)
end

# function number_generation(avg::Float64, sd::Float64, lower::Float64, upper::Float64)::Float64
#     # Assuming a normal distribution for number generation, truncated between lower and upper bounds
#     while true
#         num = randn() * sd + avg
#         if lower <= num <= upper
#             return num
#         end
#     end
# end

function data_generation(n::Integer, filepath::String, save_to_excel::Bool)
    println("Generating $n datasets!")
    # Load the workbook and get all sheet names except the last one
    workbook = XLSX.readxlsx(filepath)
    sheetnames = XLSX.sheetnames(workbook)[1:end-1]

    # Pre-read all sheets into dataframes
    dataframes = Dict{String, DataFrame}()
    for sheet in sheetnames
        dataframes[sheet] = DataFrame(XLSX.readtable(filepath, sheet))
    end

    # Init array to store 1 to N dataframe forecasts
    random_demand_data = Vector{DataFrame}(undef, n)
    sheet_names = []

    for scenario in 1:n
        random_demand_df = DataFrame()
        
        
        for (sheet, df) in dataframes
            new_column_data = Float64[]
            for row in eachrow(df)
                lower, upper, avg, sd = row
                result = number_generation(avg, sd, lower, upper)
                push!(new_column_data, result)
            end
            random_demand_df[!, sheet] = new_column_data
        end
        
        #transpose data to match inputs
        column_headers = names(random_demand_df)
        # Transpose the DataFrame using permutedims
        df_transposed = permutedims(random_demand_df)
        # Create a mapping for new column names based on their indices
        new_column_names = Dict(names(df_transposed)[i] => (string(i)) for i in 1:length(names(df_transposed)))
        # Rename columns dynamically
        rename!(df_transposed, new_column_names)
        insertcols!(df_transposed, 1, :Vaccine => column_headers)

        random_demand_data[scenario] = df_transposed
        push!(sheet_names, "Scenario_$scenario")
    end

    # Save to Excel if the flag is true
    XLSX.openxlsx("generated_random_demand_scenarios.xlsx", mode="w") do xf
        for i in eachindex(sheet_names)
            sheet_name = sheet_names[i]
            df = random_demand_data[i]
            
            if i == firstindex(sheet_names)
                sheet = xf[1]
                XLSX.rename!(sheet, sheet_name)
                XLSX.writetable!(sheet, df)
            else
                sheet = XLSX.addsheet!(xf, sheet_name)
                XLSX.writetable!(sheet, df)        
            end
        end
    end

    return random_demand_data 
end