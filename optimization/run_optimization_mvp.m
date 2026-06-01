clc; clear; close all; warning("off");

%% Resolve project root and add paths
projectRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(projectRoot,"scripts"));

%% Load electricity demand
opts = spreadsheetImportOptions("NumVariables", 11);
opts.Sheet = "Y1 Load Profile 3";
opts.DataRange = "A2:K26281";
opts.VariableNames = ["Year", "Month", "Day", "Hour", "MonthlyLoad", "TotalDaysInThatMonth", "DailyEnergy", "HourlyConsumptionFactor", "FinalLoadProfileKW", "BlackoutProfile", "EffectiveLoad"];
opts.VariableTypes = ["double", "double", "double", "double", "double", "double", "double", "double", "double", "double", "double"];
elec_tbl = readtable("C:\Users\alexn\Documents\GitHub\PVS-Group16\optimization\Year 2026 Load Calculation Fixed.xlsx", opts, "UseExcel", false);
P_load = elec_tbl{:, 11}; % hourly load in kW

%% Load the solar generation profiles
module=2; % 1 for longi, 2 for aiko
south_tbl = readtable('generation_profile_south.xlsx', 'Sheet', 'Sheet1');
north_tbl = readtable('generation_profile_north.xlsx', 'Sheet', 'Sheet1');
if module == 1
    Solar1 = south_tbl{:,2};
    Solar2 = north_tbl{:,2};
else
    Solar1 = south_tbl{:,3};
    Solar2 = north_tbl{:,3};
end

%% Load blackout profile
P_blackout = elec_tbl{:, 10}; % uses the 3-year range

%% Expand to 3-year horizon by repeating the 1-year profiles
years = 3;
Solar1 = repmat(Solar1, years, 1);
Solar2 = repmat(Solar2, years, 1);

%% Detect start of blackout blocks (one event per contiguous blackout)
blackout_event_start = zeros(size(P_blackout));
if ~isempty(P_blackout)
    blackout_event_start(1) = P_blackout(1) > 0;
    blackout_event_start(2:end) = (P_blackout(2:end) > 0) & (P_blackout(1:end-1) == 0);
end

%% Optimization
% set parameters
params = struct();

% Technical
params.dt_h = 1.0;
if module == 1
    params.x_pv_ub = 12; % max 12 LONGi panels on each side of the roof
    params.x_pv2_ub = 12;
else
    params.x_pv_ub = 16; % max 16 AIKO panels on each side of the roof
    params.x_pv2_ub = 16;
end

params.battery_c_rating = 1;             % C-rating: 1 h^-1 means 1hr discharge
params.eta_ch = sqrt(0.92);                 % Charging efficiency (round-trip loss: 0.92)
params.eta_dis = sqrt(0.92);
params.batt_deg_per_cycle = 0.0002;         % 0.02% per cycle (event)
params.soc_min = 0.15;                       % Min state-of-charge (15%)
params.soc_max = 0.95;                       % Max state-of-charge (95%)
params.soc0 = 0.95;                         % Initial SOC
params.soc_tolerance = 45;                  % Cyclic tolerance (kWh)
params.E_bess_ub = 150;                     % Battery energy upper bound (kWh)
params.E_bess_lb = 0;
params.soc_solar_allow = 0.95;
params.soc_big_m = params.E_bess_ub;        % safe scale


% Economics
params.discount_rate = 0;
params.project_life = 3;

if module == 1
    params.c_pv_unit_capex = 950; % cost per LONGi panel
else
    params.c_pv_unit_capex = 800; % cost per AIKO panel
end
params.c_pv_unit_fom_per_year = 0;      % /year

params.c_bess_E_capex_per_kWh = 193.36;         % Battery capex (EUR/kWh)
params.c_bess_E_fom_per_kWh_yr = 0;          % Battery FOM (EUR/kWh/year)

params.slack_hourly_penalty_eur = 112.5; % compensation to clients
params.slack_big_m = max(P_load) + 1; % safe big-M (kW)


params.grid_price_eur_per_kwh = 0.2;
params.grid_big_m = 1e6;  % or set to max expected import

% Build time-varying capacity factor (for e_stored indices 1..T+1)
T = numel(P_load);
cycles_at_e = zeros(T+1, 1);
cycles_at_e(2:end) = cumsum(blackout_event_start);
batt_cap_factor = 1 - params.batt_deg_per_cycle * cycles_at_e;
batt_cap_factor = max(batt_cap_factor, 0); % safety clamp

