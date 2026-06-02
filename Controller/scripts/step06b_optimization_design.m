function step06b_optimization_design(data, pars)
    

    %% set data
    P_load = data.P_load;
    P_wind_unit = data.P_wind_unit;
    P_solar_unit = data.P_solar_unit;
    
    %% set parameters
    % General
    dt_h = pars.dt_h ;
    soc_min = pars.soc_min;
    soc_max = pars.soc_max;
    eta_ch = pars.eta_ch;
    eta_dis = pars.eta_dis;
    soc0 = pars.soc0;
    battery_c_rating = pars.battery_c_rating;

    % Upper bounds
    x_pv_ub = pars.x_pv_ub;
    x_wt_ub = pars.x_wt_ub;
    E_bess_ub = pars.E_bess_ub;     % Wh
    P_backup_ub = pars.P_backup_ub;    % W

    % Economics
    discount_rate = pars.discount_rate;
    project_life = pars.project_life;

    c_pv_unit_capex = pars.c_pv_unit_capex;
    c_pv_unit_fom_per_year = pars.c_pv_unit_fom_per_year; %fom = fixed O&M cost

    c_wt_unit_capex = pars.c_wt_unit_capex;
    c_wt_unit_fom_per_year = pars.c_wt_unit_fom_per_year;

    c_bess_E_capex_per_Wh = pars.c_bess_E_capex_per_Wh;
    c_bess_E_fom_per_Wh_yr = pars.c_bess_E_fom_per_Wh_yr;

    c_backup_capex_per_W = pars.c_backup_capex_per_W;
    c_backup_fom_per_W_yr = pars.c_backup_fom_per_W_yr;
    c_backup_vom_per_Wh = pars.c_backup_vom_per_Wh; %vom = variable O&M
    c_fuel_per_Wh_el = pars.c_fuel_per_Wh_el; %fuel cost for biomass plant

    CRF = discount_rate * (1 + discount_rate)^project_life / ...
            ((1 + discount_rate)^project_life - 1);

    % define important values for later use
    T = numel(P_load);
    E_load_ann = dt_h * sum(P_load); % in Wh

    
    %% -------------------- Decision variables --------------------
    x_pv     = sdpvar(1,1);      % PV inverters # (continuous for now)
    x_wt     = sdpvar(1,1);      % Wind turbines # (continuous for now)
    E_bess   = sdpvar(1,1);      % BESS energy capacity [Wh]
    P_bess = E_bess * battery_c_rating;
    P_backup = sdpvar(1,1);      % backup rated power [W]
    p_ch   = sdpvar(T,1);        % battery charging power [W]
    p_dis  = sdpvar(T,1);        % battery discharging power [W]
    p_bg   = sdpvar(T,1);        % backup dispatch [W]
    p_curt = sdpvar(T,1);        % curtailed power [W]
    e_stored      = sdpvar(T+1,1);      % stored battery energy [Wh]
    z = binvar(T,1);   % 1 = charge mode, 0 = discharge mode
    
    
    %% Objective
    Objective = ...
        CRF * (c_pv_unit_capex * x_pv + ...
               c_wt_unit_capex * x_wt + ...
               c_bess_E_capex_per_Wh * E_bess + ...
               c_backup_capex_per_W * P_backup) ...
        + (c_pv_unit_fom_per_year * x_pv + ...
           c_wt_unit_fom_per_year * x_wt + ...
           c_bess_E_fom_per_Wh_yr * E_bess + ...
           c_backup_fom_per_W_yr * P_backup) ...
        + (c_backup_vom_per_Wh + c_fuel_per_Wh_el) * sum(p_bg) * dt_h;
    
    %% Constraints

    Constraints = [];

    % variable bounds to converge faster & avoid infeasibility
    Constraints = [Constraints, ...
                   0 <= x_pv <= x_pv_ub, ...
                   0 <= x_wt <= x_wt_ub, ...
                   0 <= E_bess <= E_bess_ub, ...
                   0 <= P_backup <= P_backup_ub];

    % operational variables bounds  
    for t = 1:T
        Constraints = [Constraints, ...
                        0 <= p_ch(t)  <= P_bess, ...
                        0 <= p_dis(t) <= P_bess, ...
                        0 <= p_bg(t)  <= P_backup, ...
                        0 <= p_curt(t), ...
                        0 <= e_stored(t)];
    end

    % force charge - discharge exclusivity (Big-M logic)
    P_bess_ub = E_bess_ub * battery_c_rating;
    for t = 1:T
        Constraints = [Constraints, ...
            p_ch(t)  <= P_bess_ub * z(t), ...
            p_dis(t) <= P_bess_ub * (1 - z(t))];
    end

    % power balance constraint
    for t = 1:T
        Constraints = [Constraints, ...
                        x_pv * P_solar_unit(t) + ...
                        x_wt * P_wind_unit(t) + ...
                        p_bg(t) + p_dis(t) == ...
                        P_load(t) + p_ch(t) + p_curt(t)];
    end

    % 50% by each generator constraint 
    % (or if this generation is less costly than back up they will always operate without backup

        Constraints = [Constraints, ...
                        x_pv * sum(P_solar_unit) * dt_h == 0.5 * E_load_ann, ...
                        x_wt * sum(P_wind_unit) * dt_h == 0.5 * E_load_ann];

    % Battery energy progression

    for t = 1:T
        Constraints = [Constraints, ...
        e_stored(t+1) == e_stored(t) + (eta_ch * p_ch(t) - p_dis(t)/eta_dis) * dt_h];
    end

    % Initial SoC 
    Constraints = [Constraints, e_stored(1) == soc0 * E_bess];

    % SoC min/max bounds 
    for t = 1:T+1
        Constraints = [Constraints, soc_min * E_bess <= e_stored(t) <= soc_max * E_bess];
    end

    % Backup generation power limit
    for t = 1:T
        Constraints = [Constraints, p_bg(t)  <= P_backup];
    end

    % Curtailment limited by available RES at time
    for t = 1:T
        Constraints = [Constraints, ...
            p_curt(t) <= x_pv * P_solar_unit(t) + x_wt * P_wind_unit(t)];
    end    

    % annual curtailment max
    Constraints = [Constraints, sum(p_curt) * dt_h <= 0.10 * E_load_ann];

    % annual backup-energy max 
    Constraints = [Constraints, sum(p_bg) * dt_h <= 0.20 * E_load_ann];
    
    % two-day autonomy 
    Constraints = [Constraints, ...
        (soc_max - soc_min) * E_bess >= 2 * E_load_ann / 365];
    
    % SoC(0) = SoC(end) + tolerance
    tol = 10e3;
    Constraints = [Constraints, e_stored(1) - tol <= e_stored(T+1) <= e_stored(1) + tol];

    %% Solve optimization problem

    ops = sdpsettings('solver','gurobi','verbose',1);
    diagnostics = optimize(Constraints, Objective, ops);

    if diagnostics.problem == 0
        disp('Solved successfully');
    
        x_pv_opt = value(x_pv);
        x_wt_opt = value(x_wt);
        E_bess_opt = value(E_bess);
        P_backup_opt = value(P_backup);
    
        p_ch_opt   = value(p_ch);
        p_dis_opt  = value(p_dis);
        p_bg_opt   = value(p_bg);
        p_curt_opt = value(p_curt);
        e_stored_opt = value(e_stored);
    
        annual_cost = value(Objective);
        LCOE = annual_cost / E_load_ann;
    
        fprintf('Inverters # = %.4f\n', x_pv_opt);
        fprintf('Wind turbines # = %.4f\n', x_wt_opt);
        fprintf('E_bess = %.4f GWh\n', E_bess_opt / 1e9);
        fprintf('E_pv (%%) = %.4f %% \n', x_pv_opt * sum(P_solar_unit) * dt_h * 100 / E_load_ann);
        fprintf('E_wind (%%) = %.4f %% \n', x_wt_opt * sum(P_wind_unit) * dt_h * 100 / E_load_ann);
        fprintf('P_backup = %.4f GW\n', P_backup_opt / 1e9);
        fprintf('E_backup (%%) = %.4f %% \n', (sum(p_bg_opt) * dt_h * 100) / E_load_ann);
        fprintf('E_curtailed (%%) = %.4f %% \n', (sum(p_curt_opt) * dt_h * 100) / E_load_ann);
        % fprintf('P_curtailed # = %.4f\n', sum(p_curt_opt));
        fprintf('LCOE = %.6f cost-unit/Wh\n', LCOE);
    else
        disp('Solver failed');
        disp(diagnostics.info);
    end

    
    %% diagnostic figures

    if diagnostics.problem == 0 
        
        idx = 1000:1168; % example one week
    
        p_pv_opt = x_pv_opt * P_solar_unit;
        p_wt_opt = x_wt_opt * P_wind_unit;
        
        figure;
        hold on; grid on;
        plot(P_load(idx), 'k', 'LineWidth', 1.5);
        plot(p_pv_opt(idx), 'LineWidth', 1.2);
        plot(p_wt_opt(idx), 'LineWidth', 1.2);
        plot(p_bg_opt(idx), 'LineWidth', 1.2);
        plot(p_dis_opt(idx), 'LineWidth', 1.2);
        plot(-p_ch_opt(idx), 'LineWidth', 1.2);
        plot(-p_curt_opt(idx), 'LineWidth', 1.2);
        legend('Load','PV','Wind','Backup','Battery dis','Battery ch','Curtailment');
        title('Dispatch over selected time window');
        xlabel('Hour');
        ylabel('W');
    
        soc_opt = e_stored_opt / value(E_bess);
        
        figure;
        plot(soc_opt, 'LineWidth', 1.2); grid on;
        title('Battery state of charge');
        xlabel('Time step');
        ylabel('SoC [-]');
    
        p_ren_opt = p_pv_opt + p_wt_opt;
    
        figure;
        plot(p_ren_opt, 'LineWidth', 1.1); hold on; grid on;
        plot(P_load, 'k', 'LineWidth', 1.1);
        legend('Renewable available','Load');
        title('Renewable generation vs load');
        xlabel('Time step');
        ylabel('W');
    
        figure;
        plot(p_bg_opt, 'LineWidth', 1.2); grid on;
        title('Backup dispatch');
        xlabel('Time step');
        ylabel('W');
    
        figure;
        plot(p_curt_opt, 'LineWidth', 1.2); grid on;
        title('Curtailment');
        xlabel('Time step');
        ylabel('W');
    end
end