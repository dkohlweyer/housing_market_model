mutable struct CreditMarket <: AbstractAgent
    id::Int
    average_pd_applications::Float64
    average_interest_rate_offers::Float64
    average_interest_rate_new_loans::Float64
end

mutable struct Loan
    bank::Bank
    principal::Float64
    installment::Float64
    no_installments_left::Int64
    interest_rate::Float64
    repayment_started::Bool
    probability_default::Float64
end

function CreditMarket(id)
    return CreditMarket(id, 0,0,0)
end

function agent_step!(credit_market::CreditMarket, model)
    if hasmethod(getfield(Main, Symbol(model.current_step)), (CreditMarket, AgentBasedModel))
        getfield(Main, Symbol(model.current_step))(credit_market, model)
    end
end

function credit_market(credit_market::CreditMarket, model)
    total_demand_credit = 0.0
    total_demand_risk = 0.0
    total_budget_credit = 0.0
    total_budget_risk = 0.0

    # Calculate REAs
    compute_risk_exposure_amounts(model)

    # Prepare
    risk_budget_remaining = Dict{Bank,Float64}()
    liquidity_budget_remaining = Dict{Bank,Float64}()

    applications = Dict{Bank, Dict{Firm,Float64}}() # {Bank,{Firm, EAD}}
    offers = Dict{Firm, Dict{Loan,Float64}}() # {Firm, {Loan, i}}

    active_banks = Dict{Int64, Bank}()
    for (bank_id, bank) in model.banks
        risk_budget = model.alpha * bank.equity - bank.risk_exposure_amount # Eq. (67)
        liquidity_budget = max(0.0, bank.reserves - model.minimum_reserve_requirement * bank.deposits)

        if bank.active_business
            active_banks[bank_id] = bank
            applications[bank] = Dict{Int64, Firm}()
            risk_budget_remaining[bank] = risk_budget
            liquidity_budget_remaining[bank] = liquidity_budget

            total_budget_risk+=risk_budget_remaining[bank]
            total_budget_credit+=liquidity_budget_remaining[bank]
        end


    end

    if length(active_banks)>0
        sum_i_offers = 0.0
        n_offers = 0
        sum_i_new_loans = 0.0
        n_new_loans = 0
        sum_pd = 0.0
        n_pd = 0

        # Firms apply at banks with EAD
        for (firm_id, firm) in model.active_firms
            if firm.activation_day == model.day_in_month && firm.credit_demand > 0
                offers[firm] = Dict{Bank,Float64}()

                for bank_id in shuffle(collect(keys(active_banks)))[1:min(model.firm_credit_number_banks_to_approach, length(active_banks))]
                    pd = max(0.0003, 1-exp(-0.1*(firm.total_debt+firm.credit_demand)/firm.equity)) # Eq. (62)
                    ead = pd * firm.credit_demand # Eq. (63)

                    sum_pd += pd
                    n_pd += 1

                    applications[active_banks[bank_id]][firm] = ead
                end
            end
        end

        # Banks send out offers
        for (bank_id, bank) in active_banks
            for (firm, ead) in sort(collect(applications[bank]), by=x->x[2])
                pd = max(0.0003, 1-exp(-0.1*(firm.total_debt+firm.credit_demand)/firm.equity)) # Eq. (62)
                i = model.central_bank_rate * (1 + model.lambda_bank*pd + rand()) # Eq. (65)

                ead_reg = bank.risk_weight_firm_loans * firm.credit_demand

                if model.disable_credit_rationing || true # liquidity_budget_remaining[bank] > 0.01 * firm.credit_demand
                    if model.disable_credit_rationing || ead_reg < risk_budget_remaining[bank] # Eq. (68)
                        amount_offered = firm.credit_demand

                        loan = Loan(bank, amount_offered, amount_offered/model.firm_credit_period, model.firm_credit_period, i, false, pd)
                        offers[firm][loan] = i

                        sum_i_offers += i
                        n_offers += 1

                        @assert loan.principal > -0.0001

                        risk_budget_remaining[bank] -= ead_reg
                        liquidity_budget_remaining[bank] -= amount_offered
                    else
                        @model_log "credit_market" "risk_budget_reached" bank_id
                    end
                else
                    @model_log "credit_market" "liquidity_budget_reached" bank_id
                end
            end
        end

        # Firms select best offer(s)
        for (firm, firm_offers) in offers
            while firm.credit_demand > 0 && length(firm_offers) > 0
                # Find best offer
                min_i = 9999999.9
                best_loan_offer = nothing
                for (loan, i) in firm_offers
                    if loan.interest_rate < min_i
                        min_i = loan.interest_rate
                        best_loan_offer = loan
                    end
                end

                sum_i_new_loans += min_i
                n_new_loans+= 1

                bank = best_loan_offer.bank
                pa_bank = firm.bank_payment_account

                principal = min(firm.credit_demand, best_loan_offer.principal)
                best_loan_offer.principal = principal
                best_loan_offer.installment = principal / model.firm_credit_period
                firm.credit_demand -= principal

                firm.payment_account += principal
                firm.total_debt +=  principal
                pa_bank.deposits += principal
                pa_bank.reserves += principal
                bank.total_loans += principal
                bank.reserves -= principal
                bank.number_loans_new += 1

                firm.credit_raised += principal

                model.statistics.flows.total_money_created += principal

                firm.loans[best_loan_offer] = bank

                @assert best_loan_offer.principal > -1e-6
                @assert best_loan_offer.installment > -1e-6

                firm.last_loan_interest_rate = best_loan_offer.interest_rate

                delete!(firm_offers, best_loan_offer)
            end
        end

        if n_pd > 0
            credit_market.average_pd_applications = sum_pd / n_pd
        end

        if n_offers > 0
            credit_market.average_interest_rate_offers = sum_i_offers / n_offers
        end

        if n_new_loans > 0
            credit_market.average_interest_rate_new_loans = sum_i_new_loans / n_new_loans
        end
    end
end

function compute_risk_exposure_amounts(model) # Eq. (64)
    for (bank_id, bank) in model.banks
        bank.risk_exposure_amount = 0.0
    end

    for (bank_id, bank) in model.commercial_banks
        bank.risk_exposure_amount += bank.risk_weight_firm_loans * bank.total_loans
        bank.risk_exposure_amount += bank.risk_weight_mortgages * bank.total_mortgages
    end
end