data = struct( ...
    'P_load', P_load, ...
    'P_solar_unit', Solar1, ...
    'P_solar_unit_2', Solar2, ...
    'P_blackout', P_blackout, ...
    'blackout_event_start', blackout_event_start, ...
    'batt_cap_factor', batt_cap_factor ...
);

fprintf('Data check before optimization:\n');
if module == 1
    fprintf('LONGi module');
else
    fprintf('AIKO module');
end
fprintf('  P_load: min=%.0f, max=%.0f\n', min(data.P_load), max(data.P_load));
fprintf('  P_solar_unit: min=%.0f, max=%.0f\n', min(data.P_solar_unit), max(data.P_solar_unit));
fprintf('  P_solar_unit_2: min=%.0f, max=%.0f\n', min(data.P_solar_unit_2), max(data.P_solar_unit_2));
fprintf('  Max possible gen: %.0f kW\n', ...
    params.x_pv_ub*max(data.P_solar_unit) + params.x_pv2_ub*max(data.P_solar_unit_2));
fprintf('  Peak load: %.0f kW\n', max(data.P_load));

fprintf('Building MVP optimization problem...\n')
fprintf('\n')

% Setup constraint and objective registries
constraint_registry = {@bind_power_balance, ...
        @bind_battery_dynamics, ...
        @bind_battery_soc, ...
        @bind_battery_exclusivity, ...
        @bind_curtailment, ...
        @bind_grid_charging, ...
        @bind_grid_availability, ...
        @bind_solar_to_load_soc,
        };

% Select objective based on objective_type
objective_registry = {@default_objective, @cost_slack, @cost_battery, @cost_grid};


use_saved_result = true; % set false to run optimization

results_path = fullfile(projectRoot, 'results', 'longi_results.mat');

if use_saved_result && isfile(results_path)
    loaded = load(results_path);
    result_50 = loaded.result_50;
    params = loaded.params;
    data = loaded.data;
else
    result_50 = build_problem(data, params, constraint_registry, objective_registry);
    % Save optimization outputs for reuse
    results_dir = fullfile(projectRoot, 'results');
    if ~exist(results_dir, 'dir')
        mkdir(results_dir);
    end
    save(results_path, 'result_50', 'params', 'data');
end

%% Visualization
fprintf('\nGenerating visualization...\n')


