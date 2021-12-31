using Distributed, DataStructures, StatsPlots, Serialization, ArgParse,Statistics

# Parse arguments
s = ArgParseSettings()
@add_arg_table s begin
    "config"
        help = "configuration file"
        required = true
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
	println("ERROR: No data found in $folder")
	exit(1)
end

min = 900
max = 1500

# Aggregate data
single_run_data = Dict()
aggregated_data = Dict()

for (exp_name, props) in experiments
	single_run_data[exp_name] = []
	aggregated_data[exp_name] = Dict()

	for i in 1:length(results)
		if results[i][:exp_name] == exp_name
			append!(single_run_data[exp_name], [results[i][:model_data][min:max,:]])
		end
	end
end


### Baseline Time Series
i=1
for col in [:unemployment, :output_growth_yoy, :hpi_growth, :mortgage_credit_growth_yoy]
	pl = @df single_run_data["baseline"][i] plot(cols(col), color="blue", label="")
	savefig(pl, "$(folder)baseline_$col.pdf")
end


### Correlations Baseline
data = single_run_data["baseline"][1]

for i in 2:10
	global data = vcat(data, single_run_data["baseline"][i])
end
Plots.scalefontsizes(0.25)
pl = @df data cornerplot([:output_growth_yoy :hpi_growth :mortgage_credit_growth_yoy :bank_average_mortgage_rate_spread], grid = false,compact=true,histograms=false)

savefig(pl, "$folder/baseline_correlations.pdf")


Plots.scalefontsizes(4.0)


### Capital gain experiment Time Series
for col in [:hpi_growth, :mortgage_credit_growth_yoy]
	pl = @df single_run_data["baseline"][i] plot(cols(col), color="blue", label="")
	@df single_run_data["lambda0.0"][i] plot!(cols(col), color="green", label="")
	@df single_run_data["lambda0.0_disableGrowth"][i] plot!(cols(col), color="red", label="")
	savefig(pl, "$(folder)cap_gain_exp_$col.pdf")
end


### Capital gain experiment: Histograms
data_baseline = single_run_data["baseline"][1]

for i in 2:no_runs
	global data_baseline = vcat(data_baseline, single_run_data["baseline"][i])
end

data_nogrowth= single_run_data["lambda0.0_disableGrowth"][1]

for i in 2:no_runs
	global data_nogrowth = vcat(data_nogrowth, single_run_data["lambda0.0_disableGrowth"][i])
end

data_lambda0= single_run_data["lambda0.0"][1]

for i in 2:no_runs
	global data_lambda0 = vcat(data_lambda0, single_run_data["lambda0.0_disableGrowth"][i])
end

bins = 80
for var in [:output_growth_yoy, :unemployment]
	base_bin = ( maximum(data_baseline[!, var]) - minimum(data_baseline[!, var]) ) / bins
	nexpbin = round(Int64,( maximum(data_lambda0[!, var]) - minimum(data_lambda0[!, var]) ) / base_bin)
	pl = histogram(data_baseline[!, var],alpha=0.5,label="",color="blue",bins=bins)
	histogram!(pl, data_nogrowth[!, var],alpha=0.5,label="",color="red",bins=nexpbin)
	savefig(pl, "$folder/cap_gain_exp_hist_$var.pdf")
end

bins = 80
for var in [:output_growth_yoy, :unemployment, :hpi_growth, :mortgage_credit_growth_yoy]
	base_bin = ( maximum(data_lambda0[!, var]) - minimum(data_lambda0[!, var]) ) / bins
	nexpbin = round(Int64,( maximum(data_nogrowth[!, var]) - minimum(data_nogrowth[!, var]) ) / base_bin)
	pl = histogram(data_lambda0[!, var],alpha=0.5,label="",color="green",bins=bins)
	histogram!(pl, data_nogrowth[!, var],alpha=0.5,label="",color="red",bins=nexpbin)
	savefig(pl, "$folder/cap_gain_exp_hist_lambda0_$var.pdf")
end


### Static LTV cap experiment: Histograms
data_baseline = single_run_data["baseline"][1]

for i in 2:no_runs
	global data_baseline = vcat(data_baseline, single_run_data["baseline"][i])
end

data_ltv_cap= single_run_data["static_ltv_0.7"][1]

for i in 2:no_runs
	global data_ltv_cap = vcat(data_ltv_cap, single_run_data["static_ltv_0.7"][i])
end

bins = 80
for var in [:hpi_growth,:output_growth_yoy, :unemployment, :hh_consumption_budget_in_month, :active_firms]
	base_bin = ( maximum(data_baseline[!, var]) - minimum(data_baseline[!, var]) ) / bins
	nexpbin = round(Int64,( maximum(data_ltv_cap[!, var]) - minimum(data_ltv_cap[!, var]) ) / base_bin)
	pl = histogram(data_baseline[!, var],alpha=0.5,label="",color="blue",bins=bins)
	histogram!(pl, data_ltv_cap[!, var],alpha=0.5,label="",color="red",bins=nexpbin)
	savefig(pl, "$folder/static_ltv_cap_exp_hist_$var.pdf")
end


### Static DSTI cap experiment: Histograms
data_baseline = single_run_data["baseline"][1]

for i in 2:no_runs
	global data_baseline = vcat(data_baseline, single_run_data["baseline"][i])
end

data_dsti_cap= single_run_data["static_dsti_0.2"][1]

for i in 2:no_runs
	global data_dsti_cap = vcat(data_dsti_cap, single_run_data["static_dsti_0.2"][i])
end

bins = 80
for var in [:hpi_growth,:output_growth_yoy, :unemployment, :hh_consumption_budget_in_month, :active_firms]
	base_bin = ( maximum(data_baseline[!, var]) - minimum(data_baseline[!, var]) ) / bins
	nexpbin = round(Int64,( maximum(data_dsti_cap[!, var]) - minimum(data_dsti_cap[!, var]) ) / base_bin)
	pl = histogram(data_baseline[!, var],alpha=0.5,label="",color="blue",bins=bins)
	histogram!(pl, data_dsti_cap[!, var],alpha=0.5,label="",color="yellow",bins=nexpbin)
	savefig(pl, "$folder/static_dsti_cap_exp_hist_$var.pdf")
end
