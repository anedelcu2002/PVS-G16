function constraints = bind_match_demand(vars, data, params)
    % BIND_MATCH_DEMAND Enforce PV annual energy share
    %
    % Enforces:
    %   x_pv * sum(P_solar) * dt = pv_energy_frac * E_load
    %
    % This anchors PV sizing in PV-only runs and reduces the search space.

    if ~isfield(params, 'enable_split_constraint') || ~params.enable_split_constraint
        constraints = [];
        return;
    end
    
    dt_h = params.dt_h;
    E_load_total = sum(data.P_load) * dt_h;
    E_pv_total = vars.x_pv * sum(data.P_solar_unit) * dt_h;
    pv_energy_frac = get_param_or_default(params, 'pv_energy_frac', 1.0);

    % Enforce PV energy share: PV provides pv_energy_frac of total load
    constraint_list = [
        E_pv_total == pv_energy_frac * E_load_total
    ];
    constraints = constraint_list;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
