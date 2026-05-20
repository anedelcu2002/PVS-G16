clc; clear; close all; warning("off");

%% Resolve project root and add paths
projectRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(projectRoot,"scripts"));

%% Load electricity demand
elec_tbl = readtable('Year 2026 Load Calculation Fixed.xlsx','Sheet','Y1 Load Profile 3');
P_load = elec_tbl{:, 11}; % hourly load in kW

%% Load the initial solar profile
solar_tbl = readtable('renewables_ninja_1_kw.csv');
Solar1 = solar_tbl.Var3; % hourly solar generation in kW
Solar2 = solar_tbl.Var3.*0.9; 

%% Load blackout profile
blackout_tbl = readtable('Year 2026 Load Calculation Fixed.xlsx','Sheet','Y1 Load Profile 3');
P_blackout = blackout_tbl{:, 10}; % hourly blackout indicator (1 if blackout, 0 otherwise)

%% Optimization
data = struct( ...
    'P_load', P_load, ...
    'P_solar_unit', Solar1, ...
    'P_solar_unit_2', Solar2, ...
    'P_blackout', P_blackout ...
);

% set parameters
params = struct();

% ============== SYSTEM TOGGLES ==============
params.objective_type = 'economic';  % Choose: 'economic' (cost minimization) or 'environmental' (GHG minimization)
% ================================================

% Technical
params.dt_h = 1.0;
params.x_pv_ub = 20; % max kWp
params.x_pv2_ub = 20; % max kWp
params.battery_c_rating = 0.25;             % C-rating: 0.25 h^-1 means 4hr discharge
params.eta_ch = sqrt(0.93);                 % Charging efficiency (round-trip loss: 0.93)
params.eta_dis = sqrt(0.93);                % Discharging efficiency (same as charge)
params.soc_min = 0.0;                       % Min state-of-charge (10%)
params.soc_max = 1.0;                       % Max state-of-charge (90%)
params.soc0 = 0.95;                         % Initial SOC
params.soc_tolerance = 10;                  % Cyclic tolerance (kWh)
params.E_bess_ub = 100;                     % Battery energy upper bound (kWh)
params.E_bess_lb = 0;
params.soc_solar_allow = 0.95;
params.soc_big_m = params.E_bess_ub;        % safe scale


% Economics
params.discount_rate = 0;
params.project_life = 3;
params.c_pv_unit_capex = 900;           % /kWp
params.c_pv_unit_fom_per_year = 5;      % /kWp/year
params.c_bess_E_capex_per_kWh = 250;         % Battery capex (EUR/kWh)
params.c_bess_E_fom_per_kWh_yr = params.c_bess_E_capex_per_kWh*0.04;          % Battery FOM (EUR/kWh/year)

params.slack_hourly_penalty_eur = 112.5;
params.slack_big_m = max(P_load) + 1; % safe big-M (kW)


params.grid_price_eur_per_kwh = 0.2;
params.grid_big_m = 1e6;  % or set to max expected import
% ==============================================================


% ============== LIFECYCLE GHG PARAMETERS (EMBEDDED EMISSIONS) ===============
% All GHG intensities in kg CO2-eq per unit
params.ghg_intensity_pv_per_unit = 5;         % kg CO2-eq per kWp
params.ghg_intensity_batt_per_kWh = 0.09;         % kg CO2-eq per kWh of battery storage


fprintf('Data check before optimization:\n');
fprintf('  P_load: min=%.2e, max=%.2e\n', min(data.P_load), max(data.P_load));
fprintf('  P_solar_unit: min=%.2e, max=%.2e\n', min(data.P_solar_unit), max(data.P_solar_unit));
fprintf('  P_solar_unit_2: min=%.2e, max=%.2e\n', min(data.P_solar_unit_2), max(data.P_solar_unit_2));
fprintf('  Max possible gen: %.2e kW\n', ...
    params.x_pv_ub*max(data.P_solar_unit) + params.x_pv2_ub*max(data.P_solar_unit_2));
fprintf('  Peak load: %.2e kW\n', max(data.P_load));

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
if strcmp(params.objective_type, 'economic')
    % Economic optimization: minimize cost
    objective_registry = {@default_objective, @cost_slack, @cost_battery, @cost_grid};
elseif strcmp(params.objective_type, 'environmental')
    % Environmental optimization: minimize GHG emissions (embedded only)
    objective_registry = {@cost_ghg_lifecycle, @cost_slack};
    % Note: battery GHG are already included in cost_ghg_lifecycle
else
    error('Unknown objective_type: %s. Choose ''economic'' or ''environmental''.', params.objective_type);
end

result_50 = build_problem(data, params, constraint_registry, objective_registry);

%% Visualization
fprintf('\nGenerating visualization...\n')


