function constraints = bind_curtailment(vars, data, params)
    % BIND_CURTAILMENT Renewable energy curtailment limits
    %
    % Independent of battery - can be used standalone
    % Enforces:
    %   - Can only curtail what's available: p_curt(t) <= x_pv*P_solar(t)
    %
    % Skipped if curtailment variable p_curt doesn't exist (no battery in ED mode).
    
    T = numel(data.P_load);
    
    % Hourly: cannot curtail more than available generation
    constraint_list = [];
    for t = 1:T
        avail_gen = vars.x_pv * data.P_solar_unit(t) + ...
                    vars.x_pv2 * data.P_solar_unit_2(t);
        curt_ineq = vars.p_curt(t) <= avail_gen;
        
        if t == 1
            constraint_list = curt_ineq;
        else
            constraint_list = [constraint_list, curt_ineq];
        end
    end
    
    constraints = constraint_list;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