% ====== COST AND EMISSIONS BREAKDOWNS ======
if ~strcmp(result_50.status, 'infeasible or error')
    fprintf('\n========== OPTIMIZATION RESULTS ==========\n');
    fprintf('Status: %s\n', result_50.status);

    % System sizing
    fprintf('\n--- SYSTEM SIZING ---\n');
    fprintf('  South-facing PV:  %.2f panels\n', result_50.x_pv);
    fprintf('  North-facing PV:  %.2f panels\n', result_50.x_pv2);
    fprintf('  Total PV:         %.2f panels\n', result_50.x_pv + result_50.x_pv2);
    fprintf('  Battery:          %.2f kWh\n', result_50.E_bess);
    fprintf('  Battery power (C-rate %.2f h^-1): %.2f kW\n', ...
        params.battery_c_rating, result_50.E_bess * params.battery_c_rating);

    % Degradation summary
    blackout_event_count = sum(data.blackout_event_start);
    fprintf('  Blackout events:  %.0f\n', blackout_event_count);
    fprintf('  Battery capacity fade: %.2f%%\n', (1 - data.batt_cap_factor(end)) * 100);
    fprintf('  End-of-horizon usable capacity: %.2f kWh\n', result_50.E_bess * data.batt_cap_factor(end));

    % Energy balance over horizon
    E_load_horizon = params.dt_h * sum(data.P_load);
    E_pv1_horizon = result_50.x_pv * sum(data.P_solar_unit) * params.dt_h;
    E_pv2_horizon = result_50.x_pv2 * sum(data.P_solar_unit_2) * params.dt_h;
    E_pv_horizon = E_pv1_horizon + E_pv2_horizon;
    E_batt_horizon = params.dt_h * sum(result_50.p_dis);
    E_curt_horizon = params.dt_h * sum(result_50.p_curt);
    E_grid_horizon = params.dt_h * sum(result_50.p_grid);
    E_slack_horizon = params.dt_h * sum(result_50.slack);

    fprintf('\n--- 3-YEAR ENERGY BALANCE ---\n');
    fprintf('  Total demand:        %.2f kWh\n', E_load_horizon);
    fprintf('  PV generation (South): %.2f kWh (%.1f%%)\n', ...
        E_pv1_horizon, 100 * E_pv1_horizon / E_load_horizon);
    fprintf('  PV generation (North): %.2f kWh (%.1f%%)\n', ...
        E_pv2_horizon, 100 * E_pv2_horizon / E_load_horizon);
    fprintf('  Total PV generation: %.2f kWh (%.1f%%)\n', ...
        E_pv_horizon, 100 * E_pv_horizon / E_load_horizon);
    fprintf('  Battery dispatch:    %.2f kWh (%.1f%% of demand)\n', ...
        E_batt_horizon, 100 * E_batt_horizon / E_load_horizon);
    fprintf('  Curtailment:         %.2f kWh (%.1f%% of generation)\n', ...
        E_curt_horizon, 100 * E_curt_horizon / max(E_pv_horizon, eps));
    fprintf('  Grid import:         %.2f kWh (%.1f%% of demand)\n', ...
        E_grid_horizon, 100 * E_grid_horizon / E_load_horizon);
    fprintf('  Unmet demand (slack):%.2f kWh (%.1f%%)\n', ...
        E_slack_horizon, 100 * E_slack_horizon / E_load_horizon);
    fprintf('  Hours with unmet demand: %.0f hours\n', sum(result_50.u_slack));

    % Cost breakdown (3-year totals)
    cost_pv1_total = params.c_pv_unit_capex * result_50.x_pv + ...
                     params.c_pv_unit_fom_per_year * params.project_life * result_50.x_pv;
    cost_pv2_total = params.c_pv_unit_capex * result_50.x_pv2 + ...
                     params.c_pv_unit_fom_per_year * params.project_life * result_50.x_pv2;
    cost_pv_total = cost_pv1_total + cost_pv2_total;

    cost_batt_total = params.c_bess_E_capex_per_kWh * result_50.E_bess + ...
                      params.c_bess_E_fom_per_kWh_yr * params.project_life * result_50.E_bess;

    cost_grid_total = params.grid_price_eur_per_kwh * E_grid_horizon;
    cost_slack_total = params.slack_hourly_penalty_eur * sum(result_50.u_slack);

    total_cost = cost_pv_total + cost_batt_total + cost_grid_total + cost_slack_total;
    energy_served_kwh = E_load_horizon - E_slack_horizon;
    lcoe_eur_per_kwh = (cost_pv_total + cost_batt_total + cost_grid_total) / energy_served_kwh;

    fprintf('\n--- COST BREAKDOWN (3-YEAR TOTAL, EUR) ---\n');
    fprintf('  South-facing PV:  %.2f\n', cost_pv1_total);
    fprintf('  North-facing PV:  %.2f\n', cost_pv2_total);
    fprintf('  Battery:          %.2f\n', cost_batt_total);
    fprintf('  Grid:             %.2f\n', cost_grid_total);
    fprintf('  Slack penalty:    %.2f\n', cost_slack_total);
    fprintf('  TOTAL:            %.2f\n', total_cost);
    fprintf('  LCOE:             %.4f EUR/kWh\n', lcoe_eur_per_kwh);
    
    % ====== PIE CHARTS ======
    % Cost pie chart
    fig_cost = figure('Name', 'Cost Breakdown', 'NumberTitle', 'off', 'Position', [100 100 800 500], 'WindowStyle', 'docked');
    cost_labels = {'South PV', 'North PV', 'Battery', 'Grid', 'Compensation (Slack)'};
    cost_values = [cost_pv1_total, cost_pv2_total, cost_batt_total, cost_grid_total, cost_slack_total];

    nonzero_mask = cost_values > 0;
    cost_labels = cost_labels(nonzero_mask);
    cost_values = cost_values(nonzero_mask);

    pie(cost_values);
    legend(cost_labels, 'Location', 'bestoutside');
    title(sprintf('Cost Breakdown \nTotal: %.2f EUR', total_cost));
end

% ====== VISUALIZATIONS======
    
% Prepare supply and demand timeseries
T = numel(data.P_load);
supply_components = struct();
demand_components = struct();

% Current generation sources
supply_components.solar_1 = result_50.x_pv * data.P_solar_unit;      % South PV (kW)
supply_components.solar_2 = result_50.x_pv2 * data.P_solar_unit_2;   % North PV (kW)
supply_components.solar = supply_components.solar_1 + supply_components.solar_2;  % Total (kW)

