function constraints = bind_split_pv_wt(vars, data, params)
    % BIND_SPLIT_PV_WT Enforce 50-50 renewable energy split
    %
    % Enforces:
    %   x_pv * sum(P_solar) * dt = 0.5 * E_load_annual
    %   x_wt * sum(P_wind) * dt = 0.5 * E_load_annual
    %
    % This constraint dramatically reduces solution space by fixing x_pv and x_wt,
    % allowing optimizer to focus on battery sizing.
    % Improves convergence from hours->minutes.
    %
    % Skipped in ED mode if x_pv and x_wt are both fixed.

    if ~isfield(params, 'enable_split_constraint') || ~params.enable_split_constraint
        constraints = [];
        return;
    end
    
    % Skip if both sizing variables are fixed (cannot be optimized)
    if ~isa(vars.x_pv, 'sdpvar') && ~isa(vars.x_wt, 'sdpvar')
        constraints = [];
        return;
    end
    
    dt_h = params.dt_h;
    E_load_annual = sum(data.P_load) * dt_h;
    E_pv_annual = vars.x_pv * sum(data.P_solar_unit) * dt_h;
    E_wt_annual = vars.x_wt * sum(data.P_wind_unit) * dt_h;

    % Enforce 50-50 split: each source must provide exactly half of annual load
    constraint_list = [
        E_pv_annual == 0.5 * E_load_annual,
        E_wt_annual == 0.5 * E_load_annual
    ];
    constraints = constraint_list;
end
