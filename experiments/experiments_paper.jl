# Sim properties
folder = "data/experiments_paper2/"
iterations = 30000
burn_in = 0
no_runs = 25
run_aggregation = [mean]

snapshot_file = "snapshot_5k_20000.dat"

# include baseline
include("baseline_init_from_snapshot.jl")

num_households = 5000
num_firms = 250
num_banks = 1

baseline_properties[:tax_rate] = 0.05
baseline_properties[:firm_dividend_threshold_full_payout] = 1.0
baseline_properties[:quantile_production_planning] = 0.75
baseline_properties[:mortgage_profit_rate] = 0.01
baseline_properties[:disable_credit_rationing] = true
baseline_properties[:disable_taylor_rule] = false
baseline_properties[:gamma_consumption] = 18
baseline_properties[:central_bank_rate_markdown] = 0.75
baseline_properties[:carrol_consumption_parameter] = 0.0025
baseline_properties[:lambda_btl] = 0.9


# Define experiments
experiments = Dict(
"baseline" => Dict(),
"lambda0.0" => Dict(:lambda_btl => 0.0),
"lambda0.0_disableGrowth" => Dict(:lambda_btl => 0.0,
    :disable_hpi_growth_objective => true),
"static_ltv_0.7" => Dict(:ltv_cap => 0.7),
"static_dsti_0.2" => Dict(:dsti_cap => 0.2),
)

# Data Collection
include("data_collection_full.jl")
