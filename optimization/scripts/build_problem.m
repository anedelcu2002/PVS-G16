function result = build_problem(data, params, constraint_registry, objective_registry)
    % BUILD_PROBLEM Main optimization orchestrator with battery support
    
    vars.x_pv = sdpvar(1, 1); 

    T = numel(data.P_load);
    vars.slack = sdpvar(T, 1);    % Unmet demand per hour [W]
    
    %% Create battery variables if enabled
    battery_enabled = isfield(params, 'enable_battery') && params.enable_battery;
    
    if battery_enabled
        vars.E_bess = sdpvar(1, 1);        % Decision variable
        
        vars.p_ch = sdpvar(T, 1);            % Charging power per hour [W]
        vars.p_dis = sdpvar(T, 1);           % Discharging power per hour [W]
        vars.e_stored = sdpvar(T+1, 1);      % Stored energy progression [Wh]
        vars.z = binvar(T, 1);               % Charge mode binary: 1=charge, 0=discharge
        vars.p_curt = sdpvar(T, 1);          % Curtailment [W]
    end

    %% Initialize constraints with variable bounds
    x_pv_ub = get_param_or_default(params, 'x_pv_ub', 1000);
    constraints = [0 <= vars.x_pv <= x_pv_ub];
    
    
    constraints = [constraints, 0 <= vars.slack];
    
    
    % Add battery bounds if enabled
    if battery_enabled
        E_bess_ub = get_param_or_default(params, 'E_bess_ub', 1e10);
        constraints = [constraints, 0 <= vars.E_bess <= E_bess_ub];
        
        constraints = [constraints, ...
                       0 <= vars.p_ch, ...
                       0 <= vars.p_dis, ...
                       0 <= vars.p_curt, ...
                       0 <= vars.e_stored];
    end
    
    %% Apply registered constraints
    if ~isempty(constraint_registry)
        for i = 1:numel(constraint_registry)
            constraint_func = constraint_registry{i};
            c = feval(constraint_func, vars, data, params);
            constraints = [constraints, c];
        end
    end

    % Add slack bounds if enabled
    slack_enabled = isfield(params, 'enable_slack') && params.enable_slack;
    if slack_enabled
        constraints = [constraints, 0 <= vars.slack];
    else
        % No slack: force to zero
        constraints = [constraints, vars.slack == 0];
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
        result.cost = value(objective);
        
        % Calculate energy metrics
        result.E_pv_annual = result.x_pv * sum(data.P_solar_unit) * params.dt_h;
        result.E_load_annual = params.dt_h * sum(data.P_load);
        result.E_slack_annual = params.dt_h * sum(result.slack);
        result.pv_percent = 100 * result.E_pv_annual / result.E_load_annual;
        result.slack_percent = 100 * result.E_slack_annual / result.E_load_annual;
        
        % Add battery results if enabled
        if battery_enabled
            result.E_bess = value(vars.E_bess);
            result.p_ch = value(vars.p_ch);
            result.p_dis = value(vars.p_dis);
            result.e_stored = value(vars.e_stored);
            result.z = value(vars.z);
            result.p_curt = value(vars.p_curt);
            result.E_battery_annual = params.dt_h * sum(result.p_dis);
            result.E_curt_annual = params.dt_h * sum(result.p_curt);
        end
        
        % Renewable energy system sizing
        fprintf('RENEWABLE ENERGY SYSTEM SIZING:\n');
        fprintf('  PV inverters:        %.4f units\n', result.x_pv);
        if battery_enabled
            fprintf('  Battery capacity:    %.4f GWh\n', result.E_bess / 1e9);
            fprintf('  Battery power (C-rate %.2f h⁻¹): %.4f GW\n', ...
                params.battery_c_rating, result.E_bess * params.battery_c_rating / 1e9);
        end

        % Annual energy balance
        fprintf('\nANNUAL ENERGY BALANCE:\n');
        fprintf('  Total demand:        %.2e Wh\n', result.E_load_annual);
        fprintf('  PV generation:       %.2e Wh (%.1f%%)\n', result.E_pv_annual, result.pv_percent);
        if battery_enabled
            fprintf('  Battery dispatch:    %.2e Wh (%.1f%% of demand)\n', ...
                result.E_battery_annual, 100 * result.E_battery_annual / result.E_load_annual);
            fprintf('  Curtailment:         %.2e Wh (%.1f%% of generation)\n', ...
                result.E_curt_annual, 100 * result.E_curt_annual / (result.E_pv_annual));
        end
        fprintf('  Unmet demand (slack):%.2e Wh (%.1f%%)\n', result.E_slack_annual, result.slack_percent);
        
        % Cost summary
        fprintf('\nECONOMIC OUTCOMES:\n');
        fprintf('  Total system cost (annualized): %.2e $/year\n', result.cost);
        
        % Calculate and display LCOE
        energy_served_wh = result.E_load_annual - result.E_slack_annual;
        energy_served_kwh = energy_served_wh / 1000;
        lcoe_eur_per_kwh = result.cost / energy_served_kwh; 
        fprintf('  LCOE (Levelized Cost of Energy): %.4f €/kWh\n', lcoe_eur_per_kwh);
        
        if battery_enabled
            % Compute CRF for annualization
            discount_rate = get_param_or_default(params, 'discount_rate', 0.05);
            project_life = get_param_or_default(params, 'project_life', 20);
            CRF = discount_rate * (1 + discount_rate)^project_life / ...
                  ((1 + discount_rate)^project_life - 1);
            
            % PV costs (annualized capex + FOM)
            cost_pv_capex_ann = CRF * result.x_pv * params.c_pv_unit_capex;
            cost_pv_fom_ann = result.x_pv * params.c_pv_unit_fom_per_year;
            cost_pv_ann = cost_pv_capex_ann + cost_pv_fom_ann;
            
            % Battery costs (annualized capex + FOM)
            c_bess_E_capex = get_param_or_default(params, 'c_bess_E_capex_per_Wh', 250);
            c_bess_E_fom = get_param_or_default(params, 'c_bess_E_fom_per_Wh_yr', 5);
            cost_bess_capex_ann = CRF * c_bess_E_capex * result.E_bess;
            cost_bess_fom_ann = c_bess_E_fom * result.E_bess;
            cost_bess_ann = cost_bess_capex_ann + cost_bess_fom_ann;
            
            fprintf('    PV (annualized):   %.2e $/year\n', cost_pv_ann);
            fprintf('    Battery (annualized): %.2e $/year\n', cost_bess_ann);
            
            % Show breakdown percentages
            total_capac_fom = cost_pv_ann + cost_bess_ann;
            
            
            fprintf('    Capital & FOM subtotal: %.2e $/year\n', total_capac_fom);
            fprintf('    Operations & dispatch: %.2e $/year\n', result.cost - total_capac_fom);
        end
        
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