% Demand breakdown
demand_components.load = data.P_load;  % kW

% Handle battery if enabled
supply_components.batt_dis = result_50.p_dis;  % Battery discharge in kW
demand_components.batt_ch = result_50.p_ch;  % Battery charge in kW

% Add grid import to supply components
supply_components.grid = result_50.p_grid;  % Grid import in kW

% Handle slack
supply_components.slack = result_50.slack;  % kW

% Update met demand to include grid
total_met_demand = supply_components.solar + supply_components.batt_dis + supply_components.grid;
total_unmet_demand = supply_components.slack;

% Time arrays
hours_all = 0:T-1;
hours_week = 0:min(168, T-1);

% Calculate excess generation
total_generation = supply_components.solar; % Grid is not generation
excess_generation = max(0, total_generation - demand_components.load - demand_components.batt_ch);
supply_components.excess = excess_generation;

% Figure position: center of screen (1920x1080)
center_x = (1920 - 1000) / 2;  % 560
center_y = (1080 - 800) / 2;  % 240
        
titleSuffix = sprintf('MVP System Sizing: S-PV=%.0f panels, N-PV=%.0f panels, Batt=%.0f kWh', ...
    result_50.x_pv, result_50.x_pv2, result_50.E_bess);

% --- HORIZON SUPPLY-DEMAND BALANCE (Cumulative Stacked Bar Chart) ---
% Aggregate hourly data by week
weeks_in_year = ceil(T / 168);
weekly_demand = zeros(weeks_in_year, 1);
weekly_solar_1 = zeros(weeks_in_year, 1);
weekly_solar_2 = zeros(weeks_in_year, 1);
weekly_batt_dis = zeros(weeks_in_year, 1);
weekly_batt_ch = zeros(weeks_in_year, 1);
weekly_slack = zeros(weeks_in_year, 1);
weekly_grid = zeros(weeks_in_year, 1);

for w = 1:weeks_in_year
    start_idx = (w-1) * 168 + 1;
    end_idx = min(w * 168, T);
    weekly_demand(w) = sum(demand_components.load(start_idx:end_idx));
    weekly_solar_1(w) = sum(supply_components.solar_1(start_idx:end_idx));
    weekly_solar_2(w) = sum(supply_components.solar_2(start_idx:end_idx));
    weekly_batt_dis(w) = sum(supply_components.batt_dis(start_idx:end_idx));
    weekly_batt_ch(w) = sum(demand_components.batt_ch(start_idx:end_idx));
    weekly_slack(w) = sum(supply_components.slack(start_idx:end_idx));
    weekly_grid(w) = sum(supply_components.grid(start_idx:end_idx));
end

fig1 = figure('Name', 'Weekly Supply-Demand Balance (Cumulative)', 'NumberTitle', 'off', 'Position', [center_x center_y 1000 600], 'WindowStyle', 'docked');
hold on;

% Create stacked bar chart showing power balance (kWh)
% Positive side: generation sources
% Negative side: battery charging demand
week_numbers = 1:weeks_in_year;
weekly_supply = [weekly_solar_1, weekly_solar_2, weekly_batt_dis, weekly_grid];  % kWh
weekly_demand_components = [-weekly_batt_ch, weekly_slack];  % kWh

% Plot supply sources (positive)
h_Supply = bar(week_numbers, weekly_supply, 'stacked', 'EdgeColor', 'none');

h_Supply(1).FaceColor = '#FDB462';  % Solar South
h_Supply(2).FaceColor = '#B3DE69';  % Solar North
h_Supply(3).FaceColor = '#8DD3C7';  % Battery Discharge
h_Supply(4).FaceColor = '#80B1D3';  % Grid

% Plot demand components on same bars (battery charge as negative, slack as positive continuation)
h_Demand = bar(week_numbers, weekly_demand_components, 'stacked', 'EdgeColor', 'none');
h_Demand(1).FaceColor = '#FC8d62';  % Battery Charge (reddish, different from discharge)
h_Demand(2).FaceColor = '#984EA3';  % Unmet (Slack) - purple, distinct from battery discharge

% Overlay weekly load demand as a line (kWh)
hold on;
h_line = plot(week_numbers, weekly_demand, 'ko-', 'LineWidth', 2, 'MarkerSize', 5, 'DisplayName', 'Weekly Load');

% Add zero reference line (exclude from legend)
yline(0, 'k-', 'LineWidth', 0.5, 'HandleVisibility', 'off');

