function constraints = bind_solar_to_load_soc(vars, data, params)
    T = numel(data.P_load);
    soc_allow = get_param_or_default(params, 'soc_solar_allow', 0.95);
    x_pv_ub = get_param_or_default(params, 'x_pv_ub', 100);
    M = get_param_or_default(params, 'soc_big_m', 1e2); % kWh, use E_bess_ub as a safe default

    constraint_list = [];
    for t = 1:T
        % Soft SOC gate: if SOC < 95%, gate can still be >0 but is limited
        c_soc = vars.y_solar_load(t) <= (vars.e_stored(t) - soc_allow * vars.E_bess + M) / M;

        % McCormick envelope for x_pv_gate(t) = y_solar_load(t) * x_pv
        c1 = vars.x_pv_gate(t) <= x_pv_ub * vars.y_solar_load(t);
        c2 = vars.x_pv_gate(t) <= vars.x_pv;
        c3 = vars.x_pv_gate(t) >= vars.x_pv - x_pv_ub * (1 - vars.y_solar_load(t));
        c4 = vars.x_pv_gate(t) >= 0;

        if t == 1
            constraint_list = [c_soc, c1, c2, c3, c4];
        else
            constraint_list = [constraint_list, c_soc, c1, c2, c3, c4];
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