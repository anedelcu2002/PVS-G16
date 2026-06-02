function obj = default_objective(vars, data, params)
    % DEFAULT_OBJECTIVE Sum of PV and wind costs
    obj = cost_pv(vars, data, params) + cost_wt(vars, data, params);
end
