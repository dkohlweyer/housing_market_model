using Agents
using Distributions
using DataFrames
using DataStructures
using GLM
using Statistics

mutable struct Firm <: AbstractAgent
    id::Int
    active::Bool
    counter_months_inactive::Int64
    payment_account::Float64
    total_value_inventory::Float64
    total_value_capital::Float64
    total_debt::Float64
    equity::Float64
    bank_payment_account::Bank
    activation_day::Int64
    total_capital::Float64
    used_capital::Float64
    last_production::Float64
    planned_production::Float64
    inventory::Float64
    price::Float64
    vintages::Dict{Int64,Float64}
    employees::Dict{Int64,Household}
    loans::Dict{Loan,Bank}
    last_loan_interest_rate::Float64
    labor_demand::Int64
    capital_demand::Float64
    credit_demand::Float64
    vintage_choice::Int64
    base_wage::Float64
    wage_offer::Dict{Int64,Float64}
    vacancies::Int64
    average_technology::Float64
    productivity::Float64
    productivity_progress::Float64
    total_supply_in_month::Float64
    next_market_research_day::Int64
    estimated_demand::Float64
    estimated_demand_schedule::Array{Float64, 1}
    estimated_demand_schedule_pos::Int64
    estimated_demand_variance::Float64
    demand_buffer::Float64
    revenue::Float64
    revenue_history::CircularBuffer{Float64}
    profit::Float64
    profit_history::CircularBuffer{Float64}
    investment::Float64
    investment_history::CircularBuffer{Float64}
    monthly_depreciation::Float64
    labor_costs::Float64
    interest_income::Float64
    interest_expense::Float64
    credit_repaid::Float64
    credit_raised::Float64
    gross_profit::Float64
    taxes_due::Float64
    dividends_due::Float64
    dividends_full::Bool
    credit_rationed::Bool
    expected_market_size::Float64
    error_market_size::Float64
    expected_market_share::Float64
    error_market_share::Float64
    random_layoffs::Float64
    intentional_layoffs::Float64
    market_research_active::Bool
    market_research_participants::Int64
    market_research_prices::Array{Float64, 1}
    market_research_pos_responses_today::Array{Float64, 1}
    market_research_pos_responses_future::Array{Float64, 1}
    market_research_variance::Array{Float64, 1}
    selected_price::Int64
    error_demand_estimation::Float64
end

function Firm(id)
    return Firm(id, false, 0, 0,0,0,0,0,Bank(0), 0, 0, 0, 0, 0, 0,0,Dict(), Dict(), Dict(), 0, 0, 0, 0, 0, 0, Dict{Int64, Float64}(), 0, 0, 0,0,0,0,0,zeros(Float64, 0),0,0,0,0,CircularBuffer{Float64}(6),0,CircularBuffer{Float64}(4),0,CircularBuffer{Float64}(18),0,0,0,0,0,0,0,0,0,false,false,0,0,0,0,0,0,false,0,zeros(Float64, 0),zeros(Float64, 0),zeros(Float64, 0),zeros(Float64, 0),0,0)
end

function collect_interest(firm::Firm, model)
    interest = (1-model.central_bank_rate_markdown) * model.central_bank_rate / 240 * firm.payment_account

    firm.payment_account += interest
    firm.interest_income += interest
    firm.bank_payment_account.equity -= interest
    firm.bank_payment_account.deposits += interest
    firm.bank_payment_account.interest_expense_deposits += interest
end

