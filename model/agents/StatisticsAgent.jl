using DataFrames
using GLM

mutable struct Stocks
    total_inventory::Float64
    total_money::Float64
    total_reserves::Float64
    total_number_houses::Int64
end

function Stocks()
    return Stocks(0,0,0,0)
end

mutable struct Flows
    total_production::Float64
    total_consumption::Float64
    total_money_created::Float64
    total_money_destroyed::Float64
    total_inventory_destroyed::Float64
    total_reserves_created::Float64
    total_reserves_destroyed::Float64
end

function Flows()
    return Flows(0,0,0,0,0,0,0)
end

mutable struct StatisticsAgent <: AbstractAgent
    id::Int
    consumer_price_index::Float64
    consumer_price_index_history::Array{Float64, 1}
    consumer_price_index_yearly_growth::Float64
    inflation_qoq::Float64
    capacity_utilization_rate::Float64
    market_size::Float64
    market_size_history::Array{Float64, 1}
    market_size_estimation_intercept::Float64
    market_size_estimation_coefficient::Float64
    market_size_estimation_mean_squared_error::Float64
    market_size_estimation_variance::Float64
    minimum_consumption_level::Float64
    average_skill::Float64
    average_general_skill_group::Float64
    average_wage::Float64
    average_base_wage::Float64
    average_productivity::Float64
    average_productivity_history::Array{Float64, 1}
    average_productivity_yearly_growth::Float64
    average_productivity_monthly_growth::Float64
    total_employment::Float64
    unemployment_rate::Float64
    unemployment_rate_by_general_skill::Dict{Int64, Float64}
    unfilled_vacancies::Int
    total_money_households::Float64
    total_money_firms::Float64
    total_output_in_month::Float64
    total_planned_output_in_month::Float64
    total_debt::Float64
    total_mortgages::Float64
    total_equity_banks::Float64
    hh_monthly_total_income::Float64
    hh_monthly_labor_income::Float64
    hh_monthly_social_benefits::Float64
    hh_monthly_dividend_income::Float64
    hh_monthly_interest_income::Float64
    housing_number_tenants::Float64
    housing_number_owners::Float64
    housing_number_landlords::Float64
    housing_number_homeless::Float64
    housing_average_rent::Float64
    active_firms::Int64
    credit_rationed_firms::Int64
    credit_rationed_households::Int64
    total_investment::Float64
    average_vintage_choice::Float64
    share_firms_full_payout::Float64
    average_profit_firms::Float64
    average_dividends_firms::Float64
    income_percentiles::Dict{Float64, Float64}
    monthly_output::Float64
    cumulated_output::Float64
    monthly_output_history::CircularBuffer{Float64}
    monthly_output_growth_yoy::Float64
    mortgage_credit::Float64
    mortgage_credit_history::CircularBuffer{Float64}
    mortgage_credit_growth_yoy::Float64
    stocks::Stocks
    stocks_prev::Stocks
    flows::Flows
end

function StatisticsAgent(id)
    return StatisticsAgent(id,0,Array{Float64, 1}(),0,0,0,0,Array{Float64, 1}(),0,0,0,0,0,0,0,0,0,0,Array{Float64, 1}(),0, 0, 0, 0, Dict{Int64, Float64}(), 0, 0,0, 0, 0, 0, 0, 0, 0,0,0, 0, 0,0, 0, 0, 0, 0,0,0,0, 0, 0, 0, 0, 0, Dict{Float64, Float64}(),
    0,0,CircularBuffer{Float64}(12),0,0,CircularBuffer{Float64}(12),0,Stocks(), Stocks(), Flows())
end

function compute_monthly_statistics(stat::StatisticsAgent, model)
    if model.day_in_month == 20
        compute_consumer_price_index(stat, model)

        compute_and_estimate_market_size(stat, model)

        compute_average_productivity(stat, model)

        compute_household_statistics(stat, model)

        compute_bank_statistics(stat, model)

        set_interest_rate(stat, model)

        set_policies(stat, model)

        sum_employees = 0
        sum_active = 0
        for (id, firm) in model.active_firms
            sum_employees+=length(firm.employees)
        end
        sum_active = length(model.active_firms)
    end

