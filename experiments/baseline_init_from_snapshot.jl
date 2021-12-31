using CSV, Serialization

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
    model = open(snapshot_file,"r") do snapshot_file
        deserialize(snapshot_file)
    end

    for (prop, value) in properties
        model.properties[prop] = value
    end

    return model
end
