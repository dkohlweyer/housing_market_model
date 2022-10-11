using Agents
using DataStructures

mutable struct Bank <: AbstractAgent
    id::Int
    active_business::Bool
    is_state_bank::Bool
    activation_day::Int
    reserves::Float64
    total_loans::Float64
    total_mortgages::Float64
    number_loans::Int64
    number_loans_new::Int64
    number_loans_defaulted::Int64
    number_loans_repaid::Int64
    number_loans_in_month_history::CircularBuffer{Int64}
    number_loans_defaulted_in_month_history::CircularBuffer{Int64}
    volume_loans_restructured::Float64
    volume_loans_restructured_in_month_history::CircularBuffer{Float64}
    volume_loss_loans_restructured::Float64
    volume_loss_loans_restructured_in_month_history::CircularBuffer{Float64}
    number_mortgages::Int64
    number_mortgages_new::Int64
    number_mortgages_defaulted::Int64
    number_mortgages_repaid::Int64
    number_mortgages_in_month_history::CircularBuffer{Int64}
    number_mortgages_defaulted_in_month_history::CircularBuffer{Int64}
    volume_mortgages_liquidated::Float64
    volume_mortgages_liquidated_in_month_history::CircularBuffer{Float64}
    volume_loss_liquidations::Float64
    volume_loss_liquidations_in_month_history::CircularBuffer{Float64}
    deposits::Float64
    central_bank_debt::Float64
    equity::Float64
    interest_income_loans::Float64
    interest_income_reserves::Float64
    interest_expense_central_bank_debt::Float64
    interest_expense_deposits::Float64
    writeoff_loans::Float64
    writeoff_loans_in_month::Float64
    writeoff_mortgages::Float64
    writeoff_mortgages_in_month::Float64
    profit::Float64
    profit_history::CircularBuffer{Float64}
    risk_exposure_amount::Float64
    funding_costs::Float64
    funding_costs_history::CircularBuffer{Float64}
    seized_properties::Dict{Int64, Any}
    loan_pd_pit::Float64
    loan_pd_pit_yearly::Float64
    loan_lgd_pit::Float64
    mortgage_pd_pit::Float64
    mortgage_pd_pit_yearly::Float64
    mortgage_lgd_pit::Float64
    risk_weight_firm_loans::Float64
    risk_weight_mortgages::Float64
    mortgage_interest_rate::Float64
    mortgage_interest_rate_spread::Float64
    capital_adequacy_ratio::Float64
end

function Bank(id)
    return Bank(id, false,false,0,0,0,0,0,0,0,0,CircularBuffer{Int64}(3),CircularBuffer{Int64}(3),0,CircularBuffer{Float64}(120),0,CircularBuffer{Float64}(120),0,0,0,0,CircularBuffer{Int64}(3),CircularBuffer{Int64}(3),0,CircularBuffer{Float64}(120),0,CircularBuffer{Float64}(120),0,0,0,0,0,0,0,0,0,0,
    0,0,CircularBuffer{Float64}(12),0,0,CircularBuffer{Float64}(3),Dict{Int64, Any}(),0,0,0,0,0,0,0,0,0,0,0)
end

function bank_transfer!(from, to, amount; note="")
    if from isa Bank
        transfer_from_equity!(from, to, amount)
    else
        from.payment_account -= amount
        from.bank_payment_account.reserves -= amount
        from.bank_payment_account.deposits -= amount

        to.payment_account += amount
        to.bank_payment_account.reserves += amount
        to.bank_payment_account.deposits += amount
    end
end

function transfer_from_equity!(from::Bank, to, amount)
    from.equity -= amount
    from.reserves -= amount

    to.payment_account += amount
    to.bank_payment_account.reserves += amount
    to.bank_payment_account.deposits += amount
end

