mutable struct FinancialMarket <: AbstractAgent
    id::Int
    payment_account::Float64
    bank_payment_account::Bank
    price::Float64
    total_no_shares::Float64
    demand_shares::Dict{Household, Float64}
    supply_shares::Dict{Household, Float64}
    total_dividends::Float64
end

function FinancialMarket(id)
    return FinancialMarket(id, 0, Bank(0), 0, 0, Dict{Household, Int64}(), Dict{Household, Int64}(), 0)
end

function financial_market(fin_market::FinancialMarket, model)
    total_demand = 0
    total_supply = 0
    for (hh, x) in fin_market.demand_shares # Eq. (92)
        total_demand += x
    end

    for (hh, x) in fin_market.supply_shares # Eq. (93)
        total_supply += x
    end

    if total_supply > 0 && total_demand > 0
        if total_demand > total_supply # Eq. (94)
            factor_demand = total_supply / total_demand
            factor_supply = 1
        end

        if total_supply > total_demand # Eq. (95)
            factor_supply = total_demand / total_supply
            factor_demand = 1
        end

        shares = 0
        for (hh, demand) in fin_market.demand_shares
            demand_realized = factor_demand * demand
            hh.shares_index_fund += demand_realized

            @assert hh.shares_index_fund > -1e-6

            shares -= demand_realized

            bank_transfer!(hh, fin_market, demand_realized * fin_market.price, note="shares bought")
        end

        for (hh, supply) in fin_market.supply_shares

            supply_realized = factor_supply * supply
            hh.shares_index_fund -= supply_realized

            @assert hh.shares_index_fund > -1e-6

            shares += supply_realized

            bank_transfer!(fin_market, hh, supply_realized * fin_market.price, note="shares sold")
        end

        @assert shares > -1e-6 && shares < 1e-6

        # New price
        theta = (total_demand / total_supply) ^ model.index_price_adjustment_speed # Eq. (88)
        fin_market.price = fin_market.price * min(1+model.index_price_adjustment_lower_bound, max(1-model.index_price_adjustment_lower_bound, theta)) # Eq. (89)
    end

    @assert fin_market.payment_account > -1e-6

    # Reset
    fin_market.demand_shares = Dict{Household, Float64}()
    fin_market.supply_shares = Dict{Household, Float64}()
end

function distribute_dividends(fin_market::FinancialMarket, model)
    if !model.disable_shares
        distribute_dividends_based_on_shares(fin_market, model)
    else
        distribute_dividends_based_on_payment_account(fin_market, model)
    end
end

function distribute_dividends_based_on_shares(fin_market::FinancialMarket, model)
    for (hh_id, hh) in model.households
        dividend_payment = hh.shares_index_fund / fin_market.total_no_shares * fin_market.total_dividends

        hh.dividend_income += dividend_payment

        bank_transfer!(fin_market, hh, dividend_payment, note="dividends ($(hh.shares_index_fund)/$(fin_market.total_no_shares)*$(fin_market.total_dividends)=$dividend_payment)")
    end

    fin_market.total_dividends = 0

    @assert fin_market.payment_account > -1e-3 && fin_market.payment_account < 1e-3
end

function distribute_dividends_based_on_payment_account(fin_market::FinancialMarket, model)
    total_wealth = 0.0

    for (hh_id, hh) in model.households
        total_wealth += hh.payment_account

        @assert hh.payment_account > -1e-6
    end

    if fin_market.total_dividends > 0.0
        for (hh_id, hh) in model.households
            dividend_payment = hh.payment_account / total_wealth * fin_market.total_dividends

            hh.dividend_income += dividend_payment

            bank_transfer!(fin_market, hh, dividend_payment, note="dividends ($(hh.shares_index_fund)/$(fin_market.total_no_shares)*$(fin_market.total_dividends)=$dividend_payment)")
        end
    end

    fin_market.total_dividends = 0

    @assert fin_market.payment_account > -1e-3 && fin_market.payment_account < 1e-3
end

function end_of_day(fin_market::FinancialMarket, model)
    model.statistics.stocks.total_money += fin_market.payment_account
end
