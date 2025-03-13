function create_vaccine_data_MMR_only()
    # List of antigens
    A = ["Measles", "Mumps", "Rubella"]

    # List of vaccines
    V = ["M", "MR", "MMR"]

    # Mapping of vaccines to antigens
    A_v = Dict(
        "M" => ["Measles"], "MR" => ["Measles", "Rubella"], "MMR" => ["Measles", "Mumps", "Rubella"]
    )

    # List of producers
    P = ["Biological_E", "GSK","PT_Bio", "Serum_Institute"]

    # Mapping of vaccines to producers
    P_v = Dict(
        "M" => ["Serum_Institute", "PT_Bio"], "MR" => ["Serum_Institute", "Biological_E"], "MMR" => ["Serum_Institute", "GSK"]
    )

    # Derived mappings
    V_a = Dict(a => [v for v in keys(A_v) if a in A_v[v]] for a in A)
    V_p = Dict(p => [v for v in keys(P_v) if p in P_v[v]] for p in P)
    P_a = Dict(a => unique(vcat([P_v[v] for v in V_a[a]]...)) for a in A)
    A_p = Dict(p => [a for a in keys(P_a) if p in P_a[a]] for p in P)

    # Categories
    capacity_category = Dict(
        "Small" => ["AJ_Vaccines", "Panacea_Biotec", "Bilthoven", "China_National"],
        "Medium" => ["Sanofi", "Pfizer", "Haffkine_Bio", "Bharat_Biotech", "Merck_Sharp", "PT_Bio", "LG_Chem", "BB_NCIPD"],
        "Large" => ["Serum_Institute", "GSK", "Biological_E"]
    )

    vaccine_category = Dict(
        "MMR-based" => ["M", "MR", "MMR"]
    )

    antigen_category = Dict(
        "MMR-based" => ["Measles", "Mumps", "Rubella"]
    )

    return A, V, A_v, P, P_v, V_a, V_p, P_a, A_p, capacity_category, vaccine_category, antigen_category
end
