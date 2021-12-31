mutable struct HousingMarketOffer
    owner::Union{Bank, Household}
    price::Float64
    house::House
end

mutable struct HousingMarketBid
    bidder::Household
    price::Float64
    as_main_residence::Bool
    ltv::Float64
end

mutable struct HousingMarketTransaction
    quality::Float64
    price::Float64
    day::Int64
end

mutable struct HousingMarket <: AbstractAgent
    id::Int
    rental_market_offers::Dict{HousingMarketOffer, Float64}
    rental_market_bids::Dict{HousingMarketBid, Float64}
    rental_market_transactions::Dict{Float64, HousingMarketTransaction}
    rental_market_unmet_offers::Dict{Float64, HousingMarketOffer}
    rental_market_average_quality::Float64
    rental_market_average_price::Float64
    rental_market_average_price_history::CircularBuffer{Float64}
    rental_market_average_offer_price::Float64
    rental_market_no_bids::Int64
    rental_market_no_offers::Int64
    rental_market_no_matches::Int64
    rent_price_index::Float64
    rent_price_index_history::CircularBuffer{Float64}
    rent_price_index_growth::Float64
    rental_market_binned_average_prices::Dict{Float64, Float64}
    housing_market_offers::Dict{HousingMarketOffer, Float64}
    housing_market_bids::Dict{HousingMarketBid, Float64}
    housing_market_transactions::Dict{Float64, HousingMarketTransaction}
    housing_market_unmet_offers::Dict{Float64, HousingMarketOffer}
    housing_market_average_quality::Float64
    housing_market_average_price::Float64
    housing_market_average_price_history::CircularBuffer{Float64}
    housing_market_average_offer_price::Float64
    housing_market_average_time_on_market::Float64
    housing_market_no_bids::Int64
    housing_market_no_offers::Int64
    housing_market_no_matches::Int64
    house_price_index::Float64
    house_price_index_history::CircularBuffer{Float64}
    house_price_index_growth::Float64
    housing_market_binned_average_prices::Dict{Float64, Float64}
end

function HousingMarket(id)
    return HousingMarket(id, Dict{HousingMarketOffer, Float64}(), Dict{HousingMarketBid, Float64}(),Dict{Float64, HousingMarketTransaction}(),Dict{Float64, HousingMarketOffer}(),0,0,CircularBuffer{Float64}(3),0,0,0,0,0,CircularBuffer{Float64}(12),0,Dict{Float64, Float64}(),Dict{HousingMarketOffer, Float64}(), Dict{HousingMarketBid, Float64}(),Dict{Float64, HousingMarketTransaction}(),Dict{Float64, HousingMarketOffer}(),0,0,CircularBuffer{Float64}(3),0,0,0,0,0,0,CircularBuffer{Float64}(12),0,
    Dict{Float64, Float64}())
end

function agent_step!(housing_market::HousingMarket, model)
    if hasmethod(getfield(Main, Symbol(model.current_step)), (HousingMarket, AgentBasedModel))
        getfield(Main, Symbol(model.current_step))(housing_market, model)
    end
end

