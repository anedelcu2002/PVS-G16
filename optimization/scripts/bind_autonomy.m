function constraints = bind_autonomy(vars, data, params)
    % BIND_AUTONOMY Enforce battery autonomy (days of independence)
    %
    % Enforces minimum battery energy capacity to provide autonomy
    % without renewable generation. Anchors battery sizing and helps
    % Gurobi find feasible charge/discharge patterns quickly.
    %
    % Default: 2-day autonomy
    %   E_bess >= 2 * E_load_annual / 365 / (soc_max - soc_min)

    if ~isfield(params, 'enable_autonomy') || ~params.enable_autonomy
        constraints = [];
        return;
    end
    
    % Check that battery exists
    if ~isfield(vars, 'E_bess')
        constraints = [];
        return;
    end
    
    dt_h = params.dt_h;
    E_load_total = sum(data.P_load) * dt_h;
    days_modeled = numel(data.P_load) * dt_h / 24;
    
    % Autonomy parameters
    autonomy_days = get_param_or_default(params, 'autonomy_days', 2);
    soc_min = get_param_or_default(params, 'soc_min', 0.10);
    soc_max = get_param_or_default(params, 'soc_max', 0.90);
    
    % Usable capacity per unit E_bess
    usable_soc_range = soc_max - soc_min;
    
    % Minimum energy to support autonomy_days without generation
    min_daily_avg = E_load_total / max(days_modeled, eps);
    min_E_bess = autonomy_days * min_daily_avg / usable_soc_range;
    
    % Constraint: E_bess must be large enough
    constraint_list = [vars.E_bess >= min_E_bess];
    
    constraints = constraint_list;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
