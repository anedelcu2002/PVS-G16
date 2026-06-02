function constraints = bind_curtailment(vars, data, params)
    % BIND_CURTAILMENT Renewable energy curtailment limits
    %
    % Independent of battery - can be used standalone
    % Enforces:
    %   - Can only curtail what's available: p_curt(t) <= x_pv*P_solar(t) + x_wt*P_wind(t)
    %   - Annual curtailment limit: sum(p_curt) * dt_h <= max_curtail_pct * E_load_annual
    %
    % Skipped if curtailment variable p_curt doesn't exist (no battery in ED mode).

    if ~isfield(params, 'enable_curtailment') || ~params.enable_curtailment
        constraints = [];
        return;
    end
    
    % Only applies if curtailment variable exists (battery enabled)
    if ~isfield(vars, 'p_curt')
        constraints = [];
        return;
    end
    
    T = numel(data.P_load);
    dt_h = params.dt_h;
    max_annual_curtail_pct = get_param_or_default(params, 'max_curtail_pct', 0.10);
    
    % Hourly: cannot curtail more than available generation
    constraint_list = [];
    for t = 1:T
        avail_gen = vars.x_pv * data.P_solar_unit(t) + vars.x_wt * data.P_wind_unit(t);
        curt_ineq = vars.p_curt(t) <= avail_gen;
        
        if t == 1
            constraint_list = curt_ineq;
        else
            constraint_list = [constraint_list, curt_ineq];
        end
    end
    
    % Annual curtailment limit - percentage of total annual load
    E_load_ann = sum(data.P_load) * dt_h;
    
    annual_curt = sum(vars.p_curt) * dt_h <= max_annual_curtail_pct * E_load_ann;
    constraint_list = [constraint_list, annual_curt];
    
    constraints = constraint_list;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