function monthly_settlement(firm::Firm, model)
    sold_units = firm.revenue / firm.price

    firm.error_demand_estimation = abs(sold_units/firm.estimated_demand - 1)

    # Check inactivity
    if !firm.active
        firm.counter_months_inactive+=1

        if firm.counter_months_inactive == 12
            reactivate(firm, model)
        end
    end

    # Calculatory capital costs
    calc_capital_costs = 0.0
    for inv in firm.investment_history
        calc_capital_costs += inv/model.firm_credit_period
    end

    firm.gross_profit = firm.revenue + firm.interest_income - firm.labor_costs - firm.interest_expense - calc_capital_costs  # Eqs. (23)-(26)

    # Compute taxes
    firm.taxes_due = max(0.0, firm.gross_profit * model.government.tax_rate)

    firm.profit = firm.gross_profit - firm.taxes_due # Eq. (27)

    push!(firm.revenue_history, firm.revenue)
    push!(firm.profit_history, firm.profit)

    # Dividend payment
    average_revenue = Statistics.mean(convert(Vector{Float64}, firm.revenue_history))
    average_profit = Statistics.mean(convert(Vector{Float64}, firm.profit_history))

    if firm.payment_account < model.firm_dividend_threshold_full_payout*average_revenue
        firm.dividends_due = model.dividend_earnings_ratio * max(0.0, average_profit) # Eq. (28), using smoothed net profit
        firm.dividends_full = false
    else
        firm.dividends_due = max(0.0, average_profit) # Pay out full profit, if firm is hoarding money
        firm.dividends_full = true
    end

    accounting(firm, model)

    @model_log firm "monthly_settlement" "revenue" firm.revenue
    @model_log firm "monthly_settlement" "labor_costs" firm.labor_costs
    @model_log firm "monthly_settlement" "investment" firm.investment
    @model_log firm "monthly_settlement" "interest_income" firm.interest_income
    @model_log firm "monthly_settlement" "interest_expense" firm.interest_expense
    @model_log firm "monthly_settlement" "credit_repaid" firm.credit_repaid
    @model_log firm "monthly_settlement" "credit_raised" firm.credit_raised
    @model_log firm "monthly_settlement" "calc_capital_costs" calc_capital_costs
    @model_log firm "monthly_settlement" "gross_profit" firm.gross_profit
    @model_log firm "monthly_settlement" "taxes_due" firm.taxes_due
    @model_log firm "monthly_settlement" "dividends_due" firm.dividends_due

    @model_log firm "balance_sheet" "capital_stock" firm.total_value_capital
    @model_log firm "balance_sheet" "inventory" firm.total_value_inventory
    @model_log firm "balance_sheet" "payment_account" firm.payment_account
    @model_log firm "balance_sheet" "debt" firm.total_debt
    @model_log firm "balance_sheet" "equity" firm.equity

    # reset variables
    firm.revenue = 0
    firm.labor_costs = 0
    firm.interest_expense = 0
    firm.interest_income = 0
    firm.credit_repaid = 0
    firm.credit_raised = 0
end

function calculate_writedown_factor_insolvency(firm::Firm, model)
    assets = max(0.0, firm.total_value_capital + firm.payment_account)
    target_debt = model.debt_rescaling_factor * assets # Eq. (58)
    return target_debt / firm.total_debt
end

function bankruptcy_procedure(firm::Firm, model, writedown_factor)
    @assert writedown_factor > -1e-3
    @assert writedown_factor < 1.0 + 1e-3

    firm.active = false
    firm.counter_months_inactive = 0
    firm.labor_demand = 0
    model.statistics.flows.total_inventory_destroyed += firm.inventory
    firm.inventory = 0

    pop!(model.active_firms, firm.id)
    model.inactive_firms[firm.id] = firm

    # debt restructuring
    for (loan, bank) in firm.loans
        writeoff = (1-writedown_factor) * loan.principal

        bank.number_loans_defaulted += 1
        bank.volume_loans_restructured += loan.principal
        bank.volume_loss_loans_restructured += writeoff

        loan.principal = writedown_factor * loan.principal
        loan.installment = writedown_factor * loan.installment

        bank.equity -= writeoff
        bank.total_loans -= writeoff
        bank.writeoff_loans += writeoff

        firm.total_debt -= writeoff

        model.statistics.flows.total_money_destroyed += writeoff

        if loan.principal < 1e-6
            pop!(firm.loans, loan)
        end

        @model_log firm "crisis" "loan_writeoff" writeoff
    end
end

function reactivate(firm::Firm, model)
    firm.active = true
    firm.counter_months_inactive = 0
    firm.price = model.statistics.consumer_price_index
    pop!(model.inactive_firms, firm.id)
    model.active_firms[firm.id] = firm

    market_research(firm, model)

    # Assign new random market research day
    firm.next_market_research_day = model.day + rand(1:model.firm_planning_horizon_months*20)

    @model_log firm  "crisis" "reactivated"
end

function production_planning(firm::Firm, model)
    firm.monthly_depreciation = depreciate_capital_stock(firm, model)

    if firm.estimated_demand_schedule_pos > length(firm.estimated_demand_schedule)
        firm.estimated_demand_schedule_pos = length(firm.estimated_demand_schedule)
    end

    # Calculate plannend production quantity based on demand estimate
    firm.estimated_demand = firm.estimated_demand_schedule[firm.estimated_demand_schedule_pos]
    firm.estimated_demand_schedule_pos += 1
    firm.demand_buffer = model.quantile_production_planning * sqrt(firm.estimated_demand_variance)
    firm.planned_production = max(0.0, firm.estimated_demand + firm.demand_buffer - firm.inventory) # Eqs. (2)-(3)

    # Determine labor and capital demand
    firm.labor_demand, firm.capital_demand = determine_labor_and_capital_demand(firm, model, firm.planned_production, model.investment_inertia * firm.monthly_depreciation)

    @model_log firm "planning" "estimated_demand" firm.estimated_demand
    @model_log firm "planning" "demand_buffer" firm.demand_buffer
    @model_log firm "planning" "planned_production" firm.planned_production
    @model_log firm "planning" "labor_demand" firm.labor_demand
    @model_log firm "planning" "capital_demand" firm.capital_demand
end

