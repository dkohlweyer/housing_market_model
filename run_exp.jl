using Distributed, DataStructures, StatsPlots, Serialization, ArgParse, Dates

# Parse arguments
s = ArgParseSettings()
@add_arg_table s begin
    "--chunk"
        help = "TODO"
		arg_type = Int
		default = 1
	"--no_chunks"
		help = "TODO"
		arg_type = Int
		default = 1
    "config"
        help = "configuration file"
        required = true
end
parsed_args = parse_args(s)

config = parsed_args["config"]
chunk = parsed_args["chunk"]
no_chunks = parsed_args["no_chunks"]

if chunk > no_chunks
	println("ERROR: chunk has to be <= no_chunks")
	exit(1)
end

include("model/model.jl")
include("$config")

print("Preparing workers... ")

@everywhere function load_config(config)
	include(config)
end

@everywhere function execute_task(task)
	global temp = open("temp.txt", "a")
	println("Running ", task[:exp_name], "/", task[:run], "...")

	model = initialize(task[:properties], num_households, num_firms, num_banks)
	agent_data, model_data = run!(model, dummystep, model_step!, iterations; adata = adata, mdata = mdata, when=when_collect)

	return Dict(:exp_name => task[:exp_name], :run => task[:run], :agent_data => agent_data, :model_data => model_data)
end

# Create list of task ids
all_task_ids = Vector{String}()
for (exp_name, props) in experiments
	for run in 1:no_runs
		push!(all_task_ids, "$exp_name-$run")
	end
end
sort!(all_task_ids)

tasks_per_junk = ceil(length(all_task_ids) / no_chunks)
from = Int((chunk-1)*tasks_per_junk+1)
to = Int(min(from+tasks_per_junk-1, length(all_task_ids)))

my_task_ids = all_task_ids[from:to]

# Create list of tasks matching ids in my_task_ids
tasks = Dict[]
for (exp_name, props) in experiments
    for run in 1:no_runs
		if "$exp_name-$run" in my_task_ids
			properties = deepcopy(baseline_properties)

	        for (prop, value) in props
	            properties[prop] = value
	        end

			task = Dict(:exp_name => exp_name, :run => run, :properties => properties)

			push!(tasks, task)
		end
    end
end

println("DONE")

print("Loading config... ")

@everywhere include("model/model.jl")
if nworkers() > 1
	for i in 2:nworkers()+1
		@spawnat i load_config("$config")
	end
end

println("DONE")

# run parallel
results = pmap(execute_task, tasks)

# Save data
if !isdir(folder)
	mkdir(folder)
end
serialize("$folder/data-$chunk.dat", results)
