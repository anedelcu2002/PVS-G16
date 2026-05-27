function result = build_problem(data, params, constraint_registry, objective_registry)
    % BUILD_PROBLEM Main optimization orchestrator with battery support
 
    %% Create variables
    vars.x_pv = sdpvar(1, 1);
    vars.x_pv2 = sdpvar(1, 1);  

    T = numel(data.P_load); 
    vars.slack = sdpvar(T, 1);    % Unmet demand per hour [kW]
    vars.p_curt = sdpvar(T, 1);          % Curtailment [kW] 
    vars.u_slack = binvar(T, 1);   % 1 if slack > 0 at hour t
    
    vars.E_bess = sdpvar(1, 1);        % Decision variable
    vars.p_ch = sdpvar(T, 1);            % Charging power per hour [kW]
    vars.p_dis = sdpvar(T, 1);           % Discharging power per hour [kW]
    vars.e_stored = sdpvar(T+1, 1);      % Stored energy progression [kWh]
    vars.z = binvar(T, 1);               % Charge mode binary: 1=charge, 0=discharge
    vars.y_solar_load_total = sdpvar(T, 1);  % shared gate in [0, 1]
    vars.x_pv_gate_total = sdpvar(T, 1);     % total gated PV capacity

    vars.x_pv_gate_1 = sdpvar(T, 1);         % gated PV capacity for Solar1
    vars.x_pv_gate_2 = sdpvar(T, 1);         % gated PV capacity for Solar2

    % Grid import and split charging
    vars.p_grid = sdpvar(T, 1);       % Grid import [kW]
    vars.p_ch_solar = sdpvar(T, 1);   % Battery charge from solar [kW]
    vars.p_ch_grid = sdpvar(T, 1);    % Battery charge from grid [kW]

    %% Initialize constraints with variable bounds
    x_pv_ub = get_param_or_default(params, 'x_pv_ub', 100);
    x_pv2_ub = get_param_or_default(params, 'x_pv2_ub', 100);
    constraints = [0 <= vars.x_pv <= x_pv_ub];
    constraints = [constraints, 0 <= vars.x_pv2 <= x_pv2_ub];
    constraints = [constraints, 0 <= vars.slack];
    constraints = [constraints, 0 <= vars.u_slack <= 1];
    constraints = [constraints, 0 <= vars.y_solar_load_total <= 1];
    constraints = [constraints, 0 <= vars.x_pv_gate_total <= x_pv_ub];
    constraints = [constraints, 0 <= vars.x_pv_gate_1 <= x_pv_ub];
    constraints = [constraints, 0 <= vars.x_pv_gate_2 <= x_pv2_ub];

    slack_big_m = get_param_or_default(params, 'slack_big_m', max(data.P_load) + 1);
    constraints = [constraints, vars.slack <= slack_big_m * vars.u_slack];

    % Add battery bounds if enabled
    E_bess_lb = get_param_or_default(params, 'E_bess_lb', 300);
    E_bess_ub = get_param_or_default(params, 'E_bess_ub', 500);
    constraints = [constraints, E_bess_lb <= vars.E_bess <= E_bess_ub];
    
    constraints = [constraints, ...
                    0 <= vars.p_grid, ...
                    0 <= vars.p_ch_solar, ...
                    0 <= vars.p_ch_grid, ...
                    0 <= vars.p_ch, ...
                    0 <= vars.p_dis, ...
                    0 <= vars.p_curt, ...
                    0 <= vars.e_stored];

    % Link total charge to split components
    constraints = [constraints, vars.p_ch == vars.p_ch_solar + vars.p_ch_grid];
    
    %% Apply registered constraints
    if ~isempty(constraint_registry)
        for i = 1:numel(constraint_registry)
            constraint_func = constraint_registry{i};
            c = feval(constraint_func, vars, data, params);
            constraints = [constraints, c];
        end
    end
    
    %% Build objective from registered components
    objective = 0;
    if ~isempty(objective_registry)
        for i = 1:numel(objective_registry)
            obj_func = objective_registry{i};
            objective = objective + feval(obj_func, vars, data, params);
        end
    end
    
    %% Solve optimization problem
    opts = sdpsettings('solver', 'gurobi', 'verbose', 1, 'gurobi.TimeLimit', 300);

    fprintf('Solving MVP optimization problem...\n')
    fprintf('\n')

    diagnostics = optimize(constraints, objective, opts);
    
    %% Package results
    result = struct();
    has_feasible_solution = (diagnostics.problem == 0) || (diagnostics.problem == 3 && ~isinf(value(objective)));

    if has_feasible_solution
        if diagnostics.problem == 0
            result.status = 'optimal';
        else
            result.status = 'feasible (time-limited)';
        end
        result.x_pv = value(vars.x_pv);
        result.slack = value(vars.slack);
        result.u_slack = value(vars.u_slack);
        result.slack_hours = sum(result.u_slack);
        result.cost = value(objective);
        result.x_pv2 = value(vars.x_pv2);
        result.x_pv_gate_total = value(vars.x_pv_gate_total);
        result.x_pv_gate_1 = value(vars.x_pv_gate_1);
        result.x_pv_gate_2 = value(vars.x_pv_gate_2);
        % Calculate energy metrics
        result.E_pv_annual = (result.x_pv * sum(data.P_solar_unit) + ...
                              result.x_pv2 * sum(data.P_solar_unit_2)) * params.dt_h;
        result.E_load_annual = params.dt_h * sum(data.P_load);
        result.E_slack_annual = params.dt_h * sum(result.slack);
        result.pv_percent = 100 * result.E_pv_annual / result.E_load_annual;
        result.slack_percent = 100 * result.E_slack_annual / result.E_load_annual;

        % Add battery results if enabled
        result.E_bess = value(vars.E_bess);
        result.p_ch = value(vars.p_ch);
        result.p_dis = value(vars.p_dis);
        result.e_stored = value(vars.e_stored);
        result.z = value(vars.z);
        result.p_curt = value(vars.p_curt);
        result.E_battery_annual = params.dt_h * sum(result.p_dis);
        result.E_curt_annual = params.dt_h * sum(result.p_curt);
        result.E_pv1_annual = result.x_pv * sum(data.P_solar_unit) * params.dt_h;
        result.E_pv2_annual = result.x_pv2 * sum(data.P_solar_unit_2) * params.dt_h;

        % Add grid results
        result.p_grid = value(vars.p_grid);
        result.p_ch_solar = value(vars.p_ch_solar);
        result.p_ch_grid = value(vars.p_ch_grid);
        result.E_pv1_annual = result.x_pv * sum(data.P_solar_unit) * params.dt_h;
        result.E_pv2_annual = result.x_pv2 * sum(data.P_solar_unit_2) * params.dt_h;
    else
        result.status = 'infeasible or error';
        result.x_pv = NaN;
        result.slack = NaN;
        result.cost = NaN;
    end
    
    result.diagnostics = diagnostics;
    
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