function monthly_settlement(bank::Bank, model)
    gross_profit = bank.interest_income_loans + bank.interest_income_reserves - bank.interest_expense_deposits - bank.interest_expense_central_bank_debt - bank.writeoff_loans - bank.writeoff_mortgages # Eq. (60), including writeoffs

    # Pay taxes
    tax = pay_taxes!(model.government, bank, gross_profit)

    bank.profit = gross_profit - tax
    push!(bank.profit_history, bank.profit)

    # Dividend payment
    average_profit = Statistics.mean(convert(Vector{Float64}, bank.profit_history))

    dividends = model.dividend_earnings_ratio * max(0.0, average_profit)

    if dividends > 0.0
        transfer_from_equity!(bank, model.financial_market, dividends)
        model.financial_market.total_dividends += dividends
    end

    # Funding costs
    funding_costs = 12 * (bank.interest_expense_deposits + bank.interest_expense_central_bank_debt) / (bank.total_mortgages + bank.total_loans)
    push!(bank.funding_costs_history, funding_costs)

    bank.funding_costs = Statistics.mean(convert(Vector{Float64}, bank.funding_costs_history))

    # PD / LGD calculation Loans
    number_loans_in_month = max(0, bank.number_loans - bank.number_loans_new + bank.number_loans_repaid)

    @assert number_loans_in_month >= 0

    push!(bank.number_loans_in_month_history, number_loans_in_month)
    push!(bank.number_loans_defaulted_in_month_history, bank.number_loans_defaulted)

    sum_loan_defaults = sum(convert(Vector{Int64}, bank.number_loans_defaulted_in_month_history))
    mean_loans = mean(convert(Vector{Int64}, bank.number_loans_in_month_history))

    if mean_loans > 0.0
        bank.loan_pd_pit = sum_loan_defaults / mean_loans
    else
        bank.loan_pd_pit = 0
    end

    bank.loan_pd_pit_yearly = 1-(1-bank.loan_pd_pit)^(12/length(bank.number_loans_defaulted_in_month_history))

    push!(bank.volume_loans_restructured_in_month_history, bank.volume_loans_restructured)
    push!(bank.volume_loss_loans_restructured_in_month_history, bank.volume_loss_loans_restructured)

    sum_loss = sum(convert(Vector{Float64}, bank.volume_loss_loans_restructured_in_month_history))
    sum_restructured = sum(convert(Vector{Float64}, bank.volume_loans_restructured_in_month_history))
    if sum_restructured > 0.0
        bank.loan_lgd_pit = sum_loss / sum_restructured
    else
        bank.loan_lgd_pit = 0
    end

    bank.number_loans_new = 0
    bank.number_loans_defaulted = 0
    bank.number_loans_repaid = 0
    bank.volume_loans_restructured = 0
    bank.volume_loss_loans_restructured = 0

    # PD / LGD calculation Mortgages
    number_mortgages_in_month = bank.number_mortgages - bank.number_mortgages_new + bank.number_mortgages_repaid + bank.number_mortgages_defaulted

    @assert number_mortgages_in_month >= 0

    push!(bank.number_mortgages_in_month_history, number_mortgages_in_month)
    push!(bank.number_mortgages_defaulted_in_month_history, bank.number_mortgages_defaulted)

    sum_defaults = sum(convert(Vector{Int64}, bank.number_mortgages_defaulted_in_month_history))
    mean_mortgages = mean(convert(Vector{Int64}, bank.number_mortgages_in_month_history))

    if mean_mortgages > 0.0
        bank.mortgage_pd_pit = sum_defaults / mean_mortgages
    else
        bank.mortgage_pd_pit = 0
    end

    bank.mortgage_pd_pit_yearly = 1-(1-bank.mortgage_pd_pit)^(12/length(bank.number_mortgages_defaulted_in_month_history))

    push!(bank.volume_mortgages_liquidated_in_month_history, bank.volume_mortgages_liquidated)
    push!(bank.volume_loss_liquidations_in_month_history, bank.volume_loss_liquidations)

    sum_loss = sum(convert(Vector{Float64}, bank.volume_loss_liquidations_in_month_history))
    sum_liquidations = sum(convert(Vector{Float64}, bank.volume_mortgages_liquidated_in_month_history))

    if sum_liquidations > 0.0
        bank.mortgage_lgd_pit = sum_loss / sum_liquidations
    else
        bank.mortgage_lgd_pit = 0
    end

    calculate_risk_weights(bank, model)

    # Set mortgage interest rate
    pd = 1-(1-bank.mortgage_pd_pit_yearly)^(1/12.0)
    lgd = bank.mortgage_lgd_pit
    f = max(0.0, bank.funding_costs)
    pr = model.mortgage_profit_rate
    if !model.disable_endegenous_mortgage_interest_rate
        bank.mortgage_interest_rate = max(0.00001, (f + pr) + 12.0 * pd * lgd / (1-pd))
        bank.mortgage_interest_rate_spread = bank.mortgage_interest_rate - bank.funding_costs
    else
        bank.mortgage_interest_rate = model.mortgage_interest_rate
    end

    compute_risk_exposure_amounts(model)

    bank.capital_adequacy_ratio = bank.equity / bank.risk_exposure_amount

    bank.number_mortgages_new = 0
    bank.number_mortgages_defaulted = 0
    bank.number_mortgages_repaid = 0
    bank.volume_mortgages_liquidated = 0
    bank.volume_loss_liquidations = 0

    @model_log bank "monthly_settlement" "interest_income_loans" bank.interest_income_loans
    @model_log bank "monthly_settlement" "interest_income_reserves" bank.interest_income_reserves
    @model_log bank "monthly_settlement" "interest_expense_deposits" bank.interest_expense_deposits
    @model_log bank "monthly_settlement" "interest_expense_central_bank_debt" bank.interest_expense_central_bank_debt
    @model_log bank "monthly_settlement" "writeoff_loans" bank.writeoff_loans
    @model_log bank "monthly_settlement" "gross_profit" gross_profit
    @model_log bank "monthly_settlement" "tax" tax
    @model_log bank "monthly_settlement" "dividends" dividends

    @model_log bank "balance_sheet" "reserves" bank.reserves
    @model_log bank "balance_sheet" "loans" bank.total_loans
    @model_log bank "balance_sheet" "mortgages" bank.total_mortgages
    @model_log bank "balance_sheet" "deposits" bank.deposits
    @model_log bank "balance_sheet" "central_bank_debt" bank.central_bank_debt
    @model_log bank "balance_sheet" "equity" bank.equity

    bank.writeoff_loans_in_month = bank.writeoff_loans
    bank.writeoff_mortgages_in_month = bank.writeoff_mortgages

    # reset variables
    bank.interest_income_loans = 0.0
    bank.interest_income_reserves = 0.0
    bank.interest_expense_deposits = 0.0
    bank.interest_expense_central_bank_debt = 0.0
    bank.writeoff_loans = 0.0
    bank.writeoff_mortgages = 0.0