% ====== COST AND EMISSIONS BREAKDOWNS ======
if ~strcmp(result_50.status, 'infeasible or error')
    % --- COST BREAKDOWN ---
    cost_breakdown = struct();
    
    % PV costs (both arrays)
    CRF = compute_crf(params.discount_rate, params.project_life);
    cost_breakdown.pv_1 = CRF * params.c_pv_unit_capex * result_50.x_pv + ...
                          params.c_pv_unit_fom_per_year * result_50.x_pv;
    cost_breakdown.pv_2 = CRF * params.c_pv_unit_capex * result_50.x_pv2 + ...
                          params.c_pv_unit_fom_per_year * result_50.x_pv2;
    cost_breakdown.pv = cost_breakdown.pv_1 + cost_breakdown.pv_2;

    grid_energy_kwh = sum(result_50.p_grid) * params.dt_h;
    cost_breakdown.grid = params.grid_price_eur_per_kwh * grid_energy_kwh;
    
    % Battery cost
    cost_breakdown.batt = CRF * params.c_bess_E_capex_per_kWh * result_50.E_bess + ...
                            params.c_bess_E_fom_per_kWh_yr * result_50.E_bess;
    
    cost_breakdown.total = cost_breakdown.pv + cost_breakdown.batt + cost_breakdown.grid;
    cost_breakdown.slack = params.slack_hourly_penalty_eur * result_50.slack_hours;
    cost_breakdown.total = cost_breakdown.total + cost_breakdown.slack;
    
    % --- EMISSIONS BREAKDOWN ---
    emissions_breakdown = struct();
    % PV emissions (both arrays combined)
    emissions_breakdown.pv = params.ghg_intensity_pv_per_unit * (result_50.x_pv + result_50.x_pv2);
    
    % Battery emissions
    emissions_breakdown.batt = params.ghg_intensity_batt_per_kWh * result_50.E_bess;
    emissions_breakdown.total = emissions_breakdown.pv + emissions_breakdown.batt;
    
    % --- CALCULATE LCOE AND CARBON INTENSITY ---
    % Annual energy demand (sum of hourly loads in kWh, assuming data.P_load is in kW)
    annual_energy_kWh = sum(data.P_load) * params.dt_h;
    % LCOE in EUR/kWh = annual cost / annual energy (energy systems only, excluding heat)
    lcoe_eur_per_kwh = (cost_breakdown.pv + cost_breakdown.batt + cost_breakdown.grid) / (annual_energy_kWh);
    % Carbon intensity in kg CO2-eq/kWh = lifecycle emissions / (annual demand * project life)
    lifetime_energy_kWh = annual_energy_kWh * params.project_life;
    carbon_intensity_kg_per_kwh = (emissions_breakdown.pv + emissions_breakdown.batt) / (lifetime_energy_kWh);
    
    % ===== PRINT SUMMARY TO CONSOLE =====
    fprintf('\n========== OPTIMIZATION RESULTS ==========\n');
    fprintf('Objective: %s\n', params.objective_type);
    fprintf('\n--- SYSTEM SIZING ---\n');
    fprintf('  South-facing PV:  %.2f kWp\n', result_50.x_pv);
    fprintf('  North-facing PV:  %.2f kWp\n', result_50.x_pv2);
    fprintf('  Total PV:         %.2f kWp\n', result_50.x_pv + result_50.x_pv2);
    fprintf('  Battery:          %.2f kWh\n', result_50.E_bess);
    fprintf('\n--- COST BREAKDOWN (Annual, EUR) ---\n');
    fprintf('  South-facing PV:  %.2f\n', cost_breakdown.pv_1);
    fprintf('  North-facing PV:  %.2f\n', cost_breakdown.pv_2);
    fprintf('  Battery:          %.2f\n', cost_breakdown.batt);
    fprintf('  Grid:             %.2f\n', cost_breakdown.grid);
    fprintf('  Slack hours penalty: %.2f\n', cost_breakdown.slack);
    fprintf('  TOTAL:            %.2f\n', cost_breakdown.total);
    fprintf('  LCOE (Levelized Cost of Energy): %.4f EUR/kWh\n', lcoe_eur_per_kwh);
    
    % ====== PIE CHARTS ======
    % Cost pie chart
    fig_cost = figure('Name', 'Cost Breakdown (SOC0 = 50%)', 'NumberTitle', 'off', 'Position', [100 100 800 500], 'WindowStyle', 'docked');
    cost_labels = {'South PV', 'North PV', 'Battery', 'Grid'};
    cost_values = [cost_breakdown.pv_1, cost_breakdown.pv_2, cost_breakdown.batt, cost_breakdown.grid];

    nonzero_mask = cost_values > 0;
    cost_labels = cost_labels(nonzero_mask);
    cost_values = cost_values(nonzero_mask);

    pie(cost_values);
    legend(cost_labels, 'Location', 'bestoutside');
    title(sprintf('Annual Cost Breakdown (SOC0 = 50%%)\nTotal: %.2f EUR', cost_breakdown.total));
    
    % Emissions pie chart (split backup into capacity and dispatch)
    fig_emis = figure('Name', 'GHG Emissions Breakdown (SOC0 = 50%)', 'NumberTitle', 'off', 'Position', [700 100 600 500], 'WindowStyle', 'docked');
    emis_labels = {'PV', 'Battery'};
    emis_values = [emissions_breakdown.pv, emissions_breakdown.batt];
    % Filter out zero values for cleaner visualization
    nonzero_emis_mask = emis_values > 0;
    emis_labels = emis_labels(nonzero_emis_mask);
    emis_values = emis_values(nonzero_emis_mask);
    pie(emis_values);
    legend(emis_labels, 'Location', 'bestoutside');
    title(sprintf('Lifecycle GHG Breakdown (SOC0 = 50%%)\nTotal: %.2f Tons CO2-eq', emissions_breakdown.total / 1e3));