end

function compute_consumer_price_index(stat::StatisticsAgent, model)
    total_supply = 0.0

    stat.total_money_firms = 0.0

    for (id, firm) in model.active_firms
        total_supply += firm.total_supply_in_month

        stat.total_money_firms += firm.payment_account
    end

    old_cpi = stat.consumer_price_index

    if total_supply > 0
        stat.consumer_price_index = 0.0
        for (id, firm) in model.active_firms
            stat.consumer_price_index += firm.price * firm.total_supply_in_month
        end
        stat.consumer_price_index = stat.consumer_price_index / total_supply
    end

    append!(stat.consumer_price_index_history, stat.consumer_price_index)
    if (length(stat.consumer_price_index_history) > 12)
        deleteat!(stat.consumer_price_index_history, 1)
        stat.consumer_price_index_yearly_growth = stat.consumer_price_index_history[12] / stat.consumer_price_index_history[1] - 1
        stat.inflation_qoq = stat.consumer_price_index_history[12] / stat.consumer_price_index_history[9] - 1
    end
end

function compute_and_estimate_market_size(stat::StatisticsAgent, model)
    stat.market_size = 0.0
    day = model.day

    consumption_budgets = Array{Float64, 1}()

    for (id, hh) in model.households
        stat.market_size += hh.consumption_budget_in_month
        push!(consumption_budgets, hh.consumption_budget_in_month)
    end
    stat.market_size = stat.market_size / stat.consumer_price_index

    stat.minimum_consumption_level = 0.5 * median(consumption_budgets)

    today = model.statistics.market_size_estimation_intercept + (model.market_size_estimation_horizon+12+1)*model.statistics.market_size_estimation_coefficient
    tomorrow = model.statistics.market_size_estimation_intercept + (model.market_size_estimation_horizon+12+11+1)*model.statistics.market_size_estimation_coefficient

    append!(stat.market_size_history, stat.market_size)
    if (length(stat.market_size_history) > model.market_size_estimation_horizon)
        deleteat!(stat.market_size_history, 1)
    end

    if length(stat.market_size_history) > 1

        data = DataFrame(month=Array(1:length(stat.market_size_history)), market_size=stat.market_size_history)

        ols = lm(@formula(market_size~month), data)

        stat.market_size_estimation_intercept = coef(ols)[1]
        stat.market_size_estimation_coefficient = coef(ols)[2]
        stat.market_size_estimation_mean_squared_error = deviance(ols)/(length(stat.market_size_history)-1)

        stat.market_size_estimation_variance = var(stat.market_size_history)
    end
end

function compute_household_statistics(stat::StatisticsAgent, model)
    sum_skills = 0.0
    sum_general_skill_group = 0.0
    sum_employed = 0
    sum_wages = 0.0
    n_wage = 0
    sum_money = 0.0

    count_by_skill_group = Dict{Int64, Int64}()
    employed_by_skill_group = Dict{Int64, Int64}()

    for g in model.general_skill_groups
        count_by_skill_group[g] = 0
        employed_by_skill_group[g] = 0
    end

    stat.hh_monthly_total_income = 0
    stat.hh_monthly_labor_income = 0
    stat.hh_monthly_dividend_income = 0
    stat.hh_monthly_interest_income = 0
    stat.hh_monthly_social_benefits = 0

    num_tenants = 0
    num_owners = 0
    num_landlords = 0
    num_homeless = 0
    sum_rent = 0.0

    credit_rationed = 0.0

    for (id, hh) in model.households
        count_by_skill_group[hh.general_skill_group] += 1

        sum_skills += hh.specific_skills
        sum_general_skill_group += hh.general_skill_group

        if hh.credit_rationed
            credit_rationed += 1
        end

        if hh.employer_id > 0
            sum_wages += hh.wage
            n_wage+=1
            sum_employed += 1
            employed_by_skill_group[hh.general_skill_group] += 1
        end
        sum_money +=  hh.payment_account

        stat.hh_monthly_labor_income += hh.labor_income_last_month
        stat.hh_monthly_dividend_income += hh.dividend_income_last_month
        stat.hh_monthly_interest_income += hh.interest_income_last_month
        stat.hh_monthly_social_benefits += hh.social_benefits_last_month

        if hh.rental_contract != nothing
            num_tenants+=1
            sum_rent += hh.rental_contract.rent
        end

        if hh.main_residence != nothing
            num_owners+=1
        end

        if hh.rental_contract == nothing && hh.main_residence == nothing
            num_homeless += 1
        end

        if length(hh.other_properties) > 0
            num_landlords+=1
        end

    end

    stat.credit_rationed_households = credit_rationed

    stat.housing_number_tenants = num_tenants
    stat.housing_number_owners = num_owners
    stat.housing_number_landlords = num_landlords
    stat.housing_number_homeless = num_homeless

    if num_tenants > 0
        stat.housing_average_rent = sum_rent / num_tenants
    end

    stat.hh_monthly_total_income = stat.hh_monthly_labor_income + stat.hh_monthly_dividend_income + stat.hh_monthly_interest_income + stat.hh_monthly_social_benefits

    stat.average_skill = sum_skills / length(model.households)
    stat.average_general_skill_group = sum_general_skill_group / length(model.households)

    if n_wage > 0
        stat.average_wage = sum_wages / n_wage
    end

    stat.total_employment = sum_employed
    stat.unemployment_rate = 1 - sum_employed / length(model.households)
    for g in model.general_skill_groups
        stat.unemployment_rate_by_general_skill[g] = 1 - employed_by_skill_group[g] / count_by_skill_group[g]
    end

    stat.total_money_households = sum_money
