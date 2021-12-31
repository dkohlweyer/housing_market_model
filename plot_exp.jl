using Distributed, DataStructures, StatsPlots, Serialization, ArgParse

# Parse arguments
s = ArgParseSettings()
@add_arg_table s begin
    "config"
        help = "configuration file"
        required = true
	"plot_iterations"
		help = ""
		required = false
end
parsed_args = parse_args(s)

config = parsed_args["config"]

include("model/model.jl")
include("$config")

# load data
results = []
chunk = 0
while isfile("$folder/data-$(chunk+=1).dat")
	append!(results, deserialize("$folder/data-$chunk.dat"))
end

if length(results) == 0
	println("ERROR: No data found in $folder/data/")
	exit(1)
end

plot_it = parsed_args["plot_iterations"]

if plot_it == nothing
	plot_it = size(results[1][:model_data],1)
else
	plot_it = burn_in+1+parse(Int,plot_it)
end

# Aggregate data
single_run_data = Dict()
aggregated_data = Dict()

for (exp_name, props) in experiments
	single_run_data[exp_name] = []
	aggregated_data[exp_name] = Dict()

	for i in 1:length(results)
		if results[i][:exp_name] == exp_name
			append!(single_run_data[exp_name], [results[i][:model_data][burn_in+1:plot_it,:]])
		end
	end

	for agg in run_aggregation
		agg_data_frame = DataFrame()
		for col in propertynames(single_run_data[exp_name][1])
			data = []
			for i in 1:length(single_run_data[exp_name])
				append!(data, [single_run_data[exp_name][i][!, col]])
			end

			agg_data = agg(data)

			agg_data_frame[!, col] = agg_data
		end
		aggregated_data[exp_name][agg] = agg_data_frame
	end
end

# Plotting
exp_names = collect(keys(experiments))

for agg in run_aggregation
	if !isdir("$folder/$agg/")
		mkdir("$folder/$agg/")
	end

	for col in propertynames(aggregated_data[exp_names[1]][agg])
		if col != :step
			pl = plot(title=col)
			for exp_name in exp_names
				@df aggregated_data[exp_name][agg] plot!(cols(col), label=exp_name)
			end
			savefig(pl, "$folder/$agg/$col.pdf")
		end
	end
end

for col in propertynames(single_run_data[exp_names[1]][1])
	if col != :step
		pl = plot(title=col)
		c = 0
		for exp_name in exp_names
			c += 1
			@df single_run_data[exp_name][1] plot!(cols(col), color=palette(:default)[c], label=exp_name)
			for i in 2:no_runs
				#c+=1#TODO
				@df single_run_data[exp_name][i] plot!(cols(col), color=palette(:default)[c], label="")
			end
		end
		savefig(pl, "$folder$col.pdf")
	end
end
