using Agents
using Distributions

mutable struct Mortgage
    bank::Bank
    household_id::Int64
    outstanding_principal::Float64
    outstanding_interest::Float64
    installment::Float64
    no_installments_left::Int64
    interest_rate::Float64
    repayment_started::Bool
end

mutable struct RentalContract
    landlord_id::Int64
    tenant_id::Int64
    house_id::Int64
    rent::Float64
    months_remaining::Int64
end

mutable struct House
    id::Int64
    quality::Float64
    rental_contract::Union{Nothing, RentalContract}
    mortgage::Union{Nothing, Mortgage}
    currently_on_rental_market::Bool
    currently_on_housing_market::Bool
    price::Float64
    months_on_market::Int64
end

mutable struct Household <: AbstractAgent
    id::Int
    payment_account::Float64
    payment_account_long_term::Float64
    bank_payment_account::Bank
    bank_next_mortgage::Bank
    shares_index_fund::Float64
    general_skill_group::Int64
    specific_skills::Float64
    employer_id::Int
    unemployed_since::Int
    wage::Float64
    reservation_wage::Float64
    payday::Int64
    consumption_budget::Float64
    consumption_budget_in_month::Float64
    consumption_budget_last_month::Float64
    consumption_budget_week::Float64
    consumption_remaining_weeks::Int64
    consumption_day::Int64
    selected_supplier_id::Int64
    labor_income::Float64
    dividend_income::Float64
    interest_income::Float64
    social_benefits::Float64
    rent_income::Float64
    net_income_history::CircularBuffer{Float64}
    mean_net_income::Float64
    labor_income_last_month::Float64
    dividend_income_last_month::Float64
    social_benefits_last_month::Float64
    interest_income_last_month::Float64
    rent_income_last_month::Float64
    btl_gene::Bool
    main_residence::Union{Nothing , House}
    rental_contract::Union{Nothing , RentalContract}
    other_properties::Dict{Int64, House}
    mortgage_payments_due::Float64
    rent_payments_due::Float64
    currently_looking_for_main_residence::Bool
    negative_credit_score_counter::Int64
    credit_rationed::Bool
    no_hmr::Int64
    no_op_occupied::Int64
    no_op_vacant::Int64
    no_hmr_for_sale::Int64
    no_op_for_sale::Int64
    homeless_before::Int64
    homeless_after::Int64
end

function Household(id)
    return Household(id,0,0,Bank(0),Bank(0),0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,CircularBuffer{Float64}(4),0,0,0,0,0,0,false,nothing,nothing,Dict{Int64, House}(),0,0,false, 0, false,0,0,0,0,0,0,0)
end

function collect_interest(hh::Household, model)
    interest = (1-model.central_bank_rate_markdown) * model.central_bank_rate / 240 * (hh.payment_account + hh.payment_account_long_term)

    hh.payment_account += interest
    hh.interest_income += interest
    hh.bank_payment_account.equity -= interest
    hh.bank_payment_account.deposits += interest
    hh.bank_payment_account.interest_expense_deposits += interest
end