end

function compute_income_statistics(stat::StatisticsAgent, model)
    mean_net_incomes = []

    for (hh_id, hh) in model.households
        push!(mean_net_incomes, hh.mean_net_income)
    end

    percentiles = prank(mean_net_incomes)

    for i in 1:length(mean_net_incomes)
        stat.income_percentiles[mean_net_incomes[i]] = percentiles[i]
    end
end

function prank(arr::Array)
   n = length(arr)
   result = Array(Float64, n)

   for i in 1:n
      score = 0
      for j in 1:n
         score += arr[j] < arr[i] ? 1 : 0
         score += arr[j] == arr[i] ? 0.5 : 0
      end
      result[i] = score/n
    end
   result
end

function compute_bank_statistics(stat::StatisticsAgent, model)
    stat.total_debt = 0
    stat.total_mortgages = 0
    stat.total_equity_banks = 0

    for (id, bank) in model.banks
        if !bank.is_state_bank
            stat.total_debt += bank.total_loans
            stat.total_mortgages += bank.total_mortgages
            stat.total_equity_banks += bank.equity
        end
    end

    stat.mortgage_credit = stat.total_mortgages

    push!(stat.mortgage_credit_history, stat.mortgage_credit)

    mortgage_credit_history = convert(Vector{Float64}, stat.mortgage_credit_history)
    if length(mortgage_credit_history) == 12
        stat.mortgage_credit_growth_yoy = (mortgage_credit_history[12] / mortgage_credit_history[1])-1
    else
        stat.mortgage_credit_growth_yoy = 0.00
    end
end