hold off;
xlabel('Week of Horizon'); 
ylabel('Energy (kWh)');
title(sprintf('Weekly Power Balance - Cumulative\n%s', titleSuffix));
legend([h_Supply(1), h_Supply(2), h_Supply(3), h_Supply(4), h_Demand(1), h_Demand(2), h_line], ...
    {'Solar (South)', 'Solar (North)', 'Battery Discharge', 'Grid', 'Battery Charge', 'Unmet (Slack)', 'Weekly Load'}, ...
    'Location', 'best');
grid on;
xticks(1:2:weeks_in_year);

% --- WEEKLY DISPATCH DETAIL (Renewables, Battery, Curtailment, Slack) ---
fig5 = figure('Name', 'Weekly Dispatch Detail', 'NumberTitle', 'off', ...
              'Position', [center_x center_y 1000 600], 'WindowStyle', 'docked');

hours_week_range = 1:numel(hours_week);

% Use gated PV if available; fall back to ungated PV (split by array)
if isfield(result_50, 'x_pv_gate_1') && ~isempty(result_50.x_pv_gate_1) && ...
        isfield(result_50, 'x_pv_gate_2') && ~isempty(result_50.x_pv_gate_2)
    solar1_to_load = (result_50.x_pv_gate_1 .* data.P_solar_unit);   % South
    solar2_to_load = (result_50.x_pv_gate_2 .* data.P_solar_unit_2); % North
else
    solar1_to_load = supply_components.solar_1;
    solar2_to_load = supply_components.solar_2;
end

batt_dis = result_50.p_dis;  % kW
grid_imp = result_50.p_grid; % kW
slack_mw = result_50.slack;  % kW
batt_ch = result_50.p_ch;    % kW
load_mw = data.P_load;       % kW

hold on;

% Stacked positive supply (solar1, solar2, batt, grid, slack)
supply_stack = [solar1_to_load(hours_week_range), ...
                solar2_to_load(hours_week_range), ...
                batt_dis(hours_week_range), ...
                grid_imp(hours_week_range), ...
                slack_mw(hours_week_range)];
h_supply = bar(hours_week_range, supply_stack, 'stacked', 'EdgeColor', 'none');

h_supply(1).FaceColor = '#FDB462';  % South-facing solar
h_supply(2).FaceColor = '#B3DE69';  % North-facing solar
h_supply(3).FaceColor = '#8DD3C7';  % Battery Discharge
h_supply(4).FaceColor = '#80B1D3';  % Grid
h_supply(5).FaceColor = '#FB8072';  % Slack

% Battery charge as negative bars
h_ch = bar(hours_week_range, -batt_ch(hours_week_range), 'FaceColor', '#FC8D62', ...
           'EdgeColor', 'none', 'DisplayName', 'Battery Charge');

% Load line
plot(hours_week_range, load_mw(hours_week_range), 'k-', 'LineWidth', 1.5, ...
     'DisplayName', 'Load');

% Overlay slack hours as markers on the load line
if isfield(result_50, 'u_slack') && ~isempty(result_50.u_slack)
    slack_idx = hours_week_range(result_50.u_slack(hours_week_range) > 0);
    if ~isempty(slack_idx)
        plot(slack_idx, load_mw(slack_idx), 'rx', 'MarkerSize', 6, ...
             'LineWidth', 1.2, 'DisplayName', 'Slack hours');
    end
end

% Curtailment/Excess as a line
plot(hours_week_range, supply_components.excess(hours_week_range), 'mo-', ...
     'LineWidth', 1.2, 'MarkerSize', 3, 'DisplayName', 'Curtailment');

hold off;
xlabel('Hour of Week 1');
ylabel('Power (kW)');
title(sprintf('First Week Dispatch Detail\n%s', titleSuffix));
legend([h_supply(1), h_supply(2), h_supply(3), h_supply(4), h_supply(5), h_ch, h_line], ...
    {'Solar (South)', 'Solar (North)', 'Battery Discharge', 'Grid', 'Unmet (Slack)', 'Battery Charge', 'Load'}, ...
    'Location', 'best');
grid on;
yline(0, 'k--', 'LineWidth', 0.5);

% --- 3-year dispatch ---
fig5b = figure('Name', '3-year Dispatch', 'NumberTitle', 'off', ...
               'Position', [center_x center_y 1000 600], 'WindowStyle', 'docked');

hours_all_range = 1:T;

