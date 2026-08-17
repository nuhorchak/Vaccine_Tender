"""
    create_vaccine_data()

Generates data structures related to antigens, vaccines, producers, and their relationships.

# Returns:
- `A::Vector`: List of antigens (e.g., "Measles", "Mumps").
- `V::Vector`: List of vaccines (e.g., "M", "MR").
- `A_v::Dict{String, Vector}`: Mapping of vaccines to the antigens they protect against.
- `P::Vector`: List of producers (e.g., "Serum_Institute").
- `P_v::Dict{String, Vector}`: Mapping of vaccines to the producers that manufacture them.
- `V_a::Dict{String, Vector}`: Mapping of antigens to vaccines protecting against them.
- `V_p::Dict{String, Vector}`: Mapping of producers to vaccines they produce.
- `P_a::Dict{String, Vector}`: Mapping of antigens to producers that manufacture vaccines protecting against them.
- `A_p::Dict{String, Vector}`: Mapping of producers to antigens their vaccines protect against.
- `capacity_category::Dict{String, Vector}`: Classification of producers by production capacity ("Small", "Medium", "Large").
- `vaccine_category::Dict{String, Vector}`: Classification of vaccines into categories ("MMR-based", "Td-based", "Single").
- `antigen_category::Dict{String, Vector}`: Classification of antigens into categories ("MMR-based", "Td-based", "Single").
"""
function create_vaccine_data()
    # List of antigens
    A = ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio", "HPV", "Rotavirus", "PCV"]
    # ["Measles", "Mumps", "Rubella", "Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio", "HPV", "Rotavirus", "PCV"]

    # List of vaccines
    # V = ["TT", "HepB",  "IPV", "OPV", "DT", "Td", "DTwP", "DTwP-Hib", "HPV", "Rotavirus", "PCV"]#, "Hib"]
    V = ["TT", "HepB",  "IPV", "OPV", "DT", "Td", "DTwP", "DTwP-Hib", "Penta", "Hexa", "HPV", "Rotavirus", "PCV"] #"Hib",
    # ["M", "MR", "MMR", "TT", "HepB",  "IPV", "OPV", "DT", "Td", "DTwP", "DTwP-Hib", "Penta", "Hexa", "HPV", "Rotavirus", "PCV"]

    # Mapping of vaccines to antigens
    A_v = Dict(
        "TT" => ["Tetanus"],
        "HepB" => ["Hepatitis_B"], "IPV" => ["Polio"], "OPV" => ["Polio"], "DT" => ["Diphtheria", "Tetanus"],
        "Td" => ["Diphtheria", "Tetanus"], "DTwP" => ["Diphtheria", "Tetanus", "Pertussis"], "DTwP-Hib" => ["Diphtheria", "Tetanus", "Pertussis", "Hib"],
        "Penta" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib"], "Hexa" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio"],
        "HPV" => ["HPV"], "Rotavirus" => ["Rotavirus"], "PCV" => ["PCV"],# "Hib" => ["Hib"],
    )

        #     "TT" => ["Tetanus"],
        # "HepB" => ["Hepatitis_B"], "IPV" => ["Polio"], "OPV" => ["Polio"], "DT" => ["Diphtheria", "Tetanus"],
        # "Td" => ["Diphtheria", "Tetanus"], "DTwP" => ["Diphtheria", "Tetanus", "Pertussis"], "DTwP-Hib" => ["Diphtheria", "Tetanus", "Pertussis", "Hib"],
        # "Penta" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib"], "Hexa" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio"],
        # "HPV" => ["HPV"], "Rotavirus" => ["Rotavirus"], "PCV" => ["PCV"] # "Hib" => ["Hib"],

    #     A_v = Dict(
    #     "M" => ["Measles"], "MR" => ["Measles", "Rubella"], "MMR" => ["Measles", "Mumps", "Rubella"], "TT" => ["Tetanus"],
    #     "HepB" => ["Hepatitis_B"], "IPV" => ["Polio"], "OPV" => ["Polio"], "DT" => ["Diphtheria", "Tetanus"],
    #     "Td" => ["Diphtheria", "Tetanus"], "DTwP" => ["Diphtheria", "Tetanus", "Pertussis"], "DTwP-Hib" => ["Diphtheria", "Tetanus", "Pertussis", "Hib"],
    #     "Penta" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib"], "Hexa" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio"],
    #     "HPV" => ["HPV"], "Rotavirus" => ["Rotavirus"], "PCV" => ["PCV"] # "Hib" => ["Hib"],
    # )
    # List of producers
    P = ["AJ_Vaccines", "BB_NCIPD", "China_National", "Bharat_Biotech", "Bilthoven", "Biological_E", "GSK", "Haffkine_Bio",
         "LG_Chem", "Merck_Sharp", "Panacea_Biotec", "PT_Bio", "Sanofi", "Serum_Institute", "Pfizer"]

    # Mapping of vaccines to producers
    P_v = Dict(
        "TT" => ["Serum_Institute", "PT_Bio", "BB_NCIPD", "Biological_E"], "HepB" => ["Serum_Institute", "LG_Chem"],
        "IPV" => ["LG_Chem", "AJ_Vaccines", "Bilthoven", "Sanofi"], "OPV" => ["Serum_Institute", "PT_Bio", "GSK", "Sanofi", "Panacea_Biotec", "China_National", "Bharat_Biotech", "Haffkine_Bio"],
        "DT" => ["PT_Bio", "BB_NCIPD"], "Td" => ["Serum_Institute", "PT_Bio", "BB_NCIPD", "Biological_E"], "DTwP" => ["Serum_Institute", "Biological_E"],
        "DTwP-Hib" => ["Serum_Institute"], "Penta" => ["Serum_Institute", "PT_Bio", "Biological_E", "LG_Chem", "Panacea_Biotec"], "Hexa" => ["Sanofi"],
        "HPV" => ["GSK", "Merck_Sharp", "China_National"], "Rotavirus" => ["Serum_Institute", "GSK", "Bharat_Biotech"], "PCV" => ["Serum_Institute", "GSK", "Pfizer"]
        #"Hib" => ["Serum_Institute"]
    )

    #     P_v = Dict(
    #     "TT" => ["Serum_Institute", "PT_Bio", "BB_NCIPD", "Biological_E"], "HepB" => ["Serum_Institute", "LG_Chem"],
    #     "IPV" => ["LG_Chem", "AJ_Vaccines", "Bilthoven", "Sanofi"], "OPV" => ["Serum_Institute", "PT_Bio", "GSK", "Sanofi", "Panacea_Biotec", "China_National", "Bharat_Biotech", "Haffkine_Bio"],
    #     "DT" => ["PT_Bio", "BB_NCIPD"], "Td" => ["Serum_Institute", "PT_Bio", "BB_NCIPD", "Biological_E"], "DTwP" => ["Serum_Institute", "Biological_E"],
    #     "DTwP-Hib" => ["Serum_Institute"],  "HPV" => ["GSK", "Merck_Sharp", "China_National"], "Rotavirus" => ["Serum_Institute", "GSK", "Bharat_Biotech"], 
    #     "PCV" => ["Serum_Institute", "GSK", "Pfizer"]
    # )

    #     P_v = Dict(
    #     "M" => ["Serum_Institute", "PT_Bio"], "MR" => ["Serum_Institute", "Biological_E"], "MMR" => ["Serum_Institute", "GSK"],
    #     "TT" => ["Serum_Institute", "PT_Bio", "BB_NCIPD", "Biological_E"], "HepB" => ["Serum_Institute", "LG_Chem"],
    #     "IPV" => ["LG_Chem", "AJ_Vaccines", "Bilthoven", "Sanofi"], "OPV" => ["Serum_Institute", "PT_Bio", "GSK", "Sanofi", "Panacea_Biotec", "China_National", "Bharat_Biotech", "Haffkine_Bio"],
    #     "DT" => ["PT_Bio", "BB_NCIPD"], "Td" => ["Serum_Institute", "PT_Bio", "BB_NCIPD", "Biological_E"], "DTwP" => ["Serum_Institute", "Biological_E"],
    #     "DTwP-Hib" => ["Serum_Institute"], "Penta" => ["Serum_Institute", "PT_Bio", "Biological_E", "LG_Chem", "Panacea_Biotec"], "Hexa" => ["Sanofi"],
    #     "HPV" => ["GSK", "Merck_Sharp", "China_National"], "Rotavirus" => ["Serum_Institute", "GSK", "Bharat_Biotech"], "PCV" => ["Serum_Institute", "GSK", "Pfizer"]
    # ) # "Hib" => ["Serum_Institute"],

    # Derived mappings
    V_a = Dict(a => [v for v in keys(A_v) if a in A_v[v]] for a in A)
    V_p = Dict(p => [v for v in keys(P_v) if p in P_v[v]] for p in P)
    P_a = Dict(a => unique(vcat([P_v[v] for v in V_a[a]]...)) for a in A)
    A_p = Dict(p => [a for a in keys(P_a) if p in P_a[a]] for p in P)

    # Categories
    # capacity_category = Dict(
    #     "Small" => ["AJ_Vaccines", "Panacea_Biotec", "Bilthoven", "China_National"],
    #     "Medium" => ["Sanofi", "Pfizer", "Haffkine_Bio", "Bharat_Biotech", "Merck_Sharp", "PT_Bio", "LG_Chem", "BB_NCIPD"],
    #     "Large" => ["Serum_Institute", "GSK", "Biological_E"]
    # )

    #     capacity_category = Dict(
    #     "Small" => ["Serum_Institute", "Haffkine_Bio",  "Merck_Sharp", "Sanofi"],
    #     "Medium" => ["Bilthoven", "Pfizer",  "Bharat_Biotech",  "PT_Bio", "BB_NCIPD", "China_National"],
    #     "Large" => ["GSK", "Biological_E", "AJ_Vaccines", "LG_Chem", "Panacea_Biotec"]
    # )

    capacity_category = Dict(
    "Small"  => ["Serum_Institute", "Haffkine_Bio", "Merck_Sharp", "Sanofi"],
    "Medium" => ["Bilthoven", "Pfizer", "Bharat_Biotech", "PT_Bio", "BB_NCIPD", "China_National", "GSK", "Biological_E"],
    "Large"  => ["AJ_Vaccines", "LG_Chem", "Panacea_Biotec"]
    )

    vaccine_category = Dict(
        "MMR-based" => ["M", "MR", "MMR"],
        "Td-based" => ["TT", "HepB", "Hib", "IPV", "OPV", "DT", "Td", "DTwP", "DTwP-Hib"],#, "Penta", "Hexa"],
        "Single" => ["HPV", "Rotavirus", "PCV"]
    )

    antigen_category = Dict(
        "Td-based" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio"],
        "Single" => ["HPV", "Rotavirus", "PCV"]
    )

            # "MMR-based" => ["Measles", "Mumps", "Rubella"],

    return A, V, A_v, P, P_v, V_a, V_p, P_a, A_p, capacity_category, vaccine_category, antigen_category
end