function compute_average_productivity(stat::StatisticsAgent, model)
    sum_output = 0.0
    sum_potential_output = 0.0
    sum_labor = 0.0
    sum_unfilled_vacancies = 0.0
    sum_planned_output = 0.0
    active = 0
    credit_rationed = 0
    sum_vintage_choice = 0.0
    sum_investment = 0.0
    sum_full_payouts = 0
    sum_profit = 0
    sum_dividends = 0
    sum_base_wage = 0

    sum_used_capital = 0
    sum_total_capital = 0
    sum_last_production = 0
    for (id, firm) in model.active_firms#union(model.active_firms, model.inactive_firms)
        if firm.active
            sum_used_capital += firm.used_capital
            sum_last_production += firm.last_production
        end
        sum_total_capital += firm.total_capital
    end

    if sum_total_capital > 0.0
        stat.capacity_utilization_rate = sum_used_capital / sum_total_capital
    else
        stat.capacity_utilization_rate = 1
    end

    for (id, firm) in model.active_firms
        sum_output += firm.last_production
        sum_labor += length(firm.employees)
        sum_unfilled_vacancies += (firm.labor_demand - length(firm.employees))
        sum_planned_output += firm.planned_production
        sum_investment += firm.investment
        sum_vintage_choice += firm.vintage_choice
        sum_profit += firm.profit

        if firm.dividends_full
            sum_full_payouts += 1
        end

        if firm.active
            active+=1
            sum_profit += firm.profit
            sum_dividends += firm.dividends_due
            sum_base_wage += firm.base_wage
        end

        if firm.credit_rationed
            credit_rationed+=1
        end
    end
    if sum_labor > 0
        stat.average_productivity = sum_output / sum_labor
    end

    stat.total_output_in_month = sum_output
    stat.unfilled_vacancies = sum_unfilled_vacancies
    stat.total_planned_output_in_month = sum_planned_output
    stat.active_firms = active
    stat.credit_rationed_firms = credit_rationed
    stat.total_investment = sum_investment
    stat.average_vintage_choice = sum_vintage_choice / length(model.active_firms)
    stat.share_firms_full_payout = sum_full_payouts / length(model.active_firms)
    stat.average_profit_firms = sum_profit / active
    stat.average_dividends_firms = sum_dividends / active

    old_base_wage = stat.average_base_wage

    if active > 0
        stat.average_base_wage = sum_base_wage / active
    end

    append!(stat.average_productivity_history, stat.average_productivity)
    if (length(stat.average_productivity_history) > 12)
        deleteat!(stat.average_productivity_history, 1)
        stat.average_productivity_yearly_growth = stat.average_productivity_history[12] / stat.average_productivity_history[1] - 1
    end

    sum_growth_rates = 0.0
    num_obs = 0
    for i=2:length(stat.average_productivity_history)
        sum_growth_rates += stat.average_productivity_history[i] / stat.average_productivity_history[i-1]
        num_obs+=1
    end

    if num_obs > 0
        stat.average_productivity_monthly_growth = sum_growth_rates / num_obs - 1
    end

    stat.monthly_output = stat.total_output_in_month

    stat.cumulated_output += stat.monthly_output

    push!(stat.monthly_output_history, stat.monthly_output)

    output_history = convert(Vector{Float64}, stat.monthly_output_history)
    if length(output_history) == 12
        stat.monthly_output_growth_yoy = (output_history[12] / output_history[1])-1
    else
        stat.monthly_output_growth_yoy = 0.00
    end

end

function set_interest_rate(stat::StatisticsAgent, model)
    if !model.disable_taylor_rule
        cap_util_rate = min(max(0.6, stat.capacity_utilization_rate), 0.9)
        inflation_gap = min(max(-0.02, stat.consumer_price_index_yearly_growth - 0.019), 0.015)

        model.central_bank_rate = max(0.0, -0.097 + 0.15 * cap_util_rate + 1.42 * inflation_gap)
    end
end

function set_policies(stat::StatisticsAgent, model)
    if model.policy_dyn_ltv_cap
        x1 = -0.05
        y1 = 1.0
        x2 = 0.2
        y2 = 0.6

        m = (y2-y1)/(x2-x1)
        n = (y1*x2-y2*x1)/(x2-x1)

        ltv_cap = min(y1,max(y2,n + m * model.statistics.mortgage_credit_growth_yoy))

        model.ltv_cap = ltv_cap
    end
end

function approx_equal(a, b)
    return abs(a-b) < 1e-1
end

function assert_stock_flow_consistency(stat::StatisticsAgent, model)
    @assert approx_equal(stat.stocks.total_inventory, stat.stocks_prev.total_inventory - stat.flows.total_consumption + stat.flows.total_production - stat.flows.total_inventory_destroyed)
    @assert approx_equal(stat.stocks.total_money, stat.stocks_prev.total_money + stat.flows.total_money_created - stat.flows.total_money_destroyed)
    @assert approx_equal(stat.stocks.total_reserves, stat.stocks_prev.total_reserves + stat.flows.total_reserves_created - stat.flows.total_reserves_destroyed)
    @assert stat.stocks.total_number_houses == stat.stocks_prev.total_number_houses

    stat.stocks_prev = stat.stocks
    stat.stocks = Stocks()
    stat.flows = Flows()
end
