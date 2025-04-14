"""
Function to check whether a solution is "infeasible" due to the average number of missed doses
being larger than some percent of the total demand

Inputs:
subproblem
% threshold

"""

function check_percent_for_sec(
    S, A, T_initial, Ω_scenarios, p_ω, 
)


S_results = Dict()
for a in A
    temp_1 = Dict()
    for t in T_initial
        temp_2 = Dict()
        for ω in Ω_scenarios
            temp_2[ω] = S[ω][a,t]
        end
        temp_1[t] = temp_2
    end
    S_results[a] = temp_1
end