function determine_labor_and_capital_demand(firm::Firm, model, planned_production, max_investment)
    average_skill = get_average_skill(firm, model)

    if firm.last_production > 0 && length(firm.employees) > 0
        effective_productivity = firm.last_production / length(firm.employees) # feeds into Eq. (9) below
    else
        effective_productivity = model.statistics.average_skill
    end

    return determine_labor_and_capital_demand(planned_production, max_investment, firm.vintage_choice, firm.vintages, average_skill, effective_productivity, model)
end

function determine_labor_and_capital_demand(planned_production, max_investment, vintage_choice, vintages::Dict{Int64,Float64}, average_skill, effective_productivity, model)
    feasible_production = determine_feasible_production(vintages, average_skill, model)

    total_capital = calculate_total_capital(vintages)

    if feasible_production < planned_production
        capital_demand = (planned_production - feasible_production) / min(model.capital_goods_producer.vintage_productivities[vintage_choice], average_skill) # Eq. (10)
        labor_demand = round(total_capital + capital_demand) # Eq. (11)
    else
        capital_demand = 0
        labor_demand = round(planned_production / effective_productivity) # Eq. (9)
    end

    if labor_demand == 0
        capital_demand = 0.0
    end

    return labor_demand, capital_demand
end

function financial_planning(firm::Firm, model) # Eq. (32)-(33)
    # Determine credit demand
    prospective_labor_costs = firm.labor_demand * get_average_wage(firm, model)
    prospective_capital_expense = firm.capital_demand * model.capital_goods_producer.vintage_prices[firm.vintage_choice]
    prospective_principal_payments, prospective_interest_payments = calculate_loan_payments(firm)
    firm.credit_demand = max(0.0, (1+model.financial_planning_buffer)*(prospective_labor_costs + prospective_capital_expense + prospective_principal_payments + prospective_interest_payments + firm.taxes_due + firm.dividends_due) - firm.payment_account)


    if firm.payment_account < prospective_interest_payments + firm.taxes_due
        bankruptcy_procedure(firm, model, model.debt_rescaling_factor)
    end

    @model_log firm "planning" "credit_demand" firm.credit_demand
end

function calculate_loan_payments(firm::Firm)
    sum_principal = 0.0
    sum_interest = 0.0

    for (loan, bank) in firm.loans
        if loan.repayment_started
            sum_interest += loan.interest_rate/12 * loan.principal
            sum_principal += loan.installment + loan.interest_rate/12 * loan.principal
        end
    end

    return sum_principal, sum_interest
end

function financial_and_production_replanning(firm::Firm, model)
    prospective_labor_costs = firm.labor_demand * get_average_wage(firm, model)
    prospective_capital_expense = firm.capital_demand * model.capital_goods_producer.vintage_prices[firm.vintage_choice]
    prospective_principal_payments, prospective_interest_payments = calculate_loan_payments(firm)

    production_costs = prospective_labor_costs + prospective_capital_expense
    payments_due = prospective_principal_payments + prospective_interest_payments + firm.taxes_due + firm.dividends_due

    if firm.payment_account < production_costs + payments_due
        firm.credit_rationed = true

        if firm.payment_account < payments_due
            if firm.payment_account >= payments_due - firm.dividends_due
                # Liquidity problem can be resolved by not paying dividends
                firm.dividends_due = 0.0

                @model_log firm "crisis" "dividends_set_zero"
            else
                # Firm declares bankruptcy
                @model_log firm "crisis" "bankruptcy_due_to_illiquidity"

                bankruptcy_procedure(firm, model, model.debt_rescaling_factor) # Eq. (59), implicit
            end
        else
            # rescale production
            while firm.payment_account < production_costs + payments_due
                firm.planned_production = 0.98*firm.planned_production
                firm.labor_demand, firm.capital_demand = determine_labor_and_capital_demand(firm, model, firm.planned_production, model.investment_inertia * firm.monthly_depreciation)

                prospective_labor_costs = firm.labor_demand * get_average_wage(firm, model)
                prospective_capital_expense = firm.capital_demand * model.capital_goods_producer.vintage_prices[firm.vintage_choice]
                production_costs = prospective_labor_costs + prospective_capital_expense
            end

            @model_log firm "crisis" "production_rescaled" firm.planned_production
        end
    else
        firm.credit_rationed = false
    end
end

function invest(firm::Firm, model)
    # Rescale capital demand if rationed on labor market
    if firm.capital_demand > 0
        total_capital = calculate_total_capital(firm)
        firm.capital_demand = max(0.0, length(firm.employees) - total_capital)
    end

    # Buy capital goods if demand (still) positive
    if firm.capital_demand > 0  # Eq. (6), investment term
        v = firm.vintage_choice

        if v in keys(firm.vintages)
            firm.vintages[v] += firm.capital_demand
        else
            firm.vintages[v] = firm.capital_demand
        end

        firm.investment = firm.capital_demand * model.capital_goods_producer.vintage_prices[v]
        bank_transfer!(firm, model.capital_goods_producer, firm.investment)
        model.capital_goods_producer.revenue += firm.investment
    else
        firm.investment = 0
    end

    push!(firm.investment_history, firm.investment)
