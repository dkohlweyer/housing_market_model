using StatsBase

mutable struct GoodsMarket <: AbstractAgent
    id::Int
    total_units_sold_in_month::Float64
    total_revenue_in_month::Float64
    surveys::Dict{Int64,Firm}
end

function GoodsMarket(id)
    return GoodsMarket(id, 0 ,0, Dict{Int64,Firm}())
end

function consumption_goods_market(goods_market::GoodsMarket, model)
    # Reset variables at first day of month
    if model.day_in_month == 1
        goods_market.total_units_sold_in_month = 0
        goods_market.total_revenue_in_month = 0
    end

    for round in 1:2
        firms = Array{Firm, 1}()
        exps = Array{Float64, 1}()
        probs = Array{Float64, 1}()
        rationing_factors = Dict{Int64, Float64}()
        total_demand = Dict{Int64, Float64}()

        households = Dict{Int64, Household}()

        # Prepare logit choice
        sum_exps = 0.0
        for (id, firm) in model.active_firms
            if firm.inventory > 0
                push!(firms, firm)
                expvalue = exp(-model.gamma_consumption*log(firm.price))
                push!(exps, expvalue)
                sum_exps += expvalue
                total_demand[id] = 0
            end
        end

        if length(firms) > 0
            probs = map((x)->x/sum_exps, exps) # Eq. (81)

            for (id, hh) in model.households
                if (hh.consumption_day == model.day_in_week && hh.consumption_budget_week > 0)
                    households[id] = hh
                    firm = sample(firms, Weights(probs))
                    hh.selected_supplier_id = firm.id
                    total_demand[firm.id] += hh.consumption_budget_week / firm.price
                end
            end

            for firm in firms
                rationing_factors[firm.id] = min(1.0,(firm.inventory / total_demand[firm.id]))
            end

            for (id, hh) in households
                firm = model[hh.selected_supplier_id]

                delivered = hh.consumption_budget_week / firm.price * rationing_factors[hh.selected_supplier_id]

                model.statistics.flows.total_consumption += delivered

                firm.inventory -= delivered

                bank_transfer!(hh, firm, delivered * firm.price, note="goods")
                firm.revenue += delivered * firm.price

                hh.consumption_budget_week -= delivered * firm.price
                hh.consumption_budget -= delivered * firm.price

                goods_market.total_revenue_in_month += delivered * firm.price
                goods_market.total_units_sold_in_month += delivered
            end
        end
    end
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