function determine_consumption_budget(hh::Household, model)
    if model.day_in_month == hh.payday
        if hh.negative_credit_score_counter > 0
            hh.negative_credit_score_counter -=1
        end

        if hh.employer_id <= 0
            # Receive unemployment benefits if no employer
            hh.social_benefits = max(model.unemployment_replacement_rate * hh.wage, 0.5 * model.statistics.average_wage)
            gov_expense!(model.government, hh, hh.social_benefits)
        end

        # Pay taxes
        gross_income = hh.labor_income + hh.dividend_income + hh.interest_income + hh.rent_income + hh.social_benefits
        tax = pay_taxes!(model.government, hh, gross_income)

        net_income = gross_income - tax

        push!(hh.net_income_history, net_income)
        hh.mean_net_income = Statistics.mean(convert(Vector{Float64}, hh.net_income_history))

        value_shares = 0.0
        if !model.disable_shares
            value_shares = hh.shares_index_fund * model.financial_market.price
        end

        # Transfer from long-term payment account
        transfer_from_long_term = model.carrol_consumption_parameter_long_term * hh.payment_account_long_term
        hh.payment_account += transfer_from_long_term
        hh.payment_account_long_term -= transfer_from_long_term

        total_wealth = hh.payment_account + value_shares

        hh.rent_payments_due = 0.0
        hh.mortgage_payments_due = 0.0

        # determine mortgage and rent payments
        if !model.disable_housing
            hh.mortgage_payments_due = calculate_mortgage_payments(hh)
            if hh.rental_contract != nothing
                if hh.rental_contract.months_remaining > 0
                    hh.rent_payments_due = hh.rental_contract.rent
                else
                    terminate_rental_contract(hh, model)
                end
            end
        end

        disposable_income = max(0, hh.mean_net_income - hh.mortgage_payments_due - hh.rent_payments_due)

        hh.consumption_budget = disposable_income + model.carrol_consumption_parameter * (total_wealth - model.target_wealth_income_ratio * disposable_income) # Eq. (79)
        hh.consumption_budget_in_month = hh.consumption_budget

        budget_portfolio = hh.payment_account + value_shares - hh.consumption_budget - hh.mortgage_payments_due - hh.rent_payments_due

        if budget_portfolio < 0
            budget_portfolio = max(hh.payment_account + value_shares, hh.payment_account + value_shares - hh.consumption_budget - hh.rent_payments_due - hh.mortgage_payments_due)
        end

        @assert budget_portfolio > 0

        # Financial market
        if !model.disable_shares
            share_risky_asset = rand()

            net_investment = share_risky_asset * budget_portfolio - value_shares

            if net_investment > 0
                model.financial_market.demand_shares[hh] = net_investment/model.financial_market.price # Eq. (90), assuming infinite divisibility of shares
            end

            if net_investment < 0
                model.financial_market.supply_shares[hh] = -net_investment/model.financial_market.price # Eq. (91), assuming infinite divisibility of shares
            end
        end

        hh.consumption_day = model.day_in_week
        hh.consumption_remaining_weeks = 4

        hh.labor_income_last_month = hh.labor_income
        hh.dividend_income_last_month = hh.dividend_income
        hh.social_benefits_last_month = hh.social_benefits
        hh.interest_income_last_month = hh.interest_income
        hh.rent_income_last_month = hh.rent_income

        @model_log hh "determine_consumption_budget" "labor_income" hh.labor_income
        @model_log hh "determine_consumption_budget" "dividend_income" hh.dividend_income
        @model_log hh "determine_consumption_budget" "interest_income" hh.interest_income
        @model_log hh "determine_consumption_budget" "social_benefits" hh.social_benefits
        @model_log hh "determine_consumption_budget" "rent_income" hh.rent_income
        @model_log hh "determine_consumption_budget" "gross_income" gross_income
        @model_log hh "determine_consumption_budget" "taxes" tax
        @model_log hh "determine_consumption_budget" "consumption_budget" hh.consumption_budget_in_month

        # reset
        hh.labor_income = 0
        hh.dividend_income = 0
        hh.social_benefits = 0
        hh.interest_income = 0
        hh.rent_income = 0
    end

    if model.day_in_week == hh.consumption_day
        hh.consumption_budget_week = (hh.consumption_budget / hh.consumption_remaining_weeks)
        hh.consumption_remaining_weeks -= 1
    end
end

function terminate_rental_contract(hh::Household, model)
    landlord = model[hh.rental_contract.landlord_id]


    found = false
    for (house_id, house) in landlord.other_properties
        if house_id == hh.rental_contract.house_id
            house.rental_contract = nothing
            found = true
        end
    end

    @assert found

    hh.rental_contract = nothing
    hh.rent_payments_due = 0.0
end

function review_consumption_budget(hh::Household, model)
    if !model.disable_minimum_consumption
        min_consumption = model.statistics.minimum_consumption_level
    else
        min_consumption = 0.0
    end

    if !model.disable_sticky_consumption
        min_consumption = max(0.95 * hh.consumption_budget_last_month, model.statistics.minimum_consumption_level)
    end

    if model.day_in_month == hh.payday

        # Prio 1: rent payment
        if hh.rent_payments_due > 0
            landlord = model[hh.rental_contract.landlord_id]
            if  hh.payment_account - min_consumption > hh.rent_payments_due
                pay_rent(hh, landlord, model)
            else
                terminate_rental_contract(hh, model)
            end
        end

        # Prio 2: mortgage payments
        if hh.mortgage_payments_due > 0.0
            if hh.payment_account - min_consumption > hh.mortgage_payments_due
                pay_mortgages(hh, model)
            else
                default_on_mortgages(hh, model, min_consumption)
            end
        end

        # Review consumption budget in case HH has been rationed on financial market
        hh.consumption_budget = min(max(min_consumption, hh.consumption_budget), hh.payment_account) # Eq. (80)
        hh.consumption_budget_in_month = hh.consumption_budget
        hh.consumption_budget_week = (hh.consumption_budget / hh.consumption_remaining_weeks)

        hh.consumption_budget_last_month = hh.consumption_budget_in_month
    end
