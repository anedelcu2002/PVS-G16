function obj = default_objective(vars, data, params)
    % DEFAULT_OBJECTIVE Sum of PV costs
    obj = cost_pv(vars, data, params);
end