% Use gated PV if available; fall back to ungated PV (split by array)
if isfield(result_50, 'x_pv_gate_1') && ~isempty(result_50.x_pv_gate_1) && ...
        isfield(result_50, 'x_pv_gate_2') && ~isempty(result_50.x_pv_gate_2)
    solar1_to_load_all = (result_50.x_pv_gate_1 .* data.P_solar_unit);   % South
    solar2_to_load_all = (result_50.x_pv_gate_2 .* data.P_solar_unit_2); % North
else
    solar1_to_load_all = supply_components.solar_1;
    solar2_to_load_all = supply_components.solar_2;
end

batt_dis_all = result_50.p_dis;
grid_imp_all = result_50.p_grid;
slack_mw_all = result_50.slack;
batt_ch_all = result_50.p_ch;
load_mw_all = data.P_load;

hold on;

% Stacked positive supply (solar1, solar2, batt, grid, slack)
supply_stack_all = [solar1_to_load_all(hours_all_range), ...
                    solar2_to_load_all(hours_all_range), ...
                    batt_dis_all(hours_all_range), ...
                    grid_imp_all(hours_all_range), ...
                    slack_mw_all(hours_all_range)];
h_supply_all = bar(hours_all_range, supply_stack_all, 'stacked', 'EdgeColor', 'none');

h_supply_all(1).FaceColor = '#FDB462';  % South-facing solar
h_supply_all(2).FaceColor = '#B3DE69';  % North-facing solar
h_supply_all(3).FaceColor = '#8DD3C7';  % Battery Discharge
h_supply_all(4).FaceColor = '#80B1D3';  % Grid
h_supply_all(5).FaceColor = '#FB8072';  % Slack

% Battery charge as negative bars
h_ch_all = bar(hours_all_range, -batt_ch_all(hours_all_range), 'FaceColor', '#FC8D62', ...
               'EdgeColor', 'none', 'DisplayName', 'Battery Charge');

% Load line
h_line_all = plot(hours_all_range, load_mw_all(hours_all_range), 'k-', 'LineWidth', 1.5, ...
                  'DisplayName', 'Load');

% Overlay slack hours as markers on the load line
if isfield(result_50, 'u_slack') && ~isempty(result_50.u_slack)
    slack_idx_all = hours_all_range(result_50.u_slack(hours_all_range) > 0);
    if ~isempty(slack_idx_all)
        plot(slack_idx_all, load_mw_all(slack_idx_all), 'rx', 'MarkerSize', 6, ...
             'LineWidth', 1.2, 'DisplayName', 'Slack hours');
    end
end

% Curtailment/Excess as a line
plot(hours_all_range, supply_components.excess(hours_all_range), 'mo-', ...
     'LineWidth', 1.2, 'MarkerSize', 3, 'DisplayName', 'Curtailment');

hold off;
xlabel('Hour of Year');
ylabel('Power (kW)');
title(sprintf('3-year Dispatch\n%s', titleSuffix));
legend([h_supply_all(1), h_supply_all(2), h_supply_all(3), h_supply_all(4), h_supply_all(5), h_ch_all, h_line_all], ...
    {'Solar (South)', 'Solar (North)', 'Battery Discharge', 'Grid', 'Unmet (Slack)', 'Battery Charge', 'Load'}, ...
    'Location', 'best');
grid on;
yline(0, 'k--', 'LineWidth', 0.5);


% --- HORIZON BATTERY STATE OF CHARGE ---
fig6 = figure('Name', 'Horizon Battery State of Charge', 'NumberTitle', 'off', ...
              'Position', [center_x center_y 800 600], 'WindowStyle', 'docked');
soc_annual = result_50.e_stored / result_50.E_bess;
plot(0:T, soc_annual, 'LineWidth', 1.5, 'Color', '#0066FF');
hold on;

soc_min_t = params.soc_min .* data.batt_cap_factor;
soc_max_t = params.soc_max .* data.batt_cap_factor;
plot(0:T, soc_min_t, 'r--', 'LineWidth', 1.5, ...
     'DisplayName', sprintf('Min SOC (%.0f%%)', params.soc_min*100));
plot(0:T, soc_max_t, 'g--', 'LineWidth', 1.5, ...
     'DisplayName', sprintf('Max SOC (%.0f%%)', params.soc_max*100));

hold off;
xlabel('Hour of Horizon');
ylabel('State of Charge (SOC)');
title(sprintf('Horizon Battery State of Charge\n%s', titleSuffix));
legend('Location', 'best');
grid on;
ylim([0 1]);
xlim([0 T+100]);

