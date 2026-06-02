function constraints = bind_battery_soc(vars, data, params)
    % BIND_BATTERY_SOC State-of-charge limits and initialization
    
    if ~isfield(params, 'enable_battery') || ~params.enable_battery
        constraints = [];
        return;
    end
    
    T = numel(data.P_load);
    soc_min = get_param_or_default(params, 'soc_min', 0.20);     % Minimum SOC (20%)
    soc_max = get_param_or_default(params, 'soc_max', 0.95);     % Maximum SOC (95%)
    soc0 = get_param_or_default(params, 'soc0', 0.50);           % Initial SOC (50%)
    soc_tol = get_param_or_default(params, 'soc_tolerance', 10e3); % Tolerance for cycle (Wh)
    
    constraint_list = [];
    
    % Initial SOC constraint: e_stored(1) = soc0 * E_bess
    constraint_list = [constraint_list, vars.e_stored(1) == soc0 * vars.E_bess];
    
    % SOC bounds for all time steps
    for t = 1:T+1
        lb = soc_min * vars.E_bess <= vars.e_stored(t);
        ub = vars.e_stored(t) <= soc_max * vars.E_bess;
        constraint_list = [constraint_list, lb, ub];
    end
    
    % Cyclic constraint: SOC(end) ~= SOC(start)
    constraint_list = [constraint_list, ...
                       vars.e_stored(1) - soc_tol <= vars.e_stored(T+1), ...
                       vars.e_stored(T+1) <= vars.e_stored(1) + soc_tol];
    
    constraints = constraint_list;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end