end


function depreciate_capital_stock(vintages::Dict{Int64,Float64}, model) # Eq. (6), w/o investment
    depreciation = 0.0 # in units
    for (v, c) in vintages
        depreciation += model.depreciation_rate * vintages[v]
        vintages[v] -= model.depreciation_rate * vintages[v]
    end

    return depreciation
end

function depreciate_capital_stock(firm::Firm, model)
    depreciate_capital_stock(firm.vintages, model)
end

function calculate_total_capital(vintages::Dict{Int64,Float64}) # Eq. (5)
    total_capital = 0
    for (v, c) in vintages
        total_capital += vintages[v]
    end
    return total_capital
end

function calculate_total_capital(firm::Firm)
    return calculate_total_capital(firm.vintages)
end

function determine_feasible_production(vintages::Dict{Int64,Float64}, average_skill, model) # Eq. (8), assuming depreciation already acounted for.
    feasible_production = 0
    for (v, c) in vintages
        feasible_production += c * min(model.capital_goods_producer.vintage_productivities[v], average_skill)
    end
    return feasible_production
end

function determine_feasible_production(firm::Firm, model)
    return determine_feasible_production(firm.vintages, get_average_skill(firm, model), model)
end

function fire_employees(firm::Firm, model)
    if model.day_in_month == firm.activation_day
        # intentional firing
        number_layoffs = max(0, length(firm.employees) - firm.labor_demand)

        employees_sorted_by_general_skill = sort(shuffle(collect(firm.employees)), by=x->x[2].general_skill_group)

        @assert number_layoffs <= length(firm.employees)

        for (hh_id, hh) in employees_sorted_by_general_skill[1:number_layoffs]
            hh.employer_id = -1
            hh.unemployed_since = model.day
            pop!(firm.employees, hh_id)
        end

        # random firing
        number_layoffs_random = Int(round(rand(Uniform(model.fraction_random_layoffs_l, model.fraction_random_layoffs_u))*length(firm.employees)))

        for (hh_id, hh) in shuffle(collect(firm.employees))[1:min(number_layoffs_random, length(firm.employees))]
            hh.employer_id = -1
            hh.unemployed_since = model.day
            pop!(firm.employees, hh_id)
        end

        firm.vacancies = max(0, firm.labor_demand - length(firm.employees))

        @model_log firm "labor_market" "layoffs" number_layoffs
        @model_log firm "labor_market" "random_layoffs" number_layoffs_random
        @model_log firm "labor_market" "vacancies" firm.vacancies

        calculate_wage_offers(firm, model)

        if firm.vacancies > 0
            # offer positions at labor market
            model.labor_market.job_postings[firm.id] = firm
        end
    end
end

function calculate_wage_offers(firm::Firm, model)
    firm.wage_offer = Dict{Int64,Float64}()

    average_skills = get_average_skill_by_groups(firm, model)
    average_technology = firm.average_technology

    for g in model.general_skill_groups
        firm.wage_offer[g] = firm.base_wage * min(average_technology, average_skills[g]) # Eq. (17), using *effective* skill group productivity
    end
end

function production_function(vintages, average_skill, no_workers, model) # Eq. (7)
    best_vintage = maximum(keys(vintages))
    remaining_workers = no_workers

    technology=0.0
    used_vintages=0

    production = 0
    for i in 1:best_vintage
        v = best_vintage + 1 - i

        if v in keys(vintages)
            workers = min(vintages[v], remaining_workers)
            remaining_workers -= workers

            production += workers * min(model.capital_goods_producer.vintage_productivities[v], average_skill)

            technology += workers * model.capital_goods_producer.vintage_productivities[v]
            used_vintages += workers
        end
    end

    return production, used_vintages, technology / used_vintages
end

function production(firm::Firm, model)
    average_skill = get_average_skill(firm, model)

    firm.total_capital = calculate_total_capital(firm)

    if length(firm.employees) > 0
        production, firm.used_capital, firm.average_technology = production_function(firm.vintages, average_skill, length(firm.employees), model)

        last_productivity = firm.productivity

        if average_skill >= firm.average_technology
            firm.productivity = firm.average_technology
        else
            firm.productivity = average_skill
        end

        firm.productivity_progress = firm.productivity / last_productivity - 1.0
    else
        production = 0
    end

    firm.inventory += production
    firm.total_supply_in_month = firm.inventory

    firm.last_production = production

    model.statistics.flows.total_production += production

    @model_log firm "production" "total_capital" calculate_total_capital(firm.vintages)
    @model_log firm "production" "labor_force" length(firm.employees)
    @model_log firm "production" "output" production
end

function payments(firm::Firm, model)
    # Pay wages and update skills
    for (id, hh) in firm.employees
        bank_transfer!(firm, hh, hh.wage, note="wage")

        firm.labor_costs += hh.wage
        hh.labor_income += hh.wage
        hh.reservation_wage = hh.wage

        hh.specific_skills = hh.specific_skills + model.skill_update_formula(hh.general_skill_group) * max(0.0, firm.average_technology - hh.specific_skills) # Eq. (15)
    end

    # loans and interest
    firm.interest_expense = 0
    for (loan, bank_loan) in firm.loans
        if loan.repayment_started
            interest = loan.interest_rate/12 * loan.principal
            firm.interest_expense += interest

            firm.payment_account -= (loan.installment + interest)
            firm.bank_payment_account.reserves -= (loan.installment + interest)
            firm.bank_payment_account.deposits -= (loan.installment + interest)
            firm.total_debt -= loan.installment
            bank_loan.reserves += (loan.installment + interest)
            bank_loan.total_loans -= loan.installment
            bank_loan.equity += interest
            bank_loan.interest_income_loans += interest

            model.statistics.flows.total_money_destroyed += loan.installment

            loan.principal -= loan.installment
            loan.no_installments_left -= 1

            firm.credit_repaid += loan.installment

            @assert loan.no_installments_left > -0.0001
            @assert loan.principal > -0.0001
            @assert firm.total_debt > -0.0001

            if loan.no_installments_left == 0
                @assert approx_equal(loan.principal, 0.0)

                bank_loan.number_loans_repaid += 1

                pop!(firm.loans, loan)
            end
        else
            # Start repaying next month
            loan.repayment_started = true
        end
    end

    # Taxes
    taxes = pay_taxes!(model.government, firm, firm.gross_profit)

    # Dividends
    if firm.dividends_due > 0.0
        bank_transfer!(firm, model.financial_market, firm.dividends_due)
        model.financial_market.total_dividends += firm.dividends_due
    end
end

function get_average_skill(firm::Firm, model)
    if length(firm.employees) > 0
        sum_skills = 0
        for (id, hh) in firm.employees
            sum_skills += hh.specific_skills
        end
        return sum_skills / length(firm.employees)
    else
        return model.statistics.average_skill
    end
end

function get_average_skill_by_groups(firm::Firm, model)
    sum_skills = Dict{Int64,Float64}()
    n = Dict{Int64,Int64}()
    avg_skills = Dict{Int64,Float64}()

    default_avg_skill = get_average_skill(firm, model)

    for g in model.general_skill_groups
        sum_skills[g] = 0
        n[g] = 0
    end

    for (id, hh) in firm.employees
        sum_skills[hh.general_skill_group] += hh.specific_skills
        n[hh.general_skill_group] += 1
    end

    for g in model.general_skill_groups
        if n[g] > 0
            avg_skills[g] = sum_skills[g] / n[g]
        else
            avg_skills[g] = default_avg_skill
        end
    end

    return avg_skills
end

function get_average_general_skill_group(firm::Firm, model)
    if length(firm.employees) > 0
        sum_skill_groups = 0
        for (id, hh) in firm.employees
            sum_skill_groups += hh.general_skill_group
        end
        return sum_skill_groups / length(firm.employees)
    else
        return model.statistics.average_general_skill_group
    end
end


function get_average_wage(firm::Firm, model)
    if length(firm.employees) > 0
        sum_wages = 0.0
        for (id, hh) in firm.employees
            sum_wages += hh.wage
        end
        return sum_wages / length(firm.employees)
    else
        return model.statistics.average_wage
    end
end

function calculate_average_technology(vintages::Dict{Int64,Float64}, model)
    sum_tech_weighted = 0.0
    sum_weights = 0.0
    for (v, c) in vintages
        sum_tech_weighted += vintages[v] * model.capital_goods_producer.vintage_productivities[v]
        sum_weights += vintages[v]
    end

    return sum_tech_weighted / sum_weights
end

function calculate_average_technology(firm::Firm, model)
    return calculate_average_technology(firm.vintages, model)
end

function choose_vintage(firm::Firm, model)
    average_skill = get_average_skill(firm, model)
    average_skill_group = get_average_general_skill_group(firm, model)

    exps = Array{Float64, 1}()
    sum_exps = 0.0

    vintages = Array{Int64, 1}()

    for (v, vintage_productivity) in model.capital_goods_producer.vintage_productivities # Eq. (14)
        vintage_price = model.capital_goods_producer.vintage_prices[v]

        effective_productivity = calculate_estimated_future_productivity(model, vintage_productivity, average_skill, average_skill_group)
        expvalue = exp(model.gamma_vintage*log(effective_productivity/vintage_price))
        push!(exps, expvalue)
        push!(vintages, v)
        sum_exps += expvalue
    end

    probs = map((x)->x/sum_exps, exps)

    return sample(vintages, Weights(probs))
end

function market_research(firm::Firm, model)
    if model.fixed_production
        no_firms = (length(model.active_firms) + length(model.inactive_firms))
        fixed_prod = (model.statistics.average_productivity * length(model.households)) / no_firms

        firm.estimated_demand_variance = 0
        firm.estimated_demand_schedule = fill(fixed_prod, model.firm_planning_horizon_months)
        firm.estimated_demand_schedule_pos = 1

        firm.price = model.statistics.market_size / (fixed_prod * no_firms)

        firm.next_market_research_day = firm.next_market_research_day + model.firm_planning_horizon_months*20

        return
    end

    # Prepare
    number_prices = Int(floor((model.market_research_end_price - model.market_research_start_price) / model.market_research_increment))

    firm.market_research_participants = model.market_research_no_questionaires

    firm.market_research_pos_responses_today = zeros(Float64, number_prices)
    firm.market_research_pos_responses_future = zeros(Float64, number_prices)
    firm.market_research_variance = zeros(Float64, number_prices)

    # Prepare
    number_prices = Int(floor((model.market_research_end_price - model.market_research_start_price) / model.market_research_increment))

    firm.price = model.statistics.consumer_price_index

    prices = Array{Float64,1}()
    for i in 1:number_prices
        append!(prices, firm.price*(model.market_research_start_price + (i-1)*model.market_research_increment))
    end

    firm.market_research_prices = prices

    # Do surveys
    competitor_prices_today = []

    for (firm_id, f) in model.active_firms
        if f.id != firm.id && f.last_production > 0.0#1 * model.statistics.average_productivity
            append!(competitor_prices_today, f.price)
        end
    end

    competitor_prices_future = competitor_prices_today.*(1+model.statistics.consumer_price_index_yearly_growth)^(model.firm_planning_horizon_months/12)

    for i in 1:length(firm.market_research_prices)
        price = firm.market_research_prices[i]

        pos_today = zeros(5)
        pos_future = zeros(5)

        for j in 1:5
            pos_today[j] = survey_market(price, competitor_prices_today, model.gamma_consumption, firm.market_research_participants)
            pos_future[j] = survey_market(price, competitor_prices_future, model.gamma_consumption, firm.market_research_participants)
        end

        firm.market_research_pos_responses_today[i] = mean(pos_today)
        firm.market_research_pos_responses_future[i] = mean(pos_future)

        firm.market_research_variance[i] = (StatsBase.var(pos_today) + StatsBase.var(pos_future)) / 2
    end

    market_research_analyze(firm, model)
end

function market_research_analyze(firm::Firm, model)
    firm.market_research_active = false
    firm.next_market_research_day = firm.next_market_research_day + model.firm_planning_horizon_months*20

    prices = firm.market_research_prices

    if !model.disable_regression
        market_share_function_today, variance_today = log_regression_market_share(prices, firm.market_research_pos_responses_today, firm.market_research_variance, firm.market_research_participants)
        market_share_function_one_year, variance_one_year = log_regression_market_share(prices, firm.market_research_pos_responses_future, firm.market_research_variance, firm.market_research_participants)
    else
        market_share_function_today, variance_today = no_regression_market_share(prices, firm.market_research_pos_responses_today, firm.market_research_variance, firm.market_research_participants)
        market_share_function_one_year, variance_one_year = no_regression_market_share(prices, firm.market_research_pos_responses_future, firm.market_research_variance, firm.market_research_participants)
    end

    prices_and_demand_schedule = Dict{Float64, Array{Float64, 1}}()
    profits = Dict{Float64, Float64}()

    # Choose vintage
    chosen_vintage = choose_vintage(firm, model)
    firm.vintage_choice = chosen_vintage

    max_profit = -99999999999999.0
    price_max_profit = 0.0
    demand_schedule_max_profit = zeros(12)

    for price in prices

        market_share_today = market_share_function_today[price]
        market_share_end_of_year = market_share_function_one_year[price]

        error_today = variance_today[price]

        expected_market_share = market_share_function_today[price]
        error_market_share = error_today / firm.market_research_participants^2
        expected_market_size = model.statistics.market_size_estimation_intercept
        error_market_size = model.statistics.market_size_estimation_mean_squared_error

        # Calculate demand variance
        demand_variance = expected_market_share^2 * error_market_size + expected_market_size^2 * error_market_share + error_market_share * error_market_size

        discounted_profit, demand_schedule = simulate_planning_period(firm, model, price, market_share_today, market_share_end_of_year, demand_variance)

        if discounted_profit > max_profit
            max_profit = discounted_profit
            price_max_profit = price
            demand_schedule_max_profit = demand_schedule

            firm.estimated_demand_variance = demand_variance

            firm.selected_price = indexin(price, prices)[1]
		end
    end

    firm.price = price_max_profit
    firm.estimated_demand_schedule = demand_schedule_max_profit
    firm.estimated_demand_schedule_pos = 1

    @assert firm.price > 0

    @model_log firm "market_research" "new_price" firm.price
    @model_log firm "market_research" "estimated_demand_schedule" firm.estimated_demand_schedule