end

function calculate_risk_weights(bank::Bank, model)
    i = 2
    j = 2

    while i < length(model.mortgage_risk_weight_lookup[i]) && model.mortgage_risk_weight_lookup[i][1] <= bank.mortgage_pd_pit_yearly
        i+=1
    end

    while j < length(model.mortgage_risk_weight_lookup[1]) && model.mortgage_risk_weight_lookup[1][j] <= bank.mortgage_lgd_pit
        j+=1
    end

    bank.risk_weight_mortgages = model.mortgage_risk_weight_lookup[i][j]

    i = 2
    j = 2

    while i < length(model.firm_loan_risk_weight_lookup) && model.firm_loan_risk_weight_lookup[i][1] <= bank.loan_pd_pit_yearly
        i+=1
    end

    while j < length(model.firm_loan_risk_weight_lookup[1]) && model.firm_loan_risk_weight_lookup[1][j] <= bank.loan_lgd_pit
        j+=1
    end

    bank.risk_weight_firm_loans = model.firm_loan_risk_weight_lookup[i][j]
end

function end_of_day(bank::Bank, model)
    diff_to_min_reserves = bank.reserves - model.minimum_reserve_requirement * bank.deposits

    if diff_to_min_reserves < 0
        bank.reserves += -diff_to_min_reserves
        bank.central_bank_debt += -diff_to_min_reserves
        model.statistics.flows.total_reserves_created += -diff_to_min_reserves
    else
        repay = min(bank.central_bank_debt, diff_to_min_reserves)
        bank.central_bank_debt -= repay
        bank.reserves -= repay
        model.statistics.flows.total_reserves_destroyed += repay
    end

    min_reserves = model.minimum_reserve_requirement * bank.deposits
    excess_reserves = bank.reserves - min_reserves

    if !bank.is_state_bank
        interest_reserves = model.central_bank_rate/240 * min_reserves + (model.central_bank_rate*(1-model.excess_reserves_markdown))/240 * excess_reserves
        bank.interest_income_reserves += interest_reserves
        bank.equity += interest_reserves
        bank.reserves += interest_reserves
        model.statistics.flows.total_money_created += interest_reserves
        model.statistics.flows.total_reserves_created += interest_reserves

        interest_cb_debt = model.central_bank_rate/240 * bank.central_bank_debt
        bank.interest_expense_central_bank_debt += interest_cb_debt
        bank.equity -= interest_cb_debt
        bank.reserves -= interest_cb_debt
        model.statistics.flows.total_money_destroyed += interest_cb_debt
        model.statistics.flows.total_reserves_destroyed += interest_cb_debt

        if bank.equity < 0.0
            #bank.active_business = false
        else
            bank.active_business = true
        end
    end

    model.statistics.stocks.total_money += bank.equity
    model.statistics.stocks.total_reserves += bank.reserves

    model.statistics.stocks.total_number_houses += length(collect(keys(bank.seized_properties)))

    @assert approx_equal(bank.reserves + bank.total_loans + bank.total_mortgages, bank.deposits + bank.central_bank_debt + bank.equity)
