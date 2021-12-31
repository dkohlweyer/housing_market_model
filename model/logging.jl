
model_log = false
model_log_agent_types = Dict{Type, Bool}()
model_log_categories = Dict{String, Bool}()
model_log_io = stdout

function model_log_agent(agent::Type)
    global model_log_agent_types[agent] = true
end

function model_log_category(category::String)
    global model_log_categories[category] = true
end

function model_logging(enabled::Bool)
    global model_log = enabled
end

function model_logger_target(io)
    global model_log_io = io
end

macro model_log(agent, category, key, value)
    return quote
        if model_log
            if @isdefined model
                if get(model_log_agent_types, typeof($(esc(agent))), false) && get(model_log_categories, $(esc(category)), false)
                    print(model_log_io, model.day, "\t", $(esc(agent)).id, "\t", typeof($(esc(agent))), "\t", $(esc(category)), "\t", $(esc(key)))

                    print(model_log_io, "\t", $(esc(value)))

                    println(model_log_io)
                end
            else
                @warn "model_log called from a context, where 'model' is not defined."
            end
        end
    end
end

macro model_log(agent, category, key)
    return quote
        if model_log
            if @isdefined model
                if get(model_log_agent_types, typeof($(esc(agent))), false) && get(model_log_categories, $(esc(category)), false)
                    print(model_log_io, model.day, "\t", $(esc(agent)).id, "\t", typeof($(esc(agent))), "\t", $(esc(category)), "\t", $(esc(key)))

                    println(model_log_io)
                end
            else
                @warn "model_log called from a context, where 'model' is not defined."
            end
        end
    end
end
