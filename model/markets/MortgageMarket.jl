mutable struct MortgageMarket <: AbstractAgent
    id::Int
    mortgage_requests::Dict{Household, Float64}
    ltv_requested::Array{Float64}
    ltv_granted::Array{Float64}
    average_ltv_requested::Float64
    average_ltv_granted::Float64
    dsti_requested::Array{Float64}
    dsti_granted::Array{Float64}
    average_dsti_requested::Float64
    average_dsti_granted::Float64
end

function MortgageMarket(id)
    return MortgageMarket(id, Dict{Household, Float64}(),Array{Float64, 1}(),Array{Float64, 1}(),0,0,Array{Float64, 1}(),Array{Float64, 1}(),0,0)
end

function agent_step!(mortgage_market::MortgageMarket, model)
    if hasmethod(getfield(Main, Symbol(model.current_step)), (MortgageMarket, AgentBasedModel))
        getfield(Main, Symbol(model.current_step))(mortgage_market, model)
    end
end

function mortgage_market(mortgage_market::MortgageMarket, model)
    # Calculate REAs
    compute_risk_exposure_amounts(model)

    # Prepare
    risk_budget_remaining = Dict{Bank,Float64}()
    liquidity_budget_remaining = Dict{Bank,Float64}()

    active_banks = Dict{Int64, Bank}()
    for (bank_id, bank) in model.banks
        risk_budget = model.alpha * bank.equity - bank.risk_exposure_amount # Eq. (67)
        liquidity_budget = max(0.0, bank.reserves - model.minimum_reserve_requirement * bank.deposits)

        if bank.active_business
            active_banks[bank_id] = bank
            risk_budget_remaining[bank] = risk_budget
            liquidity_budget_remaining[bank] = liquidity_budget
        end
    end

    for (bid, price) in model.housing_market.housing_market_bids
        if bid.ltv > 0.0
            hh = bid.bidder
            bank_mortgage = hh.bank_next_mortgage
            ead = bank_mortgage.risk_weight_mortgages * bid.ltv * price

            if model.disable_credit_rationing || (ead < risk_budget_remaining[bank_mortgage]) #&& price < liquidity_budget_remaining[bank_mortgage])
                risk_budget_remaining[bank_mortgage] -= ead
                liquidity_budget_remaining[bank_mortgage] -= price
            else
                # remove bid if mortgage not granted
                pop!(model.housing_market.housing_market_bids, bid)

                hh.credit_rationed = true

                if bid.as_main_residence
                    # bid on rental market instead
                    desired_expenditure = 0.33*hh.mean_net_income

                    model.housing_market.rental_market_bids[HousingMarketBid(hh, desired_expenditure, true,0.0)] = desired_expenditure
                end
            end
        end
    end
end

function compute_monthly_statistics(mortgage_market::MortgageMarket, model)
    mortgage_market.average_ltv_granted = mean(mortgage_market.ltv_granted)
    mortgage_market.average_ltv_requested = mean(mortgage_market.ltv_requested)

    mortgage_market.average_dsti_granted = mean(mortgage_market.dsti_granted)
    mortgage_market.average_dsti_requested = mean(mortgage_market.dsti_requested)

    mortgage_market.ltv_requested = Array{Float64, 1}()
    mortgage_market.ltv_granted = Array{Float64, 1}()
    mortgage_market.dsti_requested = Array{Float64, 1}()
    mortgage_market.dsti_granted = Array{Float64, 1}()
end

function calculate_annuity(principal, interest_rate, maturity)
    return (1+interest_rate/12)^maturity*interest_rate*principal / (12*((1+interest_rate/12)^maturity-1))
end

function calculate_mortgage_conditions(mortgage_market, model, house_value, max_downpayment, income, as_hmr)
    bank = model.banks[rand(2:num_banks+1)]

    interest_rate = bank.mortgage_interest_rate
    maturity = model.mortgage_duration_months

    if max_downpayment < house_value - 1e-6
        push!(mortgage_market.ltv_requested, 1 - max_downpayment/house_value)
    end

    if model.ltv_cap < 1.0 && model.day > 3000
        max_house_value = max_downpayment * 1/(1-model.ltv_cap)
    else
        max_house_value = house_value
    end

    adjusted_house_value = min(max_house_value, house_value)
    downpayment = min(max_downpayment,adjusted_house_value)

    principal = adjusted_house_value - downpayment

    annuity = calculate_annuity(principal, interest_rate, maturity)

    dsti = annuity/income

    if annuity > 0.0 && as_hmr
        push!(mortgage_market.dsti_requested, annuity/income)
    end

    if model.dsti_cap < 1.0 && model.day > 3000 && as_hmr
        # Recalculate mortgage until dsti below cap
        step = 0.01 * adjusted_house_value
        while dsti > model.dsti_cap
            adjusted_house_value -= step
            principal = adjusted_house_value - downpayment
            if principal > 0.0
                annuity = calculate_annuity(principal, interest_rate, maturity)
                dsti = annuity/income
            else
                annuity = 0
                dsti = 0
            end
        end
    end

    return bank, adjusted_house_value, downpayment, annuity
end

function get_mortgage(mortgage_market::MortgageMarket, model, bank, hh, price_house, ltv)
    push!(mortgage_market.ltv_granted, ltv)

    principal = price_house*ltv

    interest_rate = bank.mortgage_interest_rate
    maturity = model.mortgage_duration_months

    installment = calculate_annuity(principal, interest_rate, maturity)

    outstanding_interest = ((interest_rate/12) * principal * maturity)/(1-(1+interest_rate/12)^(-maturity)) - principal

    no_installments_left = maturity

    mortgage = Mortgage(bank, hh.id, principal, outstanding_interest, installment, no_installments_left, interest_rate, false)

    if (hh.currently_looking_for_main_residence)
        push!(mortgage_market.dsti_granted, installment/hh.mean_net_income)
    end

    pa_bank = hh.bank_payment_account
    hh.payment_account += principal
    pa_bank.deposits += principal
    pa_bank.reserves += principal
    bank.total_mortgages += principal
    bank.reserves -= principal
    bank.number_mortgages+=1
    bank.number_mortgages_new+=1

    model.statistics.flows.total_money_created += principal

    return mortgage
end

function fully_repay_mortgage(mortgage_market::MortgageMarket, model, hh, mortgage)
    bank_mortgage = mortgage.bank

    @assert hh.payment_account > mortgage.outstanding_principal

    hh.payment_account -= mortgage.outstanding_principal
    hh.bank_payment_account.reserves -= mortgage.outstanding_principal
    hh.bank_payment_account.deposits -= mortgage.outstanding_principal
    bank_mortgage.reserves += mortgage.outstanding_principal
    bank_mortgage.total_mortgages -= mortgage.outstanding_principal
    bank_mortgage.number_mortgages -= 1
    bank_mortgage.number_mortgages_repaid += 1

    model.statistics.flows.total_money_destroyed += mortgage.outstanding_principal
end