end

function fire_sell_seized_property(bank::Bank, model)
    for (h_id, house) in bank.seized_properties
        price = (1-model.markdown_bank_selling)*estimate_house_price(model.housing_market, house.quality)
        house.currently_on_housing_market = true
        model.housing_market.housing_market_offers[HousingMarketOffer(bank, house.price, house)] = house.price
    end
end

function house_sold!(bank::Bank, model, buyer, house, price)
    original_owner = model[house.mortgage.household_id]

    principal = house.mortgage.outstanding_principal
    diff = price - principal

    if diff >= 0
        # bank made no loss. transfer money to original owner
        bank_transfer!(buyer, original_owner, diff, note="DIFF")

        # payback mortgage
        buyer.payment_account -= principal
        bank.reserves += principal
        buyer.bank_payment_account.reserves -= principal
        buyer.bank_payment_account.deposits -= principal
        bank.total_mortgages -= principal

        bank.volume_loss_liquidations += 0
        bank.volume_mortgages_liquidated += principal

    else
        # bank made a loss
        loss = -diff

        buyer.payment_account -= price
        bank.reserves += price
        buyer.bank_payment_account.reserves -= price
        buyer.bank_payment_account.deposits -= price

        bank.total_mortgages -= principal
        bank.equity -= loss

        bank.writeoff_mortgages += loss

        bank.volume_loss_liquidations += loss
        bank.volume_mortgages_liquidated += principal
    end

    model.statistics.flows.total_money_destroyed += principal

    @assert buyer.payment_account > 1e-5

    # Delete seized house from bank
    pop!(bank.seized_properties, house.id)
end
