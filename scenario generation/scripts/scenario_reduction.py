import numpy as np
import ot
from scipy.spatial import distance


class Fast_Forward_Selection:

    def __init__(self, df, val_col: str="val", verbose_level: int = 0):
        # Original Dataframe
        self.df = df
        # Scenario set
        self.org_set = np.array(df[val_col].tolist()).T
        # Probabilities
        self.org_probs = df["prob"].to_numpy()
        # Number of scenarios
        self.N = df.shape[0]
        # Verbosity level
        self.verbose_level = verbose_level
        # Perform checks
        if np.isclose(df["prob"].sum(), 1) == False:
            raise ValueError("Probabilities must sum to one")
        if self.N != self.org_set.shape[1]:
            raise ValueError("Size of scenario set and probabilities must match")

        # Initialize the distance matrix and the sets
        self.init_distances()
        print(f"Number of scenarios: {self.N}") if self.verbose_level >= 1 else None
        
    def init_distances(self):
        # Precompute the full distance matrix only once
        self.dist_matrix = distance.squareform(distance.pdist(self.org_set.T, "euclidean"))
        self.fixed_dist_matrix = self.dist_matrix.copy()
        self.J_set = np.ones(self.N, dtype=bool)

    def print_output(self):
        print(f"Reduced set of scenarios: {self.red_set}") if self.verbose_level >= 1 else None
        print(f"Probabilities: {self.red_probs}") if self.verbose_level >= 1 else None
        for k, v in self.red_set_dict.items():
            print(f"SID {k} is merged with: {v['merged_sids']} with probability of {v['prob']:.6f}") if self.verbose_level >= 2 else None

    def run(self, desired_n_scenarios: int = 1):
        print(f"Desired number of scenarios: {desired_n_scenarios}") if self.verbose_level >= 1 else None
        # Initialize the reduced set of scenarios
        self.red_set = np.array([], dtype=int)

        # Step 1
        u = self.get_u()
        self.update_sets(u)

        # Step i
        for _ in range(desired_n_scenarios - 1):
            self.dist_matrix = np.minimum(self.dist_matrix, self.dist_matrix[u, :])
            u = self.get_u()
            self.update_sets(u)

        # Update the probabilities
        self.update_probs()
        self.print_output()

        return self.red_set, self.red_probs, self.red_set_dict

    def get_u(self) -> int:
        # Calculate the weighted distance matrix 'wdm' only for active scenarios
        active_indices = np.where(self.J_set)[0]
        wdm = self.dist_matrix[active_indices][:, active_indices] @ self.org_probs[active_indices]

        # Find the scenario with the smallest weighted distance
        u = np.argmin(wdm)

        return active_indices[u]

    def update_sets(self, u):
        # Directly update the boolean index array
        self.J_set[u] = False
        # Append the scenario 'u' to the set of scenarios 'red_set'
        self.red_set = np.append(self.red_set, u)

    def update_probs(self):
        self.red_probs = np.zeros(len(self.red_set))
        self.red_set_dict = {}

        # Find the closest scenario for each scenario in the reduced set
        closest_indices = np.argmin(self.fixed_dist_matrix[:, self.red_set], axis=1)

        # Redistribute the probabilities
        for idx, u in enumerate(self.red_set):
            agg_prob = np.sum(self.org_probs[closest_indices == idx])
            self.red_probs[idx] = agg_prob
            # Store the original indices of the scenarios in the reduced set
            self.red_set_dict[u+1] = {"sid": np.where(closest_indices == idx)[0] + 1,
                                      "prob": agg_prob}
    def construct_reduced_df(self):
        # Construct the reduced DataFrame
        reduced_df = self.df.iloc[self.red_set].copy()
        reduced_df["prob"] = self.red_probs
        reduced_df["merged_sids"] = reduced_df["sid"].map(self.red_set_dict)
        return reduced_df
    
    
def get_zeta_metric(
    scenarios_P: np.array,
    scenarios_Q: np.array,
    probabilities_P: np.array,
    probabilities_Q: np.array,
    verbose: bool = False,
) -> float:
    """
    Absolute ζ1-distance represents the total transportation cost based on the chosen metric (e.g., Euclidean distance) between the scenarios in P and Q.
    Relative ζ1-distance is the ratio of the absolute ζ1-distance to the best possible ζ1-distance to one of the original scenarios.
    """
    # Calculate the pairwise distance matrix
    distance_matrix = ot.dist(scenarios_P, scenarios_Q, metric="euclidean")

    # Calculate the 1-Wasserstein distance (absolute ζ1-distance)
    zeta_1_distance_abs = ot.emd2(probabilities_P, probabilities_Q, distance_matrix)

    # Calculate the best possible ζ1-distance to one of the original scenarios
    best_possible_distance = min(
        [
            ot.emd2([1.0], probabilities_P, ot.dist(scenario.reshape(1, -1), scenarios_P, metric="euclidean"))
            for scenario in scenarios_P
        ]
    )

    # Calculate the relative ζ1-distance
    zeta_1_distance_rel = (zeta_1_distance_abs / best_possible_distance) * 100  # Convert to percentage
    if verbose:
        print(f"Statistics for ζ1-distance ({scenarios_P.shape[0]:,} → {scenarios_Q.shape[0]:,}):")
        print(f"   Absolute: {zeta_1_distance_abs:,.4f}")
        print(f"   Relative: {zeta_1_distance_rel:,.4f}%")

    return zeta_1_distance_abs, zeta_1_distance_rel