function rental_market(housing_market::HousingMarket, model)
    no_new_contracts = 0

    housing_market.rental_market_no_bids = length(housing_market.rental_market_bids)
    housing_market.rental_market_no_offers = length(housing_market.rental_market_offers)

    housing_market.rental_market_average_offer_price = mean(collect(values(housing_market.rental_market_offers)))

    matches_last_round = true

    for round in 1:1000
        if length(housing_market.rental_market_bids) > 0 && length(housing_market.rental_market_offers) > 0 && matches_last_round
            matches_last_round = false

            sorted_offers = sort(collect(keys(housing_market.rental_market_offers)), by=x->x.house.quality, rev=true)

            matches = Dict{HousingMarketOffer, Array{HousingMarketBid,1}}()

            for offer in sorted_offers
                can_afford = Array{HousingMarketBid,1}()

                for (bid, bid_price) in housing_market.rental_market_bids
                    if bid_price > offer.price
                        push!(can_afford, bid)

                        delete!(housing_market.rental_market_bids, bid)
                    end
                end

                matches[offer] = can_afford
            end

            for (offer, bids) in matches
                if length(bids) > 0
                    if length(bids) > 1
                        # Bid up
                        geom_dist = Geometric(exp(-5*min(10,length(bids))/20))
                        k = rand(geom_dist)
                        price = offer.price * (1+model.housing_market_bid_up)^k

                        can_still_afford = Array{HousingMarketBid,1}()

                        for bid in bids
                            if bid.price > price
                                push!(can_still_afford, bid)
                            else
                                # not successful -> push back for next round
                                housing_market.rental_market_bids[bid] = bid.price
                            end
                        end

                        winner = nothing

                        if length(can_still_afford) > 0
                            winner = rand(can_still_afford)
                            delete!(housing_market.rental_market_offers, offer)

                            contract = RentalContract(offer.owner.id, winner.bidder.id, offer.house.id, price, rand(12:24))
                            @assert winner.bidder.rental_contract == nothing
                            winner.bidder.rental_contract = contract
                            @assert offer.owner.other_properties[offer.house.id].rental_contract == nothing
                            offer.owner.other_properties[offer.house.id].rental_contract = contract
                            offer.owner.other_properties[offer.house.id].currently_on_rental_market = false
                            offer.owner.other_properties[offer.house.id].months_on_market = 0

                            no_new_contracts+=1

                            matches_last_round = true

                            tx = HousingMarketTransaction(offer.house.quality, price, model.day)
                            housing_market.rental_market_transactions[offer.house.quality] = tx
                        end

                        for bid in bids
                            if bid != winner
                                # not successful -> push back for next round
                                housing_market.rental_market_bids[bid] = bid.price
                            end
                        end

                    else
                        contract = RentalContract(offer.owner.id, bids[1].bidder.id, offer.house.id, offer.price, rand(12:24))
                        @assert bids[1].bidder.rental_contract == nothing
                        bids[1].bidder.rental_contract = contract
                        @assert offer.owner.other_properties[offer.house.id].rental_contract == nothing
                        offer.owner.other_properties[offer.house.id].rental_contract = contract
                        offer.owner.other_properties[offer.house.id].currently_on_rental_market = false
                        offer.owner.other_properties[offer.house.id].months_on_market = 0

                        delete!(housing_market.rental_market_offers, offer)

                        no_new_contracts+=1

                        tx = HousingMarketTransaction(offer.house.quality, offer.price, model.day)
                        housing_market.rental_market_transactions[offer.house.quality] = tx
                    end
                end
            end
        else
            break
        end
    end

    housing_market.rental_market_offers = Dict{HousingMarketOffer, Float64}()
    housing_market.rental_market_bids = Dict{HousingMarketBid, Float64}()

    # Delete old transactions from history and calculate index
    sum_quality = 0.0
    sum_price = 0.0
    n = 0
    for (q, tx) in housing_market.rental_market_transactions
        if (model.day - tx.day) > 120
            if length(keys(housing_market.rental_market_transactions))>10
                pop!(housing_market.rental_market_transactions, q)
            end
        else
            n+=1
            sum_quality += tx.quality
            sum_price += tx.price
        end
    end

    housing_market.rental_market_average_quality = sum_quality / n
    housing_market.rental_market_average_price = sum_price / n

    push!(housing_market.rental_market_average_price_history, housing_market.rental_market_average_price)

    # Calculate Rent price index
    bins = collect(keys(housing_market.rental_market_binned_average_prices))

    new_prices_binned = Dict{Float64, Array{Float64, 1}}()

    for bin in bins
        new_prices_binned[bin] = Array{Float64, 1}()
    end

    for (q, tx) in housing_market.rental_market_transactions
        bin = bins[findmin(abs.(bins.-q))[2]]

        push!(new_prices_binned[bin], tx.price)
    end

    for bin in bins
        if length(new_prices_binned[bin]) > 0
            housing_market.rental_market_binned_average_prices[bin] = mean(new_prices_binned[bin])
        end
    end

    housing_market.rent_price_index = mean(values(housing_market.rental_market_binned_average_prices))

    push!(housing_market.rent_price_index_history, housing_market.rent_price_index)

    rpi_history = convert(Vector{Float64}, housing_market.rent_price_index_history)
    if length(rpi_history) == 12
        housing_market.rent_price_index_growth = (rpi_history[12] / rpi_history[1])-1
    else
        housing_market.rent_price_index_growth = 0
    end

    housing_market.rental_market_no_matches = no_new_contracts
