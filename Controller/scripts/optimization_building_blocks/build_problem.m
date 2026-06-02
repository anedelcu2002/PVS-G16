function result = build_problem(data, params, constraint_registry, objective_registry)
    % BUILD_PROBLEM Main optimization orchestrator with battery support
    % Supports both sizing optimization and economic dispatch (fixed capacity) modes
    
    %% Check if in ED mode
    ed_mode = isfield(params, 'enable_ed_mode') && params.enable_ed_mode;
    
    %% Create decision variables (or fix them if in ED mode)
    % For each variable, check if it's fixed in ED mode params
    if ed_mode && isfield(params, 'x_pv_fixed') && ~isempty(params.x_pv_fixed)
        vars.x_pv = params.x_pv_fixed;  % Fixed parameter
        pv_is_fixed = true;
    else
        vars.x_pv = sdpvar(1, 1);       % Decision variable
        pv_is_fixed = false;
    end
    
    if ed_mode && isfield(params, 'x_wt_fixed') && ~isempty(params.x_wt_fixed)
        vars.x_wt = params.x_wt_fixed;  % Fixed parameter
        wt_is_fixed = true;
    else
        vars.x_wt = sdpvar(1, 1);       % Decision variable
        wt_is_fixed = false;
    end
    
    T = numel(data.P_load);
    vars.slack = sdpvar(T, 1);    % Unmet demand per hour [W]
    
    %% Create battery variables if enabled
    battery_enabled = isfield(params, 'enable_battery') && params.enable_battery;
    
    if battery_enabled
        if ed_mode && isfield(params, 'E_bess_fixed') && ~isempty(params.E_bess_fixed)
            vars.E_bess = params.E_bess_fixed;  % Fixed parameter
            bess_is_fixed = true;
        else
            vars.E_bess = sdpvar(1, 1);        % Decision variable
            bess_is_fixed = false;
        end
        
        vars.p_ch = sdpvar(T, 1);            % Charging power per hour [W]
        vars.p_dis = sdpvar(T, 1);           % Discharging power per hour [W]
        vars.e_stored = sdpvar(T+1, 1);      % Stored energy progression [Wh]
        vars.z = binvar(T, 1);               % Charge mode binary: 1=charge, 0=discharge
        vars.p_curt = sdpvar(T, 1);          % Curtailment [W]
    end

    %% Create backup variables if enabled
    backup_enabled = isfield(params, 'enable_backup') && params.enable_backup;
    
    if backup_enabled
        if ed_mode && isfield(params, 'P_backup_fixed') && ~isempty(params.P_backup_fixed)
            vars.P_backup = params.P_backup_fixed;  % Fixed parameter
            backup_is_fixed = true;
        else
            vars.P_backup = sdpvar(1, 1);      % Decision variable
            backup_is_fixed = false;
        end
        
        vars.p_bg = sdpvar(T, 1);           % Backup dispatch per hour [W]
    end
    
    %% Initialize constraints with variable bounds
    x_pv_ub = get_param_or_default(params, 'x_pv_ub', 1000);
    x_wt_ub = get_param_or_default(params, 'x_wt_ub', 100);
    
    % Only add bounds if variable is not fixed
    if ~pv_is_fixed
        constraints = [0 <= vars.x_pv <= x_pv_ub];
    else
        constraints = [];
    end
    
    if ~wt_is_fixed
        constraints = [constraints, 0 <= vars.x_wt <= x_wt_ub];
    end
    
    constraints = [constraints, 0 <= vars.slack]; %#ok<CVCH>
    
    % Track named constraints for binding analysis
    constraint_metadata = {};
    if ~pv_is_fixed
        constraint_metadata = add_constraint_meta(constraint_metadata, '0 <= x_pv <= %.0f', x_pv_ub, 'PV sizing bounds');
    end
    if ~wt_is_fixed
        constraint_metadata = add_constraint_meta(constraint_metadata, '0 <= x_wt <= %.0f', x_wt_ub, 'Wind sizing bounds');
    end
    
    % Add battery bounds if enabled
    if battery_enabled
        E_bess_ub = get_param_or_default(params, 'E_bess_ub', 1e10);
        if ~bess_is_fixed
            constraints = [constraints, 0 <= vars.E_bess <= E_bess_ub];
            constraint_metadata = add_constraint_meta(constraint_metadata, '0 <= E_bess <= %.2e Wh', E_bess_ub, 'Battery energy capacity bounds');
        end
        
        constraints = [constraints, ...
                       0 <= vars.p_ch, ...
                       0 <= vars.p_dis, ...
                       0 <= vars.p_curt, ...
                       0 <= vars.e_stored];
        constraint_metadata = add_constraint_meta(constraint_metadata, '0 <= p_ch(t) for all t', 0, 'Charging power bounds');
        constraint_metadata = add_constraint_meta(constraint_metadata, '0 <= p_dis(t) for all t', 0, 'Discharging power bounds');
        constraint_metadata = add_constraint_meta(constraint_metadata, '0 <= p_curt(t) for all t', 0, 'Curtailment power bounds');
    end
    
    % Add backup bounds if enabled
    if backup_enabled
        P_backup_ub = get_param_or_default(params, 'P_backup_ub', 100e6);  % 100 MW default
        if ~backup_is_fixed
            constraints = [constraints, 0 <= vars.P_backup <= P_backup_ub];
            constraint_metadata = add_constraint_meta(constraint_metadata, '0 <= P_backup <= %.2e W', P_backup_ub, 'Backup power capacity bounds');
        end
        constraints = [constraints, 0 <= vars.p_bg];
        constraint_metadata = add_constraint_meta(constraint_metadata, '0 <= p_bg(t) for all t', 0, 'Backup dispatch bounds');
    end
    
    %% Apply registered constraints
    if ~isempty(constraint_registry)
        for i = 1:numel(constraint_registry)
            constraint_func = constraint_registry{i};
            c = feval(constraint_func, vars, data, params);
            constraints = [constraints, c];
            
            % Add metadata based on constraint function name
            func_name = func2str(constraint_func);
            switch func_name
                case 'bind_power_balance'
                    constraint_metadata = add_constraint_meta(constraint_metadata, ...
                        'Power balance at each hour (t=1..%d)', T, 'Power balance equalities');
                case 'bind_battery_dynamics'
                    constraint_metadata = add_constraint_meta(constraint_metadata, ...
                        'Battery energy dynamics over %d hours', T, 'Battery state tracking');
                case 'bind_battery_soc'
                    constraint_metadata = add_constraint_meta(constraint_metadata, ...
                        'Battery SOC within [%.0f, %.0f]%% over %d hours', 100*params.soc_min, 100*params.soc_max, T, 'Battery SOC limits');
                case 'bind_battery_exclusivity'
                    constraint_metadata = add_constraint_meta(constraint_metadata, ...
                        'No simultaneous charge/discharge over %d hours', T, 'Battery exclusivity constraint');
                case 'bind_curtailment'
                    constraint_metadata = add_constraint_meta(constraint_metadata, ...
                        'Annual curtailment <= %.1f%% of load', 100*params.max_curtail_pct, 'Curtailment limit');
                case 'bind_split_pv_wt'
                    constraint_metadata = add_constraint_meta(constraint_metadata, ...
                        'Energy split: ~50%% PV, ~50%% Wind', 0, '50-50 PV/Wind split constraint');
                case 'bind_autonomy'
                    constraint_metadata = add_constraint_meta(constraint_metadata, ...
                        'Battery autonomy: %.1f days without generation', params.autonomy_days, 'Battery autonomy constraint');
                case 'bind_backup'
                    constraint_metadata = add_constraint_meta(constraint_metadata, ...
                        'Annual backup <= %.1f%% of load', 100*params.backup_energy_pct, 'Backup generation constraint');
            end
        end
    end

    % Add slack bounds if enabled
    slack_enabled = isfield(params, 'enable_slack') && params.enable_slack;
    if slack_enabled
        constraints = [constraints, 0 <= vars.slack]; %#ok<*CVCH>
        constraint_metadata = add_constraint_meta(constraint_metadata, '0 <= slack(t) for all t', 0, 'Slack (unmet demand) bounds');
    else
        % No slack: force to zero
        constraints = [constraints, vars.slack == 0];
        constraint_metadata = add_constraint_meta(constraint_metadata, 'slack(t) == 0 for all t', 0, 'No unmet demand (slack forced to zero)');
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
    opts = sdpsettings('solver', 'gurobi', 'verbose', 1);
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
        result.x_wt = value(vars.x_wt);
        result.slack = value(vars.slack);
        result.cost = value(objective);
        
        % Calculate energy metrics
        result.E_pv_annual = result.x_pv * sum(data.P_solar_unit) * params.dt_h;
        result.E_wt_annual = result.x_wt * sum(data.P_wind_unit) * params.dt_h;
        result.E_load_annual = params.dt_h * sum(data.P_load);
        result.E_slack_annual = params.dt_h * sum(result.slack);
        result.pv_percent = 100 * result.E_pv_annual / result.E_load_annual;
        result.wt_percent = 100 * result.E_wt_annual / result.E_load_annual;
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
        
        % Add backup results if enabled
        if params.enable_backup
            result.P_backup = value(vars.P_backup);
            result.p_bg = value(vars.p_bg);
            result.E_backup_annual = params.dt_h * sum(result.p_bg);
        end

        % ========== EXTRACT DUAL VARIABLES FOR BINDING CONSTRAINT ANALYSIS ==========
        dual_info = extract_dual_information(diagnostics, constraints, vars, data, params, result);
        
        % ========== SECTION 1: SYSTEM OUTCOMES ==========
        fprintf('\n');
        fprintf('================================================================================\n');
        if ed_mode
            fprintf('                  ECONOMIC DISPATCH RESULTS (fixed capacities) - SoC(0): %d %%\n', params.soc0 * 100);
        else
            fprintf('                  SYSTEM SIZING OPTIMIZATION RESULTS - SoC(0): %d %%\n', params.soc0 * 100);
        end
        fprintf('================================================================================\n\n');
        
        % Renewable energy system sizing
        fprintf('RENEWABLE ENERGY SYSTEM SIZING:\n');
        fprintf('  PV inverters:        %.4f units\n', result.x_pv);
        fprintf('  Wind turbines:       %.4f units\n', result.x_wt);
        if battery_enabled
            fprintf('  Battery capacity:    %.4f GWh\n', result.E_bess / 1e9);
            fprintf('  Battery power (C-rate %.2f h⁻¹): %.4f GW\n', ...
                params.battery_c_rating, result.E_bess * params.battery_c_rating / 1e9);
        end
        if backup_enabled
            fprintf('  Backup power:        %.4f GW\n', result.P_backup / 1e9);
        end
        
        % Annual energy balance
        fprintf('\nANNUAL ENERGY BALANCE:\n');
        fprintf('  Total demand:        %.2e Wh\n', result.E_load_annual);
        fprintf('  PV generation:       %.2e Wh (%.1f%%)\n', result.E_pv_annual, result.pv_percent);
        fprintf('  Wind generation:     %.2e Wh (%.1f%%)\n', result.E_wt_annual, result.wt_percent);
        if battery_enabled
            fprintf('  Battery dispatch:    %.2e Wh (%.1f%% of demand)\n', ...
                result.E_battery_annual, 100 * result.E_battery_annual / result.E_load_annual);
            fprintf('  Curtailment:         %.2e Wh (%.1f%% of generation)\n', ...
                result.E_curt_annual, 100 * result.E_curt_annual / (result.E_pv_annual+result.E_wt_annual));
        end
        if backup_enabled
            fprintf('  Backup dispatch:     %.2e Wh (%.1f%% of demand)\n', ...
                result.E_backup_annual, 100 * result.E_backup_annual / result.E_load_annual);
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
            
            % Wind costs (annualized capex + FOM)
            cost_wt_capex_ann = CRF * result.x_wt * params.c_wt_unit_capex;
            cost_wt_fom_ann = result.x_wt * params.c_wt_unit_fom_per_year;
            cost_wt_ann = cost_wt_capex_ann + cost_wt_fom_ann;
            
            % Battery costs (annualized capex + FOM)
            c_bess_E_capex = get_param_or_default(params, 'c_bess_E_capex_per_Wh', 250);
            c_bess_E_fom = get_param_or_default(params, 'c_bess_E_fom_per_Wh_yr', 5);
            cost_bess_capex_ann = CRF * c_bess_E_capex * result.E_bess;
            cost_bess_fom_ann = c_bess_E_fom * result.E_bess;
            cost_bess_ann = cost_bess_capex_ann + cost_bess_fom_ann;
            
            fprintf('    PV (annualized):   %.2e $/year\n', cost_pv_ann);
            fprintf('    Wind (annualized): %.2e $/year\n', cost_wt_ann);
            fprintf('    Battery (annualized): %.2e $/year\n', cost_bess_ann);
            
            % Show breakdown percentages
            total_capac_fom = cost_pv_ann + cost_wt_ann + cost_bess_ann;
            if backup_enabled && isfield(result, 'P_backup')
                c_backup_capex_per_W = get_param_or_default(params, 'c_backup_capex_per_W', 100);
                c_backup_fom_per_W_yr = get_param_or_default(params, 'c_backup_fom_per_W_yr', 100);
                cost_backup_capex_ann = CRF * c_backup_capex_per_W * result.P_backup;
                cost_backup_fom_ann = c_backup_fom_per_W_yr * result.P_backup;
                cost_backup_ann = cost_backup_capex_ann + cost_backup_fom_ann;
                fprintf('    Backup (annualized): %.2e $/year\n', cost_backup_ann);
                total_capac_fom = total_capac_fom + cost_backup_ann;
            end
            
            fprintf('    Capital & FOM subtotal: %.2e $/year\n', total_capac_fom);
            fprintf('    Operations & dispatch: %.2e $/year\n', result.cost - total_capac_fom);
        end
        
        % ========== SECTION 2: OPTIMIZATION PROBLEM DATA (BINDING CONSTRAINTS) ==========
        fprintf('\n');
        fprintf('================================================================================\n');
        fprintf('                   OPTIMIZATION PROBLEM DATA\n');
        fprintf('            (Binding & Non-Binding Constraints Analysis)\n');
        fprintf('================================================================================\n\n');

        % Display binding constraint analysis with natural language
        binding_count = sum([dual_info.constraints.is_binding]);
        total_count = numel(dual_info.constraints);
        
        fprintf('BINDING CONSTRAINT SUMMARY:\n');
        fprintf('  Total constraints: %d\n', total_count);
        fprintf('  Binding:           %d (%.1f%%)\n', binding_count, 100*binding_count/total_count);
        fprintf('  Non-binding:       %d (%.1f%%)\n', total_count - binding_count, 100*(total_count-binding_count)/total_count);
        
        fprintf('\n--- BINDING CONSTRAINTS (Active inequalities/equalities limiting system design) ---\n\n');
        has_binding = false;
        for i = 1:numel(dual_info.constraints)
            c = dual_info.constraints(i);
            if c.is_binding
                has_binding = true;
                desc = sprintf('  • %s', c.description);
                if ~isempty(c.details)
                    desc = sprintf('%s\n    %s', desc, c.details);
                end
                if c.dual_value ~= 0
                    desc = sprintf('%s\n    [Dual/Shadow price: %.6e]', desc, c.dual_value);
                end
                fprintf('%s\n\n', desc);
            end
        end
        if ~has_binding
            fprintf('  (No constraints are binding—solution has slack in all constraints)\n\n');
        end
        
        fprintf('--- NON-BINDING CONSTRAINTS (Inactive—could be relaxed without changing solution) ---\n\n');
        has_nonbinding = false;
        for i = 1:numel(dual_info.constraints)
            c = dual_info.constraints(i);
            if ~c.is_binding
                has_nonbinding = true;
                desc = sprintf('  • %s', c.description);
                if ~isempty(c.details)
                    desc = sprintf('%s (margin: %.2e)', desc, c.slack);
                end
                fprintf('%s\n\n', desc);
            end
        end
        if ~has_nonbinding
            fprintf('  (All constraints are binding)\n\n');
        end
        
    else
        result.status = 'infeasible or error';
        result.x_pv = NaN;
        result.x_wt = NaN;
        result.slack = NaN;
        result.cost = NaN;
    end
    
    result.diagnostics = diagnostics;
    
