using Random

# Include all agent files
include("logging.jl")
include("agents/Bank.jl")
include("markets/CreditMarket.jl")
include("agents/Household.jl")
include("agents/Firm.jl")
include("markets/HousingMarket.jl")
include("markets/MortgageMarket.jl")
include("markets/GoodsMarket.jl")
include("markets/LaborMarket.jl")
include("agents/StatisticsAgent.jl")
include("agents/Government.jl")
include("agents/CapitalGoodsProducer.jl")
include("markets/CreditMarket.jl")
include("markets/FinancialMarket.jl")

# Define custom schedulers
function hh_scheduler_randomly(model::ABM)
    return shuffle!(model.rng, collect(keys(model.households)))
end
hh_scheduler_fastest(model::ABM) = keys(model.households)

function firm_scheduler_randomly(model::ABM)
    return shuffle!(model.rng, collect(union(keys(model.active_firms), keys(model.inactive_firms))))
end
firm_scheduler_fastest(model::ABM) = union(keys(model.active_firms), keys(model.inactive_firms))

function active_firm_scheduler_randomly(model::ABM)
    return shuffle!(model.rng, collect(keys(model.active_firms)))
end
active_firm_scheduler_fastest(model::ABM) = keys(model.active_firms)

function bank_scheduler_randomly(model::ABM)
    return shuffle!(model.rng, collect(keys(model.banks)))
end
bank_scheduler_fastest(model::ABM) = keys(model.banks)

function households(f, model::ABM)
    for i in hh_scheduler_randomly(model)
        f(model.agents[i], model)
    end
end

function firms(f, model::ABM)
    for i in firm_scheduler_randomly(model)
        f(model.agents[i], model)
    end
end

function active_firms(f, model::ABM)
    for i in active_firm_scheduler_randomly(model)
        f(model.agents[i], model)
    end
end

function banks(f, model::ABM)
    for i in bank_scheduler_randomly(model)
        f(model.agents[i], model)
    end
end

function capital_goods_producer(f, model::ABM)
    f(model.capital_goods_producer, model)
end

function government(f, model::ABM)
    f(model.government, model)
end

# Implements model_step! function from Agents.jl framework.
function model_step!(model)
    model_day!(model)

    model.day += 1

    model.day_in_week +=1
    if model.day_in_week == 6
        model.day_in_week = 1
    end

    model.day_in_month +=1
    if model.day_in_month == 21
        model.day_in_month = 1
    end

    model.day_in_year += 1
    if model.day_in_year == 241
        model.day_in_year = 1
    end

    # Print progress
    if mod(model.day, 1000) == 0
        println(model.day, " ")
    end
end

# Implements sequence of events on each model day.
function model_day!(model)
    banks(model) do bank, model
        model.day_in_month == bank.activation_day && monthly_settlement(bank, model)
    end

    households(model) do hh, model
        collect_interest(hh, model)
    end

    capital_goods_producer(model) do producer, model
        model.day_in_month == 1 && monthly_settlement(producer, model)

        collect_interest(producer, model)

        innovation_process(producer, model)

        model.day_in_month == 1 && update_prices(producer, model)
    end

    firms(model) do firm, model
        model.day_in_month == firm.activation_day && monthly_settlement(firm, model)
        collect_interest(firm, model)
    end

    model.day_in_month == 1 && monthly_settlement(model.government, model)

    active_firms(model) do firm, model
        model.day == firm.next_market_research_day && market_research(firm, model)
    end

    active_firms(model) do firm, model
        if model.day_in_month == firm.activation_day && firm.active
            production_planning(firm, model)
            financial_planning(firm, model)
        end
    end

    credit_market(model.credit_market, model)

    firms(model) do firm, model
         firm.active && model.day_in_month == firm.activation_day && financial_and_production_replanning(firm, model)
         fire_employees(firm, model)
    end

    labor_market(model.labor_market, model)

    active_firms(model) do firm, model
        if model.day_in_month == firm.activation_day && firm.active
            invest(firm, model)
            production(firm::Firm, model)
            payments(firm::Firm, model)
        end
    end

    distribute_dividends(model.financial_market, model)

    if model.day_in_month == 1 && !model.disable_housing
        households(model) do hh, model
            housing_decisions(hh, model)
        end

        mortgage_market(model.mortgage_market, model)

        banks(model) do bank, model
            fire_sell_seized_property(bank, model)
        end

        housing_market(model.housing_market, model)
        rental_market(model.housing_market, model)
    end

    households(model) do hh, model
        determine_consumption_budget(hh, model)
    end

    !model.disable_shares && financial_market(model.financial_market, model)

    households(model) do hh, model
        review_consumption_budget(hh, model)
    end

    consumption_goods_market(model.goods_market, model)

    households(model) do hh, model
        end_of_day(hh, model)
    end

    firms(model) do firm, model
        end_of_day(firm, model)
    end

    capital_goods_producer(model) do producer, model
        end_of_day(producer, model)
    end

    government(model) do gov, model
        end_of_day(gov, model)
    end

    end_of_day(model.financial_market, model)

    banks(model) do bank, model
        end_of_day(bank, model)
    end

    model.day_in_month == 1 && compute_monthly_statistics(model.mortgage_market, model)

    model.day_in_month == 20 && compute_monthly_statistics(model.statistics, model)

    if model.day_in_month == 20
        households(model) do hh, model
            update_wages(hh, model)
        end
    end

    assert_stock_flow_consistency(model.statistics, model)
end