end

% ====== COMPLIANCE CHECK VISUALIZATIONS (SOC0 = 50%) ======
    
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
        
titleSuffix = sprintf('MVP System Sizing: S-PV=%.0f kWp, N-PV=%.0f kWp, Batt=%.0f kWh', ...
    result_50.x_pv, result_50.x_pv2, result_50.E_bess);

% --- YEARLY SUPPLY-DEMAND BALANCE (Cumulative Stacked Bar Chart) ---
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

fig1 = figure('Name', 'Weekly Supply-Demand Balance (Cumulative) - SOC0 = 50%', 'NumberTitle', 'off', 'Position', [center_x center_y 1000 600], 'WindowStyle', 'docked');
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
xlabel('Week of Year'); 
ylabel('Energy (kWh)');
title(sprintf('Weekly Power Balance - Cumulative (SOC0 = 50%%)\n%s', titleSuffix));
legend([h_Supply(1), h_Supply(2), h_Supply(3), h_Supply(4), h_Demand(1), h_Demand(2), h_line], ...
    {'Solar (South)', 'Solar (North)', 'Battery Discharge', 'Grid', 'Battery Charge', 'Unmet (Slack)', 'Weekly Load'}, ...
    'Location', 'best');
grid on;
xticks(1:2:weeks_in_year);

% --- WEEKLY DISPATCH DETAIL (Renewables, Battery, Curtailment, Slack) ---
fig5 = figure('Name', 'Weekly Dispatch Detail - SOC0 = 50%', 'NumberTitle', 'off', ...
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
title(sprintf('First Week Dispatch Detail (SOC0 = 50%%)\n%s', titleSuffix));
legend([h_supply(1), h_supply(2), h_supply(3), h_supply(4), h_supply(5), h_ch, h_line], ...
    {'Solar (South)', 'Solar (North)', 'Battery Discharge', 'Grid', 'Unmet (Slack)', 'Battery Charge', 'Load'}, ...
    'Location', 'best');
grid on;
yline(0, 'k--', 'LineWidth', 0.5);

% --- ANNUAL DISPATCH DETAIL (Same style as weekly) ---
fig5b = figure('Name', 'Annual Dispatch Detail - SOC0 = 50%', 'NumberTitle', 'off', ...
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
title(sprintf('Annual Dispatch Detail (SOC0 = 50%%)\n%s', titleSuffix));
legend([h_supply_all(1), h_supply_all(2), h_supply_all(3), h_supply_all(4), h_supply_all(5), h_ch_all, h_line_all], ...
    {'Solar (South)', 'Solar (North)', 'Battery Discharge', 'Grid', 'Unmet (Slack)', 'Battery Charge', 'Load'}, ...
    'Location', 'best');
grid on;
yline(0, 'k--', 'LineWidth', 0.5);


% --- ANNUAL BATTERY STATE OF CHARGE ---
fig6 = figure('Name', 'Annual Battery State of Charge - SOC0 = 50%', 'NumberTitle', 'off', 'Position', [center_x center_y 800 600], 'WindowStyle', 'docked');
soc_annual = result_50.e_stored / result_50.E_bess;  % Normalize to 0-1 range
plot(0:T, soc_annual, 'LineWidth', 1.5, 'Color', '#0066FF');
hold on;
yline(params.soc_min, 'r--', 'LineWidth', 1.5, 'DisplayName', sprintf('Min SOC (%.0f%%)', params.soc_min*100));
yline(params.soc_max, 'g--', 'LineWidth', 1.5, 'DisplayName', sprintf('Max SOC (%.0f%%)', params.soc_max*100));
hold off;
xlabel('Hour of Year'); 
ylabel('State of Charge (SOC)');
title(sprintf('Annual Battery State of Charge (SOC0 = 50%%)\n%s', titleSuffix));
legend('Location', 'best');
grid on;
ylim([0 1]);

