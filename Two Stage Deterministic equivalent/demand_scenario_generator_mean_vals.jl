#example - creates 2 scenarios, from the current random CI's, and saves to excel in the same folder it is run
#random_data = data_generation(2, "../DATA/antigen_CI_Random_generator.xlsx", true)


using DataFrames
using XLSX
using Distributions
using Random

#generates random normal data, given parameters avg, sd, lower, upper (bounds0)
function number_generation(avg, sd, lower, upper)
    return rand(Normal(avg, sd)) |> x -> clamp(x, lower, upper)
end

#calculat the average of a list of dataframes
function average_dataframes(df_list::Vector{DataFrame})
    # Ensure there is at least one dataframe in the list
    if length(df_list) == 0
        error("No dataframes provided.")
    end

    # Separate the text column from the first dataframe
    name_column = df_list[1].Vaccine

    # Ensure all dataframes have the same dimensions (excluding the first column)
    for df in df_list
        if size(df[!, 2:end]) != size(df_list[1][!, 2:end])
            error("All dataframes must have the same dimensions for element-wise averaging.")
        end
    end

    # Initialize the result dataframe with the text column
    df_combined = DataFrame(Vaccine = name_column)

    # Calculate the average for each numeric column
    num_dataframes = length(df_list)
    for col in names(df_list[1])[2:end]
        combined_col = zeros(size(df_list[1], 1))
        for df in df_list
            combined_col .+= df[!, col]
        end
        df_combined[!, col] = combined_col ./ num_dataframes
    end

    return df_combined
end

#= Generate data, using the random number generator, and mean value calculator
n is an integer, the number of datasets to generate
filepath is the location of the excel data to generate random numbers (CI file)
save_to_excel is a boolean, to save to excel when true, or just create a memory object
mean_value is a boolean, which calculates the average of all DFs when true
RETURNS: when mean_value is true, ther eare 2 returns, the list of DFs, and the mean value DF
=#
function data_generation(n::Integer, filepath::String, save_to_excel::Bool, mean_value::Bool)
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
        # Set the random seed
        Random.seed!(scenario)
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
        
        # Transpose data to match inputs
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

    # Initialize mean_df
    mean_df = DataFrame()

    # Calculate the mean value if the flag is true
    if mean_value
        mean_df = average_dataframes(random_demand_data)
    end

    # Save to Excel if the flag is true
    if save_to_excel
        # Save the list of dataframes
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
        
        # Save the mean dataframe if mean_value is true
        if mean_value
            XLSX.openxlsx("mean_value.xlsx", mode="w") do xf
                sheet = xf[1]
                XLSX.rename!(sheet, "Mean_Scenario")
                XLSX.writetable!(sheet, mean_df)
            end
        end
    end

    if mean_value
        return random_demand_data, mean_df
    else
        return random_demand_data
    end
end
