# Sim properties
folder = "data/baseline_reduced/"
iterations = 12000
burn_in = 0#Int(12000/20)
no_runs = 1
run_aggregation = [mean]

snapshot_file = "snapshot_5k-reduced.dat"

# include baseline
include("reduced_init_from_snapshot.jl")

num_households = 5000
num_firms = 250
num_banks = 1

# Define experiments
experiments = Dict(
"reduced" => Dict(),
)

# Data Collection
include("data_collection_full.jl")
