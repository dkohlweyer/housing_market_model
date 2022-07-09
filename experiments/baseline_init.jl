using CSV

# Number of agents
num_households = 1600 * 3.125
num_firms = 80 * 3.125
num_banks = 1

# Baseline properties
baseline_properties = Dict(
:policy_dyn_ltv_cap => false,
:disable_btl_trading => false,
:disable_hpi_growth_objective => false,
:disable_shares => true,
:disable_housing => false,
:disable_regression => false,
:disable_adaptive_tax_rate => true,
:disable_minimum_consumption => false,
:disable_taylor_rule => false,
:disable_endegenous_mortgage_interest_rate => false,
:disable_credit_rationing => false,
:disable_long_term_saving => true,
:disable_sticky_consumption => true,
:households => Dict{Int64,Household},
:active_firms => Dict{Int64,Firm},
:inactive_firms => Dict{Int64,Firm},
:banks => Dict{Int64,Bank},
:commercial_banks => Dict{Int64,Bank},
:goods_market => GoodsMarket,
:labor_market => LaborMarket,
:financial_market => FinancialMarket,
:credit_market => CreditMarket,
:housing_market => HousingMarket,
:mortgage_market => MortgageMarket,
:statistics => StatisticsAgent,
:government => Government,
:capital_goods_producer => CapitalGoodsProducer,
:current_step => "beginning_of_day",
:day => 1,
:day_in_week => 1,
:day_in_month => 1,
:day_in_year => 1,
:quantile_production_planning => 0.75,
:depreciation_rate => 0.01,
:discount_rate => 0.02,
:wage_update => 0.01,
:reservation_wage_update => 0.01,
:min_vacancies_wage_update => 3,
:general_skill_groups => [1,2,3,4,5],
:skill_update_formula => x -> 1-0.5^(1/(20+0.25*(x-1)*(4-20))),
:fraction_random_layoffs_l => 0.0,
:fraction_random_layoffs_u => 0.1,
:applications_per_month => 5,
:applications_per_day => 3,
:gamma_general_skills => 0.5,
:carrol_consumption_parameter => 0.0025,
:carrol_consumption_parameter_long_term => 0.001,
:target_wealth_income_ratio => 16.67,
:gamma_consumption => 18,
:gamma_vintage => 30,
:market_size_estimation_horizon => 12,
:firm_planning_horizon_months => 12,
:market_research_start_price => 0.8,
:market_research_end_price => 1.2,
:market_research_increment => 0.01,
:market_research_no_questionaires => 300,
:dividend_earnings_ratio => 0.7,
:firm_dividend_threshold_full_payout => 1.0,
:tax_rate => 0.05,
:unemployment_replacement_rate => 0.5,
:innovation_probability => 0.05,
:innovation_progress => 0.025,
:innovation_transient => 3000,
:innovation_predetermined_frontier => [280,880,1860,2200,2740,3240,4140,4640,5040,5660,6620,6960,7500,8000,8900,9400,9800,10420,11380,12260,13660,14160,14280,14880,15860,16200,16740,17240,18140,18640,19040,19660,20620,20960,21500,22000,22900,23400,23800,24420,25380,26260,27660,28160,28280,28880,29860,30200,30740,31240,32140,32640,33040,33660,34620,34960,35500,36000,36900,37400,37800,38420,39380,40260,41660,42160,42280,42880,43860,44200,44740,45240,46140,46640,47040,47660,48620,48960,49500,50000,50900,51400,51800,52420,53380,54260,55660,56160,56280,56880,57860,58200,58740,59240,60140,60640,61040,61660,62620,62960,63500,64000,64900,65400,65800,66420,67380,68260,69660,70160,70280,70880,71860,72200,72740,73240,74140,74640,75040,75660,76620,76960,77500,78000,78900,79400,79800,80420,81380,82260,83660,84160,84280,84880,85860,86200,86740,87240,88140,88640,89040,89660,90620,90960,91500,92000,92900,93400,93800,94420,95380,96260,97660,98160,98280,98880,99860,100200,100740,101240,102140,102640,103040,103660,104620,104960,105500,106000,106900,107400,107800,108420,109380,110260,111660,112160,112280,112880,113860,114200,114740,115240,116140,116640,117040,117660,118620,118960,119500,120000,120900,121400,121800,122420,123380,124260,125660,126160,126280],
:lambda_vintage_pricing => 0.5,
:firm_credit_number_banks_to_approach => 1,
:lambda_bank => 3.0,
:central_bank_rate => 0.01,
:central_bank_rate_markdown => 0.75,
:excess_reserves_markdown => 0.2,
:mortgage_interest_rate => 0.025,
:mortgage_profit_rate => 0.01,
:debt_rescaling_factor => 0.3,
:alpha => 10.0,
:minimum_reserve_requirement => 0.1,
:index_price_adjustment_speed => 1.0,
:index_price_adjustment_lower_bound => 0.1,
:index_price_adjustment_upper_bound => 0.1,
:investment_inertia => 10,
:financial_planning_buffer => 0.04,
:firm_credit_period => 18,
:ltv_cap => 1.0,
:dsti_cap => 1.0,
:months_negative_credit_score_after_default => 24,
:mortgage_risk_weight_lookup => nothing,
:firm_loan_risk_weight_lookup => nothing,
:markdown_bank_selling => 0.25,
:housing_market_alpha => 4.5,
:housing_market_beta => 0.08,
:housing_market_fraction_downpayment => 0.5,
:housing_market_prob_price_adjustment => 0.06,
:housing_market_bid_up => 0.0075,
:psycological_cost_renting => 0.0,
:mortgage_duration_months => 300,
:gamma_hmr => 5,
:gamma_btl => 10,
:lambda_btl =>0.9,
:shift_sigmoid_capital_gain_objective => 0.2,
:shift_sigmoid_rental_yield_objective => 1.0,
:rental_market_price_adjustment => 0.05,
:probability_selling_hmr => 1/12/11
)

