# **HCVM Optimization Model**

This project is automatically tested using GitHub Actions.
![CI](ci-badge.svg)
![Julia Version](https://img.shields.io/badge/julia-1.6%2B-blue)



This repository contains the implementation of an **L-Shaped decomposition model** for optimizing vaccine tenders. Below is an overview of the key files and their functions.

## **Repository Structure**

### **Main Model**
- 📂 **`L-Shaped/Final_codes/`**  
  - **`vaccine_tender_L_shaped_scenario_pairs_all_objectives_functionalized.jl`** – The main model file implementing the L-Shaped decomposition.

### **Core Functions**
- 📂 **`L-Shaped/Final_codes/functions/`**  
  - Contains modular functions used within the main model.

### **Model Components**
- 🏗 **`deterministic_equivalent.jl`** – Implements the deterministic equivalent model.  
- 🔀 **`master_problem.jl`** – Defines the master problem in the two-stage stochastic model.  
- 🔁 **`sub_problem.jl`** – Defines the sub-problem in the two-stage stochastic model.  
- ✂️ **`generate_dual_cuts.jl`** – Helper function for generating cuts for the L-Shaped method.  

### **Helper Functions**
- ⚙️ **`create_check_params.jl`** – Generates parameters used in McCormick relaxation.  
- 🎯 **`load_model_starting_points.jl`** – Loads initial conditions for the model.  
- 📊 **`load_params.jl`** – Loads necessary model parameters.  
- 🌎 **`load_scenarios.jl`** – Loads scenario data for the stochastic model.  
- 🎲 **`select_random_scenarios.jl`** – Randomly selects scenarios if not explicitly specified.  
- 💉 **`setup_vax_info.jl`** – Loads vaccine lists and associated dictionaries.  
- 💾 **`save_L_Shape_results.jl`** – Saves results into corresponding files.  

---

## **Usage**
To run the model, execute the main script:  
```julia
include("L-Shaped/Final_codes/vaccine_tender_L_shaped_scenario_pairs_all_objectives_functionalized.jl")
```
Ensure that all required dependencies and parameters are properly set up before execution.

---

## **Contributing**
Feel free to open issues or submit pull requests for improvements, bug fixes, or additional features.

---

## **License**
[MIT License](LICENSE) – Open for modification and use with attribution.