end

function simulate_planning_period(firm::Firm, model, price, market_share_today, market_share_end_of_year, demand_variance)
    profit_discounted_sum = 0.0
    demand_schedule = zeros(model.firm_planning_horizon_months)

    # Copy firm variables
    estimated_stock = 0
    payment_account = firm.payment_account
    no_employees = length(firm.employees)
    last_production = firm.last_production
    average_skill = get_average_skill(firm, model)
    average_technology = firm.average_technology
    average_wage = get_average_wage(firm, model)
    average_general_skill_group = get_average_general_skill_group(firm, model)
    vintages = deepcopy(firm.vintages)
    investment_history = deepcopy(firm.investment_history)
    loans = deepcopy(firm.loans)
    revenue_history = deepcopy(firm.revenue_history)
    profit_history = deepcopy(firm.profit_history)
    dividends_due = firm.dividends_due
    taxes_due = firm.taxes_due

    m = model.firm_planning_horizon_months-1

    for t in 0:m
        # Depreciate capital stock
        depriciation = depreciate_capital_stock(vintages, model)
        total_capital = calculate_total_capital(vintages) # Eq. (42)

        # Determine production quantity
        estimated_market_share = ((m-t)*market_share_today+t*market_share_end_of_year)/m # Eq. (38)
        estimated_market_size = model.statistics.market_size_estimation_intercept + (model.market_size_estimation_horizon+1+t)*model.statistics.market_size_estimation_coefficient # Eq. (35)
        estimated_demand = max(0.0, estimated_market_share * estimated_market_size) # Eq. (39)

        demand_schedule[t+1] = estimated_demand
        planned_production = max(0.0, estimated_demand + model.quantile_production_planning * sqrt(demand_variance) - estimated_stock) # Eq. (40)-(41)

        # Determine labor and capital demand
        if last_production > 0 && no_employees > 0
            effective_productivity = last_production / no_employees
        else
            effective_productivity = model.statistics.average_skill
        end
        labor_demand, capital_demand = determine_labor_and_capital_demand(planned_production, model.investment_inertia * depriciation, firm.vintage_choice, vintages, average_skill, effective_productivity, model) # Eq. (45)-(47)

        # Invest
        if capital_demand > 0
            if !(firm.vintage_choice in keys(vintages))
                vintages[firm.vintage_choice] = 0
            end
            vintages[firm.vintage_choice] += capital_demand

    		# Use production function to recalculate average technology
            _, _, average_technology = production_function(vintages, average_skill, labor_demand, model)

            if (average_technology > -1e-6) == false
                println(average_technology)
                flush(stdout)
            end

            @assert average_technology > -1e-6

            nominal_investment = capital_demand * model.capital_goods_producer.vintage_prices[firm.vintage_choice]
        else
            nominal_investment = 0
        end

        # Hire/Fire employees
        if labor_demand > 0
            average_wage = average_wage * min(1.0, no_employees / labor_demand) + firm.base_wage * min(average_technology, average_skill) * max(0.0, (labor_demand - no_employees)/labor_demand) # Eq. (49)
        end
        no_employees = labor_demand

        # Production
        if no_employees > 0
            last_production, _, average_technology = production_function(vintages, average_skill, no_employees, model)
        else
            last_production = 0
        end
        estimated_stock += last_production

        @assert last_production > -1e-6
        @assert estimated_stock > -1e-6

        # Calculate variable costs
        labor_costs = average_wage * labor_demand

        if last_production > 0.0
            var_labor_costs = labor_costs / last_production
            var_capital_costs = nominal_investment / model.firm_credit_period / last_production
        else
            var_labor_costs = average_wage / effective_productivity
            var_capital_costs = model.capital_goods_producer.vintage_prices[firm.vintage_choice] / effective_productivity
        end

        # Calculate fixed capital costs
        fixed_capital_costs = 0.0
        for inv in investment_history
            fixed_capital_costs += inv/model.firm_credit_period
        end

        # Credit costs
        credit_costs = 0.0
        installments = 0.0
        for (loan, bank_loan) in loans
            credit_costs += loan.interest_rate/12 * loan.principal

            installments+=loan.installment

            loan.principal -= loan.installment
            loan.no_installments_left -= 1

            if loan.no_installments_left == 0
                @assert approx_equal(loan.principal, 0.0)
                pop!(loans, loan)
            end
        end

        # New loans
        expenses = taxes_due + dividends_due + labor_costs + nominal_investment + credit_costs + installments # Eq. (51)

        if (expenses > payment_account)
            new_loan_amount = expenses - payment_account # Eq. (52)
            new_loan = Loan(firm.bank_payment_account, new_loan_amount, new_loan_amount/model.firm_credit_period, model.firm_credit_period, firm.last_loan_interest_rate, true, 0.0)
            loans[new_loan] = firm.bank_payment_account

            payment_account+=new_loan_amount # Eq. (53), additional credit
        end

        # Sales
        realized_demand = min(estimated_demand, estimated_stock)
        estimated_stock -= realized_demand

        # Update average skill
        average_skill = average_skill + model.skill_update_formula(average_general_skill_group) * max(0, average_technology - average_skill) # Eq. (44)

        @assert average_skill > 1e-6

        revenue = price*realized_demand # Eq. (54)
        payment_account += revenue - expenses # Eq. (53), w/o additional credit

        # Calculate profit
        var_costs = var_labor_costs + var_capital_costs # Eq. (49)
        fix_costs = fixed_capital_costs + credit_costs # Eq. (50)

        profit = realized_demand*(price - var_costs) - fix_costs # Eq. (55)

        @assert realized_demand > -1e-6

        profit_discounted_sum += (1/(1+model.discount_rate))^t * profit # Eq. (56)

        # Accounting, taxes and dividends for next period
        taxes_due = max(0.0, profit * model.government.tax_rate)

        push!(revenue_history, revenue)
        push!(profit_history, profit - taxes_due)
        push!(investment_history, nominal_investment)

        average_revenue = Statistics.mean(convert(Vector{Float64}, revenue_history))
        average_profit = Statistics.mean(convert(Vector{Float64}, profit_history))

        if firm.payment_account < model.firm_dividend_threshold_full_payout*average_revenue
            dividends_due = model.dividend_earnings_ratio * max(0.0, average_profit)
        else
            dividends_due = max(0.0, average_profit)
        end

        average_wage = average_wage * (1+model.statistics.average_productivity_monthly_growth)

    end

    return profit_discounted_sum, demand_schedule