# Function to set up the initial state of the model
function initialize(properties, num_households, num_firms, num_banks)
    model = ABM(Union{Household, Firm, Bank, GoodsMarket, LaborMarket, CreditMarket, StatisticsAgent, Government, CapitalGoodsProducer, FinancialMarket, HousingMarket, MortgageMarket}, properties = properties, warn = false)

    # Load risk weights
    model.mortgage_risk_weight_lookup = CSV.File("model/lookuptable_risk_weights_mortgage_loans_w_rowLGD_colPD.csv", header=false)
    model.firm_loan_risk_weight_lookup = CSV.File("model/lookuptable_risk_weights_firm_loans_w_rowLGD_colPD.csv", header=false)

    id = 0

    init_specific_skills = 1.5
    init_base_wage = 1.0
    init_wage = init_base_wage * init_specific_skills
    init_no_shares = 81
    init_share_price = 0.123456790123#10 * init_wage / init_no_shares

    init_production_per_firm = 28.568582#init_specific_skills * num_households / num_firms
    init_price = 1.2 # Set after first production in C version (due to markup)

    vintage_price_init = 20
    init_vintage_id = 6
    init_vintage_amount = 19.0

    id+=1
    statistics = StatisticsAgent(id)
    add_agent!(statistics, model)
    model.statistics = statistics
    model.statistics.average_skill = init_specific_skills
    model.statistics.average_general_skill_group = 2.5
    model.statistics.average_wage = init_wage
    model.statistics.consumer_price_index = init_price
    model.statistics.market_size = 2280.0 #init_production_per_firm * num_firms
    model.statistics.market_size_history = [2218.2304,2223.775976,2229.335416,2234.908754,2240.496026,2246.097266,2251.712509,2257.341791,2262.985145,2268.642608,2274.314214,2280]
    data = DataFrame(month=Array(1:length(model.statistics.market_size_history)), market_size=model.statistics.market_size_history)
    ols = lm(@formula(market_size~month), data)
    model.statistics.market_size_estimation_intercept = coef(ols)[1]
    model.statistics.market_size_estimation_coefficient = coef(ols)[2]
    model.statistics.market_size_estimation_mean_squared_error = deviance(ols)/(length(model.statistics.market_size_history)-1)
    model.statistics.market_size_estimation_variance = var(model.statistics.market_size_history)

    model.banks = Dict{Int64,Bank}()
    model.commercial_banks = Dict{Int64,Bank}()

    for _ in 1:num_banks
        id+=1
        bank = Bank(id)
        bank.activation_day = rand(1:20)
        bank.active_business = true
        add_agent!(bank, model)
        model.banks[id] = bank
        model.commercial_banks[id] = bank

        push!(bank.number_loans_in_month_history, 0)
        push!(bank.number_mortgages_in_month_history, 0)
    end

    # Special bank for payment account of government
    id+=1
    state_bank = Bank(id)
    state_bank.activation_day = rand(1:20)
    state_bank.is_state_bank = true
    state_bank.active_business = false
    model.banks[id] = state_bank
    add_agent!(state_bank, model)

    model.households = Dict{Int64,Household}()

    for _ in 1:num_households
        id+=1
        hh = Household(id)
        hh.bank_payment_account = model.banks[rand(2:num_banks+1)]
        hh.employer_id = -1
        hh.specific_skills = init_specific_skills
        hh.general_skill_group = sample([1,2,3,4,5], Weights([0.1, 0.3, 0.4, 0.15, 0.05]))
        hh.payday = rand(1:20)
        hh.wage = init_wage
        hh.mean_net_income = init_wage
        hh.reservation_wage = init_wage
        hh.payment_account = 15
        model.statistics.stocks_prev.total_money += hh.payment_account
        hh.bank_payment_account.deposits += hh.payment_account
        hh.shares_index_fund = init_no_shares

        add_agent!(hh, model)
        model.households[id] = hh
    end

    model.active_firms = Dict{Int64,Firm}()
    model.inactive_firms = Dict{Int64,Firm}()

    for _ in 1:num_firms
        id+=1
        firm = Firm(id)
        firm.active = true
        firm.bank_payment_account = model.banks[rand(2:num_banks+1)]

        firm.activation_day = rand(1:20)
        firm.vintages[init_vintage_id] = init_vintage_amount
        firm.average_technology = 1.5
        firm.productivity = min(init_specific_skills, firm.average_technology)
        firm.total_value_capital = vintage_price_init * firm.vintages[init_vintage_id]
        firm.payment_account = firm.total_value_capital
        model.statistics.stocks_prev.total_money += firm.payment_account
        firm.bank_payment_account.deposits += firm.total_value_capital

        for g in 1:5
            firm.wage_offer[g] = 1.5
        end

        firm.vintage_choice = 6
        firm.last_production = 28.5
        firm.base_wage = init_base_wage
        firm.price = init_price
        firm.inventory = 0
        firm.next_market_research_day = rand(21:model.firm_planning_horizon_months*20+20)
        firm.estimated_demand_schedule = fill(init_production_per_firm,13)
        firm.estimated_demand_schedule_pos = 1
        firm.estimated_demand_variance = 0

        total_assets = firm.total_value_capital + firm.payment_account
        bank_loan = model.banks[rand(2:num_banks+1)]
        init_loan = Loan(bank_loan, 2/3*total_assets, 2/3*total_assets/model.firm_credit_period, model.firm_credit_period, 0.04, false, 0.0003)
        firm.total_debt = 2/3*total_assets
        firm.loans[init_loan] = bank_loan

        firm.last_loan_interest_rate = 0.0
        bank_loan.total_loans += 2/3*total_assets
        bank_loan.number_loans += 1

        firm.equity = 1/3 * total_assets

        firm.investment = 0.211111111111*model.firm_credit_period
        firm.investment_history = CircularBuffer{Float64}(model.firm_credit_period)
        for _ in 1:18
            push!(firm.investment_history, firm.investment)
        end

        add_agent!(firm, model)
        model.active_firms[id] = firm
    end

    id+=1
    goods_market = GoodsMarket(id)
    add_agent!(goods_market, model)
    model.goods_market = goods_market

    id+=1
    labor_market = LaborMarket(id)
    add_agent!(labor_market, model)
    model.labor_market = labor_market

    id+=1
    credit_market = CreditMarket(id)
    add_agent!(credit_market, model)
    model.credit_market = credit_market

    id+=1
    fin_market = FinancialMarket(id)
    fin_market.price = init_share_price
    fin_market.bank_payment_account = state_bank
    fin_market.total_no_shares = num_households * init_no_shares
    add_agent!(fin_market, model)
    model.financial_market = fin_market

    id+=1
    government = Government(id)
    government.tax_rate = model.tax_rate
    government.bank_payment_account = state_bank
    add_agent!(government, model)
    model.government = government

    id+=1
    producer = CapitalGoodsProducer(id)
    producer.bank_payment_account = model.banks[rand(2:num_banks+1)]
    add_agent!(producer, model)
    model.capital_goods_producer = producer
    model.capital_goods_producer.vintage_productivities = Dict(1 => 1.0, 2 => 1.1, 3 => 1.2, 4 => 1.3, 5 => 1.4, 6 => 1.5, 7 => 1.6, 8 => 1.7)
    model.capital_goods_producer.vintage_prices = Dict(1 => vintage_price_init, 2 => vintage_price_init, 3 => vintage_price_init, 4 => vintage_price_init, 5 => vintage_price_init, 6 => vintage_price_init, 7 => vintage_price_init, 8 => vintage_price_init)
    model.capital_goods_producer.cost_based_price = vintage_price_init
    model.capital_goods_producer.best_available_vintage = 8

    for (id, bank) in model.banks
        #bank.equity = 0.75 / (1-0.75) * bank.deposits
        bank.equity = (1-exp(-2))*(bank.total_loans+bank.total_mortgages) / (0.5 * model.alpha)
        #bank.equity = 2 * (1-exp(-2))*(bank.total_loans+bank.total_mortgages) / (0.5 * model.alpha)
        model.statistics.stocks_prev.total_money += bank.equity
        bank.reserves = bank.deposits + bank.equity - (bank.total_loans+bank.total_mortgages)

        diff_to_min_reserves = bank.reserves - model.minimum_reserve_requirement * bank.deposits
        if diff_to_min_reserves < 0
            bank.reserves += -diff_to_min_reserves
            bank.central_bank_debt += -diff_to_min_reserves
        end

        model.statistics.stocks_prev.total_reserves += bank.reserves
    end

    # Housing Market Extension
    id+=1
    housing_market = HousingMarket(id)
    add_agent!(housing_market, model)
    model.housing_market = housing_market

    model.housing_market.rental_market_transactions = Dict(0.25 => HousingMarketTransaction(0.25,0.1,1), 0.5 => HousingMarketTransaction(0.5,0.2,1), 0.75 => HousingMarketTransaction(0.75,0.3,1), 1 => HousingMarketTransaction(1,0.4,1))
    model.housing_market.housing_market_transactions = Dict(0.25 => HousingMarketTransaction(0.25,120,1), 0.5 => HousingMarketTransaction(0.5,160,1), 0.75 => HousingMarketTransaction(0.75,250,1), 1 => HousingMarketTransaction(1,400,1))

    BINS = 10
    for i in 1:BINS
        q = i * (1/BINS) - 1/(2*BINS)

        model.housing_market.housing_market_binned_average_prices[q] = 372 * q
        model.housing_market.rental_market_binned_average_prices[q] = 0.5 * q
    end

    id+=1
    mortgage_market = MortgageMarket(id)
    add_agent!(mortgage_market, model)
    model.mortgage_market = mortgage_market

    house_counter = 0
    hh_counter = 0
    if true

        for (id, hh) in model.households
            hh_counter+=1

            if hh_counter <= num_households / 2 # 50% Owner
                hh.main_residence = House(house_counter+=1,rand(), nothing, nothing, false, false, -1, 0)
            end

            if hh_counter <= num_households / 4 # 25% BTL
                hh.btl_gene = 1
               for _ in 1:2
                    h_id = house_counter+=1
                    house = House(h_id, rand(), nothing, nothing, false, false, -1, 0)

                    hh.other_properties[h_id] = house
                end
            else

            end
        end

        model.statistics.stocks_prev.total_number_houses = house_counter
    end

    return model
end
