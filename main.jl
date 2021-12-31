using StatsPlots
using Random
using Serialization

include("model/model.jl")

include("experiments/baseline_init.jl")

no_of_days = parse(Int, ARGS[1]);

rand_string = randstring(6)

if !isdir("data/$rand_string/")
    mkdir("data/$rand_string/")
end

# Initialization
model = initialize(baseline_properties, num_households, num_firms, num_banks)

# Data collection
when_collect(model, s) = model.day_in_month == 20
model_data=[]

include("experiments/data_collection_full.jl")

model_log_file = open("data/$rand_string/model_log.txt", "w")
model_logging(false)
model_logger_target(model_log_file)
model_log_agent(Firm)
model_log_category("monthly_settlement")
model_log_category("balance_sheet")
model_log_category("planning")
model_log_category("crisis")
model_log_category("production")
model_log_category("market_research")
model_log_agent(CreditMarket)
model_log_category("credit_market")

# Running
@time agent_data, model_data = run!(model, dummystep, model_step!, no_of_days; mdata = mdata, when=when_collect)

# Snapshot
open("data/$rand_string/snapshot-$rand_string.dat", "w") do outfile
    serialize(outfile, model)
end

close(model_log_file)

# Plotting
for name in propertynames(model_data)
    if name != :step
        pl = @df model_data plot(cols(name), title=name, leg=false)
        savefig(pl, "data/$rand_string/$name.pdf")
    end
end
