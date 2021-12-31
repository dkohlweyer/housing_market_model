using Agents

mutable struct LaborMarket <: AbstractAgent
    id::Int
    job_seekers::Dict{Int64,Household}
    job_postings::Dict{Int64,Firm}
end

function LaborMarket(id)
    return LaborMarket(id ,Dict{Int64,Household}(), Dict{Int64,Firm}())
end

function labor_market(labor_market::LaborMarket, model)
    # Prepare list of job-seeking households
    prob_search = model.applications_per_month/(model.applications_per_day*20) # Eq. (19)

    for (id, hh) in model.households
        if hh.employer_id == -1 && rand() < prob_search
            # Register as job-seeking
            model.labor_market.job_seekers[hh.id] = hh
        end
    end

    # 2 rounds
    for round in 1:2
        applications = Dict{Firm, Dict{Int64,Household}}()
        offers = Dict{Household, Dict{Int64,Firm}}()

        # Prepare
        for (id, firm) in labor_market.job_postings
            applications[firm] = Dict{Int64, Household}()
        end
        for (id, hh) in labor_market.job_seekers
            offers[hh] = Dict{Int64,Firm}()
        end

        # Households apply at firms
        for (hh_id, hh) in labor_market.job_seekers
            num_applications = 0

            for firm_id in shuffle(collect(keys(labor_market.job_postings)))
                firm = labor_market.job_postings[firm_id]

                if firm.wage_offer[hh.general_skill_group] >= hh.reservation_wage # Eq. (20)
                    num_applications += 1
                    applications[firm][hh_id] = hh
                end

                if num_applications == model.applications_per_day
                    break
                end
            end
        end

        # Firms review applications and send offers
        for (firm_id, firm) in labor_market.job_postings

            if length(applications[firm]) > 0
                applicants = Array{Household, 1}()
                exps = Array{Float64, 1}()
                probs = Array{Float64, 1}()

                sum_exps = 0.0

                for (hh_id, hh) in applications[firm] # Eq. (18)
                    push!(applicants, hh)
                    expvalue = exp(model.gamma_general_skills*log(hh.general_skill_group))
                    push!(exps, expvalue)
                    sum_exps += expvalue
                end

                probs = map((x)->x/sum_exps, exps)

                num_offers = min(firm.vacancies, length(applications[firm]))

                for hh in sample(applicants, Weights(probs), num_offers, replace=false)
                    offers[hh][firm_id] = firm
                end
            end
        end

        # Households select offer
        for (hh_id, hh) in labor_market.job_seekers
            if length(offers[hh]) > 0
                best_firm_id = -1
                best_wage_offer = -1

                # Households select best offer
                for (firm_id, firm) in offers[hh]
                    if firm.wage_offer[hh.general_skill_group] > best_wage_offer
                        best_firm_id = firm_id
                        best_wage_offer = firm.wage_offer[hh.general_skill_group]
                    end
                end

                # Match
                firm = labor_market.job_postings[best_firm_id]

                @assert hh.employer_id == -1

                hh.employer_id = best_firm_id
                delete!(labor_market.job_seekers, hh.id)
                firm.employees[hh.id] = hh

                # partially repay unemployment benefits for current month
                if model.day > hh.unemployed_since
                    if model.day_in_month != hh.payday
                        days_unemployed_this_month = mod(model.day_in_month - hh.payday, 20)
                        repay = model.unemployment_replacement_rate * hh.wage * (20 - days_unemployed_this_month) / 20

                        bank_transfer!(hh, model.government, repay, note="gov repay")
                    end
                end

                hh.wage = best_wage_offer
                hh.payday = model.day_in_month

                firm.vacancies -= 1
                if firm.vacancies == 0
                    delete!(labor_market.job_postings, firm.id)
                end
            else
                # No offers -> update reservation wage
                hh.wage = max(hh.social_benefits, hh.wage - model.reservation_wage_update * hh.wage) # Eq. (22)
            end
        end

        if round==1
            # Update wage offer if vacancies to high
            for (id, firm) in labor_market.job_postings
                if firm.vacancies >= model.min_vacancies_wage_update
                    firm.base_wage = (1+model.wage_update) * firm.base_wage # Eq. (16)

                    calculate_wage_offers(firm, model)
                end
            end
        end
    end

    labor_market.job_seekers = Dict{Int64,Household}()
    labor_market.job_postings = Dict{Int64,Firm}()
end