end

function calculate_mortgage_payments(hh::Household)
    sum = 0.0

    # main residence
    if hh.main_residence != nothing && hh.main_residence.mortgage != nothing
        mortgage = hh.main_residence.mortgage
        sum += mortgage.installment
    end

    # other porperties
    for (h_id, house) in hh.other_properties
        mortgage = house.mortgage
        if mortgage != nothing && mortgage.repayment_started
            sum += mortgage.installment
        end
    end
    return sum
end

function pay_rent(hh::Household, landlord::Household, model)
    bank_transfer!(hh, landlord, hh.rental_contract.rent, note="rent")

    hh.rental_contract.months_remaining -= 1

    @assert hh.rental_contract.months_remaining >= 0

    landlord.rent_income += hh.rental_contract.rent
end

function default_on_mortgages(hh::Household, model, min_consumption)
    hh.negative_credit_score_counter = model.months_negative_credit_score_after_default

    # default on other properties first
    other_properties = sort(filter(x->x[2].mortgage != nothing, collect(hh.other_properties)), by=x->x[2].mortgage.outstanding_principal, rev=true)

    for (h_id, op) in other_properties
        # default
        if op.mortgage != nothing && hh.mortgage_payments_due > hh.payment_account - min_consumption
            hh.mortgage_payments_due -= op.mortgage.installment

            op.currently_on_housing_market = false
            op.currently_on_rental_market = false

            if op.rental_contract != nothing
                tenant = model[op.rental_contract.tenant_id]
                tenant.rental_contract = nothing
                tenant.rent_payments_due = 0.0
                op.rental_contract = nothing
            end

            bank = op.mortgage.bank
            bank.seized_properties[op.id] = op

            bank.number_mortgages -= 1
            bank.number_mortgages_defaulted += 1

            pop!(hh.other_properties, op.id)
        end
    end

    if hh.mortgage_payments_due > max(0.0, hh.payment_account - min_consumption)+ 1e-5
        hmr = hh.main_residence

        @assert hmr != nothing
        @assert hmr.mortgage != nothing

        hmr.currently_on_housing_market = false
        hmr.currently_on_rental_market = false

        bank = hmr.mortgage.bank
        bank.seized_properties[hmr.id] = hmr

        bank.number_mortgages -= 1
        bank.number_mortgages_defaulted += 1

        hh.main_residence = nothing
    end
end

function pay_mortgages(hh::Household, model)
    mortgages = Dict{Mortgage, House}()

    # main residence
    if hh.main_residence != nothing && hh.main_residence.mortgage != nothing
        mortgages[hh.main_residence.mortgage] = hh.main_residence
    end

    # other porperties
    for (h_id, house) in hh.other_properties
        mortgage = house.mortgage
        if mortgage != nothing
            mortgages[mortgage] = house
        end
    end

    for (mortgage, house) in mortgages
        if mortgage.repayment_started

            bank_mortgage = mortgage.bank

            interest = mortgage.interest_rate/12 * mortgage.outstanding_principal
            repayment = mortgage.installment - interest

            @assert hh.payment_account > (mortgage.installment -1e-6)

            hh.payment_account -= mortgage.installment
            hh.bank_payment_account.reserves -= mortgage.installment
            hh.bank_payment_account.deposits -= mortgage.installment
            bank_mortgage.reserves += mortgage.installment
            bank_mortgage.total_mortgages -= repayment
            bank_mortgage.equity += interest
            bank_mortgage.interest_income_loans += interest

            model.statistics.flows.total_money_destroyed += repayment

            mortgage.outstanding_principal -= repayment
            mortgage.outstanding_interest -= interest
            mortgage.no_installments_left -= 1

            @assert mortgage.no_installments_left > -0.01
            @assert mortgage.outstanding_principal > -0.01
            @assert mortgage.outstanding_interest > -0.01

            if mortgage.no_installments_left == 0
                @assert approx_equal(mortgage.outstanding_principal, 0.0)
                @assert approx_equal(mortgage.outstanding_interest, 0.0)

                bank_mortgage.number_mortgages -= 1
                bank_mortgage.number_mortgages_repaid += 1

                # delete mortgage
                house.mortgage = nothing
            end
        else
            # Start repaying next month
            mortgage.repayment_started = true
        end
    end
