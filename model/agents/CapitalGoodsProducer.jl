mutable struct CapitalGoodsProducer <: AbstractAgent
    id::Int
    payment_account::Float64
    bank_payment_account::Bank
    vintage_productivities::Dict{Int64, Float64}
    vintage_prices::Dict{Int64, Float64}
    best_available_vintage::Int
    cost_based_price::Float64
    interest_income::Float64
    revenue::Float64
    revenue_history::CircularBuffer{Float64}
    profit::Float64
    profit_history::CircularBuffer{Float64}
end

function CapitalGoodsProducer(id)
    return CapitalGoodsProducer(id, 0, Bank(0), Dict{Int64, Float64}(),Dict{Int64, Float64}(),0,0,0, 0,CircularBuffer{Float64}(6),0,CircularBuffer{Float64}(24))
end

function collect_interest(producer::CapitalGoodsProducer, model)
    interest = (1-model.central_bank_rate_markdown) * model.central_bank_rate / 240 * producer.payment_account

    producer.payment_account += interest
    producer.interest_income += interest
    producer.bank_payment_account.equity -= interest
    producer.bank_payment_account.deposits += interest
    producer.bank_payment_account.interest_expense_deposits += interest
end

function innovation_process(producer::CapitalGoodsProducer, model)
    if (model.innovation_predetermined_frontier == nothing && model.day > model.innovation_transient && model.day_in_month == 1 && rand() < model.innovation_probability) || (model.innovation_predetermined_frontier != nothing && (model.day-model.innovation_transient) in model.innovation_predetermined_frontier)
        # Develop a new vintage
        producer.vintage_productivities[producer.best_available_vintage+1] = producer.vintage_productivities[producer.best_available_vintage] * (1 + model.innovation_progress) # Eq. (74)
        producer.best_available_vintage += 1

        recalculate_prices(producer, model)
    end
end

function update_prices(producer::CapitalGoodsProducer, model)
    # update cost based price
    producer.cost_based_price = (1+model.statistics.average_productivity_monthly_growth) * producer.cost_based_price # Eq. (75)

    recalculate_prices(producer, model)
end

function recalculate_prices(producer::CapitalGoodsProducer, model)
    # calculate effective productivity of lowest vintage
    future_productivity_lowest_vintage = calculate_estimated_future_productivity(model, producer.vintage_productivities[1], model.statistics.average_skill, model.statistics.average_general_skill_group) # Eq. (76)

    # calculate price of all vintages
    for (v, productivity) in producer.vintage_productivities

        future_productivity = calculate_estimated_future_productivity(model, productivity, model.statistics.average_skill, model.statistics.average_general_skill_group) # Eq. (76)

        value_based_price = producer.vintage_prices[1] * future_productivity / future_productivity_lowest_vintage # Eq. (77)

        producer.vintage_prices[v] = (1-model.lambda_vintage_pricing) * producer.cost_based_price + model.lambda_vintage_pricing * value_based_price # Eq. (78)
    end
end

function calculate_estimated_future_productivity(model, vintage_producitivity, average_skill, average_skill_group)
    discounted_sum = 0
    for t in 1:24
        discounted_sum += (1/(1+model.discount_rate))^t * min(vintage_producitivity, average_skill) # Eq. (12)

        average_skill = average_skill + model.skill_update_formula(average_skill_group) * max(0, vintage_producitivity - average_skill) # Eq. (13)
    end

    return discounted_sum
end

function monthly_settlement(producer::CapitalGoodsProducer, model)
    gross_profit = producer.revenue + producer.interest_income

    # Pay taxes
    tax = pay_taxes!(model.government, producer, gross_profit)

    producer.profit = gross_profit - tax

    push!(producer.revenue_history, producer.revenue)
    push!(producer.profit_history, producer.profit)

    # Dividend payment
    average_revenue = Statistics.mean(convert(Vector{Float64}, producer.revenue_history))
    average_profit = Statistics.mean(convert(Vector{Float64}, producer.profit_history))

    dividends = max(0.0, average_profit)

    if dividends > 0.0
        bank_transfer!(producer, model.financial_market, dividends)
        model.financial_market.total_dividends += dividends
    end

    @model_log producer "monthly_settlement" "revenue" producer.revenue
    @model_log producer "monthly_settlement" "interest_income" producer.interest_income
    @model_log producer "monthly_settlement" "gross_profit" gross_profit
    @model_log producer "monthly_settlement" "average_profit" average_profit
    @model_log producer "monthly_settlement" "tax" tax
    @model_log producer "monthly_settlement" "dividends" dividends

    # reset variables
    producer.revenue = 0
    producer.interest_income = 0
end

function end_of_day(producer::CapitalGoodsProducer, model)
    model.statistics.stocks.total_money += producer.payment_account
end
