function obj = cost_battery(vars, data, params)
    % COST_BATTERY 3-year total battery cost (CapEx + FOM * project_life)

    c_bess_E_capex = get_param_or_default(params, 'c_bess_E_capex_per_kWh', 0.1);   % $/kWh
    c_bess_E_fom = get_param_or_default(params, 'c_bess_E_fom_per_kWh_yr', 0.005); % $/kWh/year

    obj = (c_bess_E_capex + c_bess_E_fom * params.project_life) * vars.E_bess;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