end

function housing_decisions(hh::Household, model)
    hh.currently_looking_for_main_residence = false
    hh.credit_rationed = false

    hh.no_hmr = 0
    hh.no_op_vacant = 0
    hh.no_op_occupied = 0
    hh.no_hmr_for_sale = 0
    hh.no_op_for_sale = 0
    hh.homeless_before = 0

    if hh.main_residence == nothing && hh.rental_contract == nothing
        # Agent in social housing
        housing_decisions_in_social_housing(hh, model)
        hh.homeless_before=1
    end

    if hh.main_residence != nothing
        # Agent owns main residence
        housing_decisions_owner(hh, model)
    end

    if hh.btl_gene
        housing_decisions_btl(hh, model)
    end
end

function housing_decisions_in_social_housing(hh::Household, model)
    if !model.disable_hpi_growth_objective
        hpi_growth = model.housing_market.house_price_index_growth
    else
        hpi_growth = 0
    end

    desired_expenditure = (model.housing_market_alpha * 12 * hh.mean_net_income * exp(rand(Normal(0,0.5))))/(1-model.housing_market_beta*hpi_growth)

    max_funds = max(0.0,hh.payment_account - (hh.consumption_budget_in_month + hh.rent_payments_due + hh.mortgage_payments_due)+ hh.payment_account_long_term)
    max_downpayment = model.housing_market_fraction_downpayment*max_funds

    hh.bank_next_mortgage, house_value, downpayment, annuity = calculate_mortgage_conditions(model.mortgage_market, model, desired_expenditure, max_downpayment, hh.mean_net_income, true)

    estimated_quality = estimate_quality(model.housing_market, house_value)

    estimated_rent = estimate_rental_price(model.housing_market, estimated_quality)

    cost_renting = (12 * estimated_rent)*(1 - model.psycological_cost_renting)
    cost_mortgage = 12*annuity + downpayment / (model.mortgage_duration_months / 12)

    prob_buy=exp(-model.gamma_hmr*log(cost_mortgage))/(exp(-model.gamma_hmr*log(cost_mortgage))+exp(-model.gamma_hmr*log(cost_renting)))

    if rand() < prob_buy && hh.negative_credit_score_counter == 0
        # Bid on housing market
        ltv = (house_value - downpayment) / house_value
        model.housing_market.housing_market_bids[HousingMarketBid(hh, house_value, true, ltv)] = house_value
        hh.currently_looking_for_main_residence = true
    else
        # Bid on rental market
        desired_expenditure = 0.33*hh.mean_net_income

        model.housing_market.rental_market_bids[HousingMarketBid(hh, desired_expenditure, true,0.0)] = desired_expenditure
    end
end

function housing_decisions_owner(hh::Household, model)
    house = hh.main_residence

    hh.no_hmr += 1

    if !house.currently_on_housing_market
        prob_sell = model.probability_selling_hmr

        if rand() < prob_sell
            # Sell main residence
            house.price = estimate_house_price(model.housing_market, house.quality)
            if house.mortgage == nothing || house.price > house.mortgage.outstanding_principal
                house.months_on_market = 1
                house.currently_on_housing_market = true
                model.housing_market.housing_market_offers[HousingMarketOffer(hh, house.price, house)] = house.price

                hh.no_hmr_for_sale += 1
            end
        end
    else
        house.months_on_market += 1
        if rand() < model.housing_market_prob_price_adjustment
            # Adjust price
            house.price = house.price * max(0.5,(1-exp(-rand(Normal(1.603,0.617)))))
        end
        if house.mortgage != nothing && house.price < house.mortgage.outstanding_principal
            # withdraw from market
            house.currently_on_housing_market = false
            house.months_on_market = 1
        else
            model.housing_market.housing_market_offers[HousingMarketOffer(hh, house.price, house)] = house.price

            hh.no_hmr_for_sale += 1
        end
    end
end

