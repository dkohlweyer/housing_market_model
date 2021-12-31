mutable struct Government <: AbstractAgent
    id::Int
    payment_account::Float64
    bank_payment_account::Bank
    tax_rate::Float64
    income::Float64
    expenses::Float64
    tax_base::Float64
    income_in_month::Float64
    expenses_in_month::Float64
    tax_base_in_month::Float64
end

function Government(id)
    return Government(id, 0, Bank(0),0,0,0,0,0,0,0)
end

function agent_step!(gov::Government, model)
    if hasmethod(getfield(Main, Symbol(model.current_step)), (Government, AgentBasedModel))
        getfield(Main, Symbol(model.current_step))(gov, model)
    end
end

function gov_expense!(gov::Government, hh, amount)
    bank_transfer!(gov, hh, amount, note="gov expense")

    gov.expenses += amount
end

function pay_taxes!(gov::Government, hh, tax_base)
    tax = max(0.0, gov.tax_rate * tax_base)

    bank_transfer!(hh, gov, tax, note="taxes")

    gov.income += tax
    gov.tax_base += max(0.0, tax_base)

    return tax
end

function monthly_settlement(gov::Government, model)
    # adjust tax rate
    if !model.disable_adaptive_tax_rate && gov.tax_base > 0.0
        tax_rate_balancing = max(0.0, gov.expenses - 1/60.0  * gov.payment_account) / gov.tax_base

        gov.tax_rate = (1-0.025) * gov.tax_rate + 0.025 * tax_rate_balancing
    else
        gov.tax_rate = model.tax_rate
    end

    gov.income_in_month = gov.income
    gov.expenses_in_month = gov.expenses
    gov.tax_base_in_month = gov.tax_base

    gov.income = 0
    gov.expenses = 0
    gov.tax_base = 0
end

function end_of_day(gov::Government, model)
    model.statistics.stocks.total_money += gov.payment_account
end