end

%% Local helper functions

function metadata = add_constraint_meta(metadata, template, varargin)
    % Helper to add constraint metadata for later analysis
    entry = struct();
    
    % Handle variable arguments to format template
    if ~isempty(varargin)
        try
            entry.description = sprintf(template, varargin{:});
        catch
            entry.description = template;
        end
    else
        entry.description = template;
    end
    
    entry.is_binding = false;  % Default, updated later
    entry.slack = 0;
    entry.dual_value = 0;
    entry.details = '';
    
    metadata = [metadata, {entry}];
end

function dual_info = extract_dual_information(~, ~, vars, data, params, result)
    % Extract binding constraint information from solved problem
    % Extract binding constraint information from solved problem
    % diagnostics and constraints args unused but kept for API compatibility
    
    T = numel(data.P_load);
    
    % Initialize output structure
    dual_info = struct();
    dual_info.constraints = [];
    
    % Analyze key constraints for binding status
    constraint_analysis = {};
    
    % 1. Power Balance Constraints (T hourly equalities)
    % These are typically binding for hour-to-hour satisfaction
    pb_slack_max = 1e-4;  % Tolerance for "exact" satisfaction
    pb_binding = sum(abs(result.slack) < pb_slack_max) == T;
    c = struct('description', 'Power balance constraints (hourly)', ...
        'is_binding', pb_binding, 'slack', max(abs(result.slack)), ...
        'dual_value', 0, ...
        'details', sprintf('Energy deficit handled through: slack (%.2e Wh/yr), battery (%s), backup (%s)', ...
            params.dt_h*sum(result.slack), ...
            conditionalStr(isfield(result,'E_battery_annual'), sprintf('%.2e Wh/yr', result.E_battery_annual), 'disabled'), ...
            conditionalStr(isfield(result,'E_backup_annual'), sprintf('%.2e Wh/yr', result.E_backup_annual), 'disabled')));
    constraint_analysis{end+1} = c;
    
    % 2. Variable bounds
    % Check sizing constraints
    x_pv_pct_used = 100 * result.x_pv / params.x_pv_ub;
    x_wt_pct_used = 100 * result.x_wt / params.x_wt_ub;
    
    pv_binding = (result.x_pv > params.x_pv_ub * 0.99);
    wt_binding = (result.x_wt > params.x_wt_ub * 0.99);
    
    c = struct('description', 'PV sizing upper bound', ...
        'is_binding', pv_binding, 'slack', params.x_pv_ub - result.x_pv, ...
        'dual_value', 0, ...
        'details', sprintf('Capacity: %.4f / %.0f units (%.1f%% utilized)', ...
            result.x_pv, params.x_pv_ub, x_pv_pct_used));
    constraint_analysis{end+1} = c;
    
    c = struct('description', 'Wind sizing upper bound', ...
        'is_binding', wt_binding, 'slack', params.x_wt_ub - result.x_wt, ...
        'dual_value', 0, ...
        'details', sprintf('Capacity: %.4f / %.0f units (%.1f%% utilized)', ...
            result.x_wt, params.x_wt_ub, x_wt_pct_used));
    constraint_analysis{end+1} = c;
    
    % 3. Battery constraints (if enabled)
    if isfield(result, 'E_bess')
        % Battery SOC limits
        soc_min_binding = any(result.e_stored(1:end-1) <= params.soc_min * result.E_bess * 1.01);
        soc_max_binding = any(result.e_stored(1:end-1) >= params.soc_max * result.E_bess * 0.99);
        
        c = struct('description', sprintf('Battery SOC limits [%.0f%%, %.0f%%]', 100*params.soc_min, 100*params.soc_max), ...
            'is_binding', soc_min_binding || soc_max_binding, 'slack', 0, ...
            'dual_value', 0, ...
            'details', sprintf('Min hours at limit: %d, Max hours at limit: %d', ...
                sum(result.e_stored(1:end-1) <= params.soc_min * result.E_bess * 1.01), ...
                sum(result.e_stored(1:end-1) >= params.soc_max * result.E_bess * 0.99)));
        constraint_analysis{end+1} = c;
        
        % Battery autonomy constraint
        if isfield(params, 'autonomy_days') && params.autonomy_days > 0
            autonomy_hrs = params.autonomy_days * 24;
            % Check if autonomy constraint makes battery bigger
            autonomy_binding = result.E_bess > (sum(data.P_load(1:autonomy_hrs)) * params.dt_h * 0.5);  % Rough check
            
            c = struct('description', sprintf('Battery autonomy (%.1f days without generation)', params.autonomy_days), ...
                'is_binding', autonomy_binding, 'slack', 0, ...
                'dual_value', 0, ...
                'details', sprintf('Battery capacity: %.4f GWh', result.E_bess / 1e9));
            constraint_analysis{end+1} = c;
        end
        
        % Curtailment limit (if enabled)
        if isfield(params, 'enable_curtailment') && params.enable_curtailment
            E_load = sum(data.P_load) * params.dt_h;
            curtail_limit = params.max_curtail_pct * E_load;
            curtail_pct_used = 100 * result.E_curt_annual / curtail_limit;
            curtail_binding = curtail_pct_used > 95;
            
            c = struct('description', sprintf('Maximum curtailment (%.1f%% of load)', params.max_curtail_pct*100), ...
                'is_binding', curtail_binding, 'slack', curtail_limit - result.E_curt_annual, ...
                'dual_value', 0, ...
                'details', sprintf('Annual curtailment: %.2e / %.2e Wh (%.1f%% of limit)', ...
                    result.E_curt_annual, curtail_limit, curtail_pct_used));
            constraint_analysis{end+1} = c;
        end
    end
    
    % 4. Backup constraints (if enabled)
    if isfield(result, 'P_backup')
        E_load = sum(data.P_load) * params.dt_h;
        backup_limit = params.backup_energy_pct * E_load;
        backup_pct_used = 100 * result.E_backup_annual / backup_limit;
        backup_binding = backup_pct_used > 95;
        
        c = struct('description', sprintf('Maximum backup generation (%.1f%% of annual load)', params.backup_energy_pct*100), ...
            'is_binding', backup_binding, 'slack', backup_limit - result.E_backup_annual, ...
            'dual_value', 0, ...
            'details', sprintf('Annual backup: %.2e / %.2e Wh (%.1f%% of limit)', ...
                result.E_backup_annual, backup_limit, backup_pct_used));
        constraint_analysis{end+1} = c;
    end
    
    % Convert to array
    dual_info.constraints = [constraint_analysis{:}];
    
    % Add energy balance insight
    E_load = sum(data.P_load) * params.dt_h;
    slack_pct = 100 * result.E_slack_annual / E_load;
    if slack_pct > 0.1
        summary = sprintf('%s  ⚠ Significant unmet demand (%.2f%%) suggests feasibility constraints.\n', summary, slack_pct);
    end
end

function str = conditionalStr(condition, if_true, if_false)
    if condition
        str = if_true;
    else
        str = if_false;
    end
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