end

function survey_market(price, competitor_prices, gamma, no_questionaires)
    sum_logit_denom = 0.0

    for competitor_price in competitor_prices
        sum_logit_denom += exp(-gamma*log(competitor_price))
    end

    prob = max(0.0,min(1.0, exp(-gamma*log(price)) / (sum_logit_denom + exp(-gamma*log(price))))) # Eq. (36)

    counter=0
    for i in 1:no_questionaires
        if rand() < prob
            counter+=1
        end
    end

    return counter
end

function survey_market_mult_prices(prices, competitor_prices, gamma, no_questionaires)
    pos_responses = Array{Float64,1}()

    for price in prices
        pos = survey_market(price, competitor_prices, gamma, no_questionaires)

        append!(pos_responses, pos)
    end

    return pos_responses
end

function log_regression_market_share(prices, pos_responses, variances, no_questionaires)
    log_counts = Array{Float64,1}()

    market_share_function = Dict{Float64, Float64}()
    variance_function = Dict{Float64, Float64}()

    for p in pos_responses
        append!(log_counts, log(max(0.1, p)))
    end

    data = DataFrame(prices = prices, log_counts = log_counts)
    ols = lm(@formula(log_counts~prices), data)

    intercept = coef(ols)[1]
    coefficient = coef(ols)[2]

    for price in prices
        market_share_function[price] = exp(intercept + coefficient*price) / no_questionaires  # Eq. (37)
    end

    mean_squared_error = sum((exp.(log_counts)-exp.(predict(ols))).^2/(length(log_counts)-1))

    for i in 1:length(prices)
        price = prices[i]

        variance_function[price] = variances[i]
    end

    return market_share_function, variance_function
end

function no_regression_market_share(prices, pos_responses, variances, no_questionaires)
    market_share_function = Dict{Float64, Float64}()
    variance_function = Dict{Float64, Float64}()

    for i in 1:length(prices)
        price = prices[i]

        market_share_function[price] = pos_responses[i] / no_questionaires  # Eq. (37)
        variance_function[price] = variances[i]
    end

    return market_share_function, variance_function

end

function estimate_market_share_function(model, prices, competitor_prices)
    pos_responses = survey_market_mult_prices(prices, competitor_prices, model.gamma_consumption, model.market_research_no_questionaires)

    return log_regression_market_share(prices, pos_responses, model.market_research_no_questionaires)
end

function accounting(firm::Firm, model)
    firm.total_value_inventory = firm.inventory * model.statistics.consumer_price_index
    firm.total_value_capital = 0
    for (v, c) in firm.vintages
        firm.total_value_capital += c * model.capital_goods_producer.vintage_prices[v]
    end

    firm.equity = firm.payment_account + firm.total_value_inventory + firm.total_value_capital - firm.total_debt
end

function end_of_day(firm::Firm, model)
    # Accounting
    accounting(firm, model)


    # default
    if firm.active && firm.equity < 0
        @model_log firm "crisis" "bankruptcy_negative_equity"
        #bankruptcy_procedure(firm, model, calculate_writedown_factor_insolvency(firm, model))
    end

    model.statistics.stocks.total_inventory += firm.inventory
    model.statistics.stocks.total_money += firm.payment_account

    @assert firm.inventory > -1e-5
end
