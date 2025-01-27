function create_vaccine_data()
    A = ["Measles", "Mumps", "Rubella", "Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio", "HPV", "Rotavirus", "PCV"]
    V = ["M", "MR", "MMR", "TT", "HepB", "Hib", "IPV", "OPV", "DT", "Td", "DTwP", "DTwP-Hib", "Penta", "Hexa", "HPV", "Rotavirus", "PCV"]
    A_v = Dict(
        "M" => ["Measles"], "MR" => ["Measles", "Rubella"], "MMR" => ["Measles", "Mumps", "Rubella"], "TT" => ["Tetanus"],
        "HepB" => ["Hepatitis_B"], "Hib" => ["Hib"], "IPV" => ["Polio"], "OPV" => ["Polio"], "DT" => ["Diphtheria", "Tetanus"],
        "Td" => ["Diphtheria", "Tetanus"], "DTwP" => ["Diphtheria", "Tetanus", "Pertussis"], "DTwP-Hib" => ["Diphtheria", "Tetanus", "Pertussis", "Hib"],
        "Penta" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib"], "Hexa" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio"],
        "HPV" => ["HPV"], "Rotavirus" => ["Rotavirus"], "PCV" => ["PCV"]
    )
    P = ["AJ_Vaccines", "BB_NCIPD", "China_National", "Bharat_Biotech", "Bilthoven", "Biological_E", "GSK", "Haffkine_Bio",
         "LG_Chem", "Merck_Sharp", "Panacea_Biotec", "PT_Bio", "Sanofi", "Serum_Institute", "Pfizer"]
    P_v = Dict(
        "M" => ["Serum_Institute", "PT_Bio"], "MR" => ["Serum_Institute", "Biological_E"], "MMR" => ["Serum_Institute", "GSK"],
        "TT" => ["Serum_Institute", "PT_Bio", "BB_NCIPD", "Biological_E"], "HepB" => ["Serum_Institute", "LG_Chem"], "Hib" => ["Serum_Institute"],
        "IPV" => ["LG_Chem", "AJ_Vaccines", "Bilthoven", "Sanofi"], "OPV" => ["Serum_Institute", "PT_Bio", "GSK", "Sanofi", "Panacea_Biotec", "China_National", "Bharat_Biotech", "Haffkine_Bio"],
        "DT" => ["PT_Bio", "BB_NCIPD"], "Td" => ["Serum_Institute", "PT_Bio", "BB_NCIPD", "Biological_E"], "DTwP" => ["Serum_Institute", "Biological_E"],
        "DTwP-Hib" => ["Serum_Institute"], "Penta" => ["Serum_Institute", "PT_Bio", "Biological_E", "LG_Chem", "Panacea_Biotec"], "Hexa" => ["Sanofi"],
        "HPV" => ["GSK", "Merck_Sharp", "China_National"], "Rotavirus" => ["Serum_Institute", "GSK", "Bharat_Biotech"], "PCV" => ["Serum_Institute", "GSK", "Pfizer"]
    )
    V_a = Dict(a => [v for v in keys(A_v) if a in A_v[v]] for a in A)
    V_p = Dict(p => [v for v in keys(P_v) if p in P_v[v]] for p in P)
    P_a = Dict(a => unique(vcat([P_v[v] for v in V_a[a]]...)) for a in A)
    A_p = Dict(p => [a for a in keys(P_a) if p in P_a[a]] for p in P)
    capacity_category = Dict(
        "Small" => ["AJ_Vaccines", "Panacea_Biotec", "Bilthoven", "China_National"],
        "Medium" => ["Sanofi", "Pfizer", "Haffkine_Bio", "Bharat_Biotech", "Merck_Sharp", "PT_Bio", "LG_Chem", "BB_NCIPD"],
        "Large" => ["Serum_Institute", "GSK", "Biological_E"]
    )
    vaccine_category = Dict(
        "MMR-based" => ["M", "MR", "MMR"],
        "Td-based" => ["TT", "HepB", "Hib", "IPV", "OPV", "DT", "Td", "DTwP", "DTwP-Hib", "Penta", "Hexa"],
        "Single" => ["HPV", "Rotavirus", "PCV"]
    )
    antigen_category = Dict(
        "MMR-based" => ["Measles", "Mumps", "Rubella"],
        "Td-based" => ["Diphtheria", "Tetanus", "Pertussis", "Hepatitis_B", "Hib", "Polio"],
        "Single" => ["HPV", "Rotavirus", "PCV"]
    )

    return Dict(
        "A" => A, "V" => V, "A_v" => A_v, "P" => P, "P_v" => P_v, "V_a" => V_a, "V_p" => V_p, "P_a" => P_a, "A_p" => A_p,
        "capacity_category" => capacity_category, "vaccine_category" => vaccine_category, "antigen_category" => antigen_category
    )
end
