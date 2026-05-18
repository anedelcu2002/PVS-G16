function constraints = bind_solar_to_load_soc(vars, data, params)
    T = numel(data.P_load);
    soc_allow = get_param_or_default(params, 'soc_solar_allow', 0.95);
    x_pv_ub = get_param_or_default(params, 'x_pv_ub', 100);
    M = get_param_or_default(params, 'soc_big_m', 1e2); % kWh, use E_bess_ub as a safe default

    constraint_list = [];
    for t = 1:T
        % Shared SOC gate for total PV-to-load capacity
        c_soc = vars.y_solar_load_total(t) <= (vars.e_stored(t) - soc_allow * vars.E_bess + M) / M;

        % McCormick envelope for x_pv_gate_total(t) = y_solar_load_total(t) * (x_pv + x_pv2)
        x_pv_total = vars.x_pv + vars.x_pv2;
        c1 = vars.x_pv_gate_total(t) <= x_pv_ub * vars.y_solar_load_total(t);
        c2 = vars.x_pv_gate_total(t) <= x_pv_total;
        c3 = vars.x_pv_gate_total(t) >= x_pv_total - x_pv_ub * (1 - vars.y_solar_load_total(t));
        c4 = vars.x_pv_gate_total(t) >= 0;

        % Split total gated capacity between arrays
        c5 = vars.x_pv_gate_1(t) >= 0;
        c6 = vars.x_pv_gate_2(t) >= 0;
        c7 = vars.x_pv_gate_1(t) + vars.x_pv_gate_2(t) == vars.x_pv_gate_total(t);
        c8 = vars.x_pv_gate_1(t) <= vars.x_pv;
        c9 = vars.x_pv_gate_2(t) <= vars.x_pv2;

        if t == 1
            constraint_list = [c_soc, c1, c2, c3, c4, c5, c6, c7, c8, c9];
        else
            constraint_list = [constraint_list, c_soc, c1, c2, c3, c4, c5, c6, c7, c8, c9];
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