end

function estimate_rental_price(housing_market::HousingMarket, quality::Float64)
    qualities = collect(keys(housing_market.rental_market_transactions))

    closest = qualities[findmin(abs.(qualities.-quality))[2]]

    return housing_market.rental_market_transactions[closest].price
end

function housing_market(housing_market::HousingMarket, model)
    no_sales = 0

    housing_market.housing_market_no_bids = length(housing_market.housing_market_bids)
    housing_market.housing_market_no_offers = length(housing_market.housing_market_offers)

    housing_market.housing_market_average_offer_price = mean(collect(values(housing_market.housing_market_offers)))
    housing_market.housing_market_average_time_on_market = mean(map(offer -> offer.house.months_on_market, collect(keys(housing_market.housing_market_offers))))

    no_rounds = 0

    matches_last_round = true

    for round in 1:1000

        no_rounds+=1

        if length(housing_market.housing_market_bids) > 0 && length(housing_market.housing_market_offers) > 0 && matches_last_round
            matches_last_round = false

            sorted_offers = sort(collect(keys(housing_market.housing_market_offers)), by=x->x.house.quality, rev=true)

            matches = Dict{HousingMarketOffer, Array{HousingMarketBid,1}}()

            for offer in sorted_offers
                can_afford = Array{HousingMarketBid,1}()

                for (bid, bid_price) in housing_market.housing_market_bids
                    if bid_price > offer.price
                        push!(can_afford, bid)

                        delete!(housing_market.housing_market_bids, bid)
                    end
                end

                matches[offer] = can_afford
            end

            for (offer, bids) in matches
                if length(bids) > 0
                    if length(bids) > 1
                        # Bid up
                        geom_dist = Geometric(exp(-5*min(10,length(bids))/20))
                        k = rand(geom_dist)
                        price = offer.price * (1+model.housing_market_bid_up)^k

                        @assert price > -0.0001

                        can_still_afford = Array{HousingMarketBid,1}()

                        for bid in bids
                            if bid.price > price
                                push!(can_still_afford, bid)
                            else
                                # not successful -> push back for next round
                                housing_market.housing_market_bids[bid] = bid.price
                            end
                        end

                        winner = nothing

                        if length(can_still_afford) > 0
                            winner = rand(can_still_afford)
                            delete!(housing_market.housing_market_offers, offer)

                            transfer_house(housing_market, model, offer, winner, price)

                            matches_last_round = true

                            no_sales+=1
                        end

                        for bid in bids
                            if bid != winner
                                # not successful -> push back for next round
                                housing_market.housing_market_bids[bid] = bid.price
                            end
                        end

                    else
                        delete!(housing_market.housing_market_offers, offer)

                        @assert offer.price > -0.0001

                        transfer_house(housing_market, model, offer, bids[1], offer.price)
                        no_sales+=1
                    end
                end
            end
        else
            break
        end
    end

    housing_market.housing_market_offers = Dict{HousingMarketOffer, Float64}()
    housing_market.housing_market_bids = Dict{HousingMarketBid, Float64}()

    # Delete old transactions from history and calculate index
    sum_quality = 0.0
    sum_price = 0.0
    n=0

    for (q, tx) in housing_market.housing_market_transactions
        if (model.day - tx.day) > 120
            if length(keys(housing_market.housing_market_transactions))>10
                pop!(housing_market.housing_market_transactions, q)
            end
        else
            n+=1
            sum_quality += tx.quality
            sum_price += tx.price
        end
    end

    housing_market.housing_market_average_quality = sum_quality / n
    housing_market.housing_market_average_price = sum_price / n

    push!(housing_market.housing_market_average_price_history, housing_market.housing_market_average_price)

    # Calculate House price index
    bins = collect(keys(housing_market.housing_market_binned_average_prices))

    new_prices_binned = Dict{Float64, Array{Float64, 1}}()

    for bin in bins
        new_prices_binned[bin] = Array{Float64, 1}()
    end

    for (q, tx) in housing_market.housing_market_transactions
        bin = bins[findmin(abs.(bins.-q))[2]]

        push!(new_prices_binned[bin], tx.price)
    end

    for bin in bins
        if length(new_prices_binned[bin]) > 0
            housing_market.housing_market_binned_average_prices[bin] = mean(new_prices_binned[bin])
        end
    end

    housing_market.house_price_index = mean(values(housing_market.housing_market_binned_average_prices))

    push!(housing_market.house_price_index_history, housing_market.house_price_index)

    hpi_history = convert(Vector{Float64}, housing_market.house_price_index_history)
    if length(hpi_history) == 12
        housing_market.house_price_index_growth = (hpi_history[12] / hpi_history[1])-1
    else
        housing_market.house_price_index_growth = 0.05
    end

    housing_market.housing_market_no_matches = no_sales
end

function transfer_house(housing_market::HousingMarket, model, offer, bid, price)
    # Save transaction
    tx = HousingMarketTransaction(offer.house.quality, price, model.day)
    housing_market.housing_market_transactions[offer.house.quality] = tx

    house = offer.house
    seller = offer.owner
    buyer = bid.bidder

    @assert price > -0.0001

    # Get mortgage
    if bid.ltv > 0.0
        new_mortgage = get_mortgage(model.mortgage_market, model, bid.bidder.bank_next_mortgage, bid.bidder, price, bid.ltv)

        @assert new_mortgage.outstanding_principal > -0.0001
    else
        new_mortgage = nothing
    end

    old_mortgage = house.mortgage

    if seller isa Household
        # Delete house for seller and transfer money
        if seller.main_residence != nothing && seller.main_residence.id == house.id
            # Seller sold main residence
            seller.main_residence = nothing
        else
            # Seller sold other property
            pop!(seller.other_properties, house.id)
        end

        own_contribution_from_long_term = min((1-bid.ltv) * price, buyer.payment_account_long_term)
        buyer.payment_account += own_contribution_from_long_term
        buyer.payment_account_long_term -= own_contribution_from_long_term

        bank_transfer!(buyer, seller, price)

        # repay mortgage
        if old_mortgage != nothing
            fully_repay_mortgage(model.mortgage_market, model, seller, old_mortgage)
        end

        @assert buyer.payment_account > -1e-6
    else
        # Seller is a bank.
        house_sold!(seller, model, buyer, house, price)
    end

    # Transfer house
    house.mortgage = new_mortgage
    house.months_on_market = 0
    house.currently_on_housing_market = false

    if bid.as_main_residence
        # Buyer bought as main residence
        buyer.main_residence = house
    else
        # Buyer bought as other property
        buyer.other_properties[house.id] = house
    end
end

function estimate_house_price(housing_market::HousingMarket, quality::Float64)
    qualities = collect(keys(housing_market.housing_market_transactions))

    closest = qualities[findmin(abs.(qualities.-quality))[2]]

    return housing_market.housing_market_transactions[closest].price
end

function estimate_quality(housing_market::HousingMarket, price::Float64)
    qualities_sorted = sort(collect(keys(housing_market.housing_market_transactions)), rev=true)

    estimated_quality = 0.0
    for q in qualities_sorted
        if housing_market.housing_market_transactions[q].price <= price
            estimated_quality = housing_market.housing_market_transactions[q].quality
            break
        end
    end

    return estimated_quality
end