function housing_decisions_btl(hh::Household, model)
    if !model.disable_btl_trading
        # Buy new property?
        q = rand()

        estimated_house_price = estimate_house_price(model.housing_market, q)

        max_funds = hh.payment_account - (hh.consumption_budget_in_month + hh.rent_payments_due + hh.mortgage_payments_due) + hh.payment_account_long_term
        max_downpayment = model.housing_market_fraction_downpayment*max_funds
        bank, house_value, downpayment, annuity = calculate_mortgage_conditions(model.mortgage_market, model, estimated_house_price, max_downpayment, hh.mean_net_income, false)

        estimated_rent = estimate_rental_price(model.housing_market, q)

        mortgage_payment = annuity + downpayment / (model.mortgage_duration_months / 12) / 12

        if !model.disable_hpi_growth_objective
            hpi_growth = model.housing_market.house_price_index_growth
        else
            hpi_growth = 0
        end

        capital_gain_objective_prob = 1/(1+exp(-model.gamma_btl*(hpi_growth-model.shift_sigmoid_capital_gain_objective)))

        rental_yield_objective_prob = 1/(1+exp(-model.gamma_btl*((estimated_rent / mortgage_payment)-model.shift_sigmoid_rental_yield_objective)))

        prob_buy = model.lambda_btl * capital_gain_objective_prob + (1-model.lambda_btl) * rental_yield_objective_prob

        if rand() < prob_buy && !hh.currently_looking_for_main_residence && hh.negative_credit_score_counter == 0
            hh.bank_next_mortgage = bank
            ltv = (house_value - downpayment) / house_value
            model.housing_market.housing_market_bids[HousingMarketBid(hh, house_value, false, ltv)] = house_value
        end

        # Adjust prices for houses to be sold
        for (h_id, house) in hh.other_properties
            if house.currently_on_housing_market
                house.months_on_market += 1

                if rand() < model.housing_market_prob_price_adjustment
                    # Adjust price
                    house.price = house.price * max(0.5,(1-exp(-rand(Normal(1.603,0.617)))))

                    @assert house.price > -0.001
                end

                if house.mortgage != nothing && house.price < house.mortgage.outstanding_principal
                    # withdraw from market
                    house.currently_on_housing_market = false
                    house.currently_on_rental_market = true
                    house.price = estimate_rental_price(model.housing_market, house.quality)

                    house.months_on_market = 1
                else
                    model.housing_market.housing_market_offers[HousingMarketOffer(hh, house.price, house)] = house.price

                    hh.no_op_for_sale += 1
                end
            end
        end

        # Sell existing property?
        for (h_id, house) in hh.other_properties
            if house.rental_contract != nothing
                hh.no_op_occupied += 1
            end

            if house.rental_contract == nothing
                hh.no_op_vacant +=1
                if house.currently_on_housing_market == false
                    # Tenant just moved out
                    x = hpi_growth

                    prob_sell = 1 - (1/(1+exp(-10*(x-0.2))))

                    if rand() < prob_sell
                        estimated_price = estimate_house_price(model.housing_market, house.quality)

                        @assert estimated_price > -0.00001

                        if house.mortgage == nothing || estimated_price > house.mortgage.outstanding_principal
                            house.price = estimated_price
                            house.months_on_market = 1
                            house.currently_on_housing_market = true
                            house.currently_on_rental_market = false
                            model.housing_market.housing_market_offers[HousingMarketOffer(hh, house.price, house)] = house.price

                            hh.no_op_for_sale += 1
                        end
                    end
                end
            end
        end
    end

    # rent out proerties not for sale
    for (h_id, house) in hh.other_properties
        if house.rental_contract == nothing && !house.currently_on_housing_market
            if !house.currently_on_rental_market
                # Put house on rental market for the first time after tenant moved out
                house.price = estimate_rental_price(model.housing_market, house.quality)
                house.currently_on_rental_market = true
                house.months_on_market = 1
            else
                # Adjust price
                house.price = house.price * (1-model.rental_market_price_adjustment)
                house.months_on_market += 1
            end
            model.housing_market.rental_market_offers[HousingMarketOffer(hh, house.price, house)] = house.price

        end
    end

    @assert hh.payment_account > -1e-6
end

function end_of_day(hh::Household, model)
    if model.disable_long_term_saving
        hh.payment_account += hh.payment_account_long_term
        hh.payment_account_long_term = 0
    end

    model.statistics.stocks.total_money += hh.payment_account + hh.payment_account_long_term

    if hh.main_residence != nothing
        model.statistics.stocks.total_number_houses += 1
    end

    model.statistics.stocks.total_number_houses += length(collect(keys(hh.other_properties)))

    if model.day_in_month == 1
        if hh.rental_contract == nothing && hh.main_residence == nothing
            hh.homeless_after = 1
        else
            hh.homeless_after = 0
        end
    end

    @assert hh.payment_account > -1e-6
end

function update_wages(hh::Household, model)
    if hh.employer_id > 0
        hh.wage = (1+model.statistics.average_productivity_monthly_growth) * hh.wage
    end
end
