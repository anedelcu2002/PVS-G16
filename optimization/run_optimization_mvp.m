clc; clear; close all; warning("off");

%% Resolve project root and add paths
projectRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(projectRoot,"scripts"));

%% 1. Load electricity demand directly (skip steps 1-4)
elecDemandCsvPath = fullfile(projectRoot, "amersfoort_electricity_demand.csv");
heatDemandCsvPath = "";  % no heat demand file when skipping steps 1-4

if ~exist(elecDemandCsvPath, 'file')
    error('Electricity demand file not found: %s', elecDemandCsvPath);
end

elec_tbl = readtable(elecDemandCsvPath);
P_load = elec_tbl{:, 2} / 3600; % convert J (per hour) to W

%% 5b. Load the initial solar profile for 1 inverter directly
solarCsvPath = fullfile(projectRoot, "solar_profiles_1_inverter.csv");

if ~exist(solarCsvPath, 'file')
    error('Solar profile file not found: %s', solarCsvPath);
end

solar_tbl = readtable(solarCsvPath);
Solar1 = table2array(solar_tbl);
Solar1(:,2) = Solar1(:,2) / 3600; % convert J (per hour) to W

%% Optimization

% set data
data = struct( ...
    'P_load', P_load, ...
    'P_solar_unit', Solar1(:,2) ...
);

% set parameters
params = struct();

% ============== SYSTEM TOGGLES ==============
params.enable_battery = true;     % Toggle battery system
params.enable_slack = true;        % Toggle slack (unmet demand penalty)
params.enable_curtailment = true;  % Toggle curtailment limits (independent of battery)
params.objective_type = 'economic';  % Choose: 'economic' (cost minimization) or 'environmental' (GHG minimization)
% ================================================

% Technical
params.dt_h = 1.0;
params.x_pv_ub = 10000;

% Economics
params.discount_rate = 0.06;
params.project_life = 20;

params.c_pv_unit_capex = 261195.56;           % /inverter
params.c_pv_unit_fom_per_year = 5145.5;      % /inverter/year


% ============== BATTERY PARAMETERS (if enabled) ==============
% Technical
params.battery_c_rating = 0.25;             % C-rating: 0.25 h^-1 means 4hr discharge
params.eta_ch = sqrt(0.93);                 % Charging efficiency (round-trip loss: 0.93)
params.eta_dis = sqrt(0.93);                % Discharging efficiency (same as charge)
params.soc_min = 0.10;                      % Min state-of-charge (10%)
params.soc_max = 0.90;                      % Max state-of-charge (90%)
params.soc0 = 0.50;                         % Initial SOC
params.soc_tolerance = 10e3;                % Cyclic tolerance (Wh)
params.E_bess_ub = 10 * 1e9;              % Battery energy upper bound

% Economics
params.c_bess_E_capex_per_Wh = 0.334;         % Battery capex (EUR/Wh)
params.c_bess_E_fom_per_Wh_yr = params.c_bess_E_capex_per_Wh*0.04;          % Battery FOM (EUR/Wh/year)
params.max_curtail_pct = 0.10;              % Max annual curtailment (10% of load)
% ==============================================================


% ============== LIFECYCLE GHG PARAMETERS (EMBEDDED EMISSIONS) ===============
% All GHG intensities in kg CO2-eq per unit
% For now, all set to 1 kg CO2-eq per unit (can be updated with actual values)
params.ghg_intensity_pv_per_unit = 831637.25;         % kg CO2-eq per PV inverter unit
params.ghg_intensity_batt_per_wh = 0.09;         % kg CO2-eq per Wh of battery storage


fprintf('Data check before optimization:\n');
fprintf('  P_load: min=%.2e, max=%.2e\n', min(data.P_load), max(data.P_load));
fprintf('  P_solar_unit: min=%.2e, max=%.2e\n', min(data.P_solar_unit), max(data.P_solar_unit));
fprintf('  Max possible gen: %.2e W\n', ...
    params.x_pv_ub*max(data.P_solar_unit));
fprintf('  Peak load: %.2e W\n', max(data.P_load));

fprintf('Solving MVP optimization problem...\n')
fprintf('\n')

% Setup constraint and objective registries
constraint_registry = {@bind_power_balance};

% Select objective based on objective_type
if strcmp(params.objective_type, 'economic')
    % Economic optimization: minimize cost
    objective_registry = {@default_objective, @cost_slack};
    
    if params.enable_battery
        objective_registry = [objective_registry, {@cost_battery}];
    end
elseif strcmp(params.objective_type, 'environmental')
    % Environmental optimization: minimize GHG emissions (embedded only)
    objective_registry = {@cost_ghg_lifecycle, @cost_slack};
    % Note: battery GHG are already included in cost_ghg_lifecycle
else
    error('Unknown objective_type: %s. Choose ''economic'' or ''environmental''.', params.objective_type);
end

% Add battery constraints if enabled
if params.enable_battery
    constraint_registry = [constraint_registry, ...
        {@bind_battery_dynamics, ...
         @bind_battery_soc, ...
         @bind_battery_exclusivity}];
end

% Add curtailment constraint if enabled (independent of battery)
if params.enable_curtailment
    constraint_registry = [constraint_registry, {@bind_curtailment}];
end

tic
result_50 = build_problem(data, params, constraint_registry, objective_registry);
elapsed = toc;

%% 7. Visualization - Forward-compatible supply-demand analysis
fprintf('\nGenerating visualization...\n')


% ====== COST AND EMISSIONS BREAKDOWNS (computed once for SOC50%) ======
if ~strcmp(result_50.status, 'infeasible or error')
    % --- COST BREAKDOWN ---
    cost_breakdown = struct();
    
    % PV cost
    CRF = compute_crf(params.discount_rate, params.project_life);
    cost_breakdown.pv = CRF * params.c_pv_unit_capex * result_50.x_pv + ...
                        params.c_pv_unit_fom_per_year * result_50.x_pv;
    
    % Battery cost
    cost_breakdown.batt = 0;
    if params.enable_battery && isfield(result_50, 'E_bess')
        cost_breakdown.batt = CRF * params.c_bess_E_capex_per_Wh * result_50.E_bess + ...
                              params.c_bess_E_fom_per_Wh_yr * result_50.E_bess;
    end
    
    cost_breakdown.total = cost_breakdown.pv + cost_breakdown.batt;
    
    % --- EMISSIONS BREAKDOWN ---
    emissions_breakdown = struct();
    
    % PV emissions
    emissions_breakdown.pv = params.ghg_intensity_pv_per_unit * result_50.x_pv;

    % Battery emissions
    emissions_breakdown.batt = 0;
    if params.enable_battery && isfield(result_50, 'E_bess')
        emissions_breakdown.batt = params.ghg_intensity_batt_per_wh * result_50.E_bess;
    end
    
    emissions_breakdown.total = emissions_breakdown.pv + emissions_breakdown.batt;
    
    % --- CALCULATE LCOE AND CARBON INTENSITY ---
    % Annual energy demand (sum of hourly loads in Wh, assuming data.P_load is in W)
    annual_energy_Wh = sum(data.P_load) * params.dt_h;
    % LCOE in EUR/MWh = annual cost / annual energy (energy systems only, excluding heat)
    lcoe_eur_per_Mwh = (cost_breakdown.pv + cost_breakdown.batt) / (annual_energy_Wh / 1e6);
    
    % Carbon intensity in kg CO2-eq/MWh = lifecycle emissions / (annual demand * project life)
    lifetime_energy_Wh = annual_energy_Wh * params.project_life;
    carbon_intensity_kg_per_Mwh = (emissions_breakdown.pv + emissions_breakdown.batt) / (lifetime_energy_Wh / 1e6);
    
    % ===== PRINT SUMMARY TO CONSOLE =====
    fprintf('\n========== OPTIMIZATION RESULTS: SOC0 = 50%% ==========\n');
    fprintf('Objective: %s\n', params.objective_type);
    fprintf('\n--- SYSTEM CAPACITIES ---\n');
    fprintf('  PV inverters: %.2f units\n', result_50.x_pv);
    if params.enable_battery && isfield(result_50, 'E_bess')
        fprintf('  Battery storage: %.2e Wh (%.2f GWh)\n', result_50.E_bess, result_50.E_bess/1e9);
    end
    
    fprintf('\n--- COST BREAKDOWN (Annual, Million EUR) ---\n');
    fprintf('  PV:        %.2f\n', cost_breakdown.pv / 1e6);
    if params.enable_battery
        fprintf('  Battery:   %.2f\n', cost_breakdown.batt / 1e6);
    end
    
    fprintf('  TOTAL:     %.2f\n', cost_breakdown.total / 1e6);
    
    fprintf('\n--- KEY ECONOMIC METRICS ---\n');
    fprintf('  LCOE (Levelized Cost of Energy): %.4f EUR/MWh\n', lcoe_eur_per_Mwh);
    
    fprintf('\n--- GHG EMISSIONS BREAKDOWN (Life-cycle, Megatons CO2-eq) ---\n');
    fprintf('  PV:        %.2f\n', emissions_breakdown.pv / 1e9);
    if params.enable_battery
        fprintf('  Battery:   %.2f\n', emissions_breakdown.batt / 1e9);
    end
    fprintf('  TOTAL:     %.2f\n', emissions_breakdown.total / 1e9);
    
    fprintf('\n--- KEY ENVIRONMENTAL METRICS ---\n');
    fprintf('  Carbon Intensity: %.4f kg CO2-eq/MWh\n', carbon_intensity_kg_per_Mwh);
    fprintf('====================================================================\n\n');
    
    % ====== PIE CHARTS ======
    % Cost pie chart
    fig_cost = figure('Name', 'Cost Breakdown (SOC0 = 50%)', 'NumberTitle', 'off', 'Position', [100 100 600 500], 'WindowStyle', 'docked');
    cost_labels = {'PV', 'Battery'};
    cost_values = [cost_breakdown.pv, cost_breakdown.batt];
    % Filter out zero values for cleaner visualization
    nonzero_mask = cost_values > 0;
    cost_labels = cost_labels(nonzero_mask);
    cost_values = cost_values(nonzero_mask);
    pie(cost_values);
    legend(cost_labels, 'Location', 'bestoutside');
    title(sprintf('Annual Cost Breakdown (SOC0 = 50%%)\nTotal: %.2f Million EUR', cost_breakdown.total / 1e6));
    
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
    title(sprintf('Lifecycle GHG Breakdown (SOC0 = 50%%)\nTotal: %.2f Megatons CO2-eq', emissions_breakdown.total / 1e9));
end

% ====== COMPLIANCE CHECK VISUALIZATIONS (SOC0 = 50%) ======
    
% Prepare supply and demand timeseries
T = numel(data.P_load);
supply_components = struct();
demand_components = struct();

% Current generation sources
supply_components.solar = result_50.x_pv * data.P_solar_unit / 1e6;  % Convert to MW

% Demand breakdown
demand_components.load = data.P_load / 1e6;  % Convert to MW

% Handle battery if enabled
if isfield(result_50, 'p_dis')
    supply_components.batt_dis = result_50.p_dis / 1e6;  % Battery discharge in MW
else
    supply_components.batt_dis = zeros(T, 1);
end

if isfield(result_50, 'p_ch')
    demand_components.batt_ch = result_50.p_ch / 1e6;  % Battery charge in MW
else
    demand_components.batt_ch = zeros(T, 1);
end

% Handle slack
if any(isnan(result_50.slack))
    supply_components.slack = zeros(size(result_50.slack)) / 1e6;
else
    supply_components.slack = result_50.slack / 1e6;
end

total_met_demand = supply_components.solar + supply_components.batt_dis;
total_unmet_demand = supply_components.slack;

% Time arrays
hours_all = 0:T-1;
hours_week = 0:min(168, T-1);

% Calculate excess generation
total_generation = supply_components.solar;
excess_generation = max(0, total_generation - demand_components.load - demand_components.batt_ch);
supply_components.excess = excess_generation;

% Figure position: center of screen (1920x1080)
center_x = (1920 - 1000) / 2;  % 560
center_y = (1080 - 800) / 2;  % 240
        
titleSuffix = sprintf('MVP System Sizing Results: %.0f PV inverters', result_50.x_pv);

% --- YEARLY SUPPLY-DEMAND BALANCE (Cumulative Stacked Bar Chart) ---
% Aggregate hourly data by week
weeks_in_year = ceil(T / 168);
weekly_demand = zeros(weeks_in_year, 1);
weekly_solar = zeros(weeks_in_year, 1);
weekly_batt_dis = zeros(weeks_in_year, 1);
weekly_batt_ch = zeros(weeks_in_year, 1);
weekly_slack = zeros(weeks_in_year, 1);

for w = 1:weeks_in_year
    start_idx = (w-1) * 168 + 1;
    end_idx = min(w * 168, T);
    weekly_demand(w) = sum(demand_components.load(start_idx:end_idx));
    weekly_solar(w) = sum(supply_components.solar(start_idx:end_idx));
    weekly_batt_dis(w) = sum(supply_components.batt_dis(start_idx:end_idx));
    weekly_batt_ch(w) = sum(demand_components.batt_ch(start_idx:end_idx));
    weekly_slack(w) = sum(supply_components.slack(start_idx:end_idx));
end

fig1 = figure('Name', 'Weekly Supply-Demand Balance (Cumulative) - SOC0 = 50%', 'NumberTitle', 'off', 'Position', [center_x center_y 1000 600], 'WindowStyle', 'docked');
hold on;

% Create stacked bar chart showing power balance (convert to GWh)
% Positive side: generation sources
% Negative side: battery charging demand
week_numbers = 1:weeks_in_year;
weekly_supply = [weekly_solar, weekly_batt_dis] / 1000;  % Convert MWh to GWh
weekly_demand_components = [-weekly_batt_ch, weekly_slack] / 1000;  % Convert MWh to GWh

% Plot supply sources (positive)
h_Supply = bar(week_numbers, weekly_supply, 'stacked', 'EdgeColor', 'none');

% Assign colors to supply components
h_Supply(1).FaceColor = '#FDB462';  % Solar
h_Supply(2).FaceColor = '#8DD3C7';  % Battery Discharge

% Plot demand components on same bars (battery charge as negative, slack as positive continuation)
h_Demand = bar(week_numbers, weekly_demand_components, 'stacked', 'EdgeColor', 'none');
h_Demand(1).FaceColor = '#FC8d62';  % Battery Charge (reddish, different from discharge)
h_Demand(2).FaceColor = '#984EA3';  % Unmet (Slack) - purple, distinct from battery discharge

% Overlay weekly load demand as a line (convert to GWh)
hold on;
h_line = plot(week_numbers, weekly_demand / 1000, 'ko-', 'LineWidth', 2, 'MarkerSize', 5, 'DisplayName', 'Weekly Load');

% Add zero reference line (exclude from legend)
yline(0, 'k-', 'LineWidth', 0.5, 'HandleVisibility', 'off');

hold off;
xlabel('Week of Year'); 
ylabel('Energy (GWh)');
title(sprintf('Weekly Power Balance - Cumulative (SOC0 = 50%%)\n%s', titleSuffix));
legend([h_Supply(1), h_Supply(2), h_Demand(1), h_Demand(2), h_line], ...
        {'Solar', 'Battery Discharge', 'Battery Charge', 'Unmet (Slack)', 'Weekly Load'}, ...
        'Location', 'best');
grid on;
xticks(1:2:weeks_in_year);

% --- ANNUAL STACKED SUPPLY ---
fig2 = figure('Name', 'Annual Generation Mix - SOC0 = 50%', 'NumberTitle', 'off', 'Position', [center_x center_y 800 600], 'WindowStyle', 'docked');
hold on;
area(hours_all, supply_components.solar, 'FaceColor', '#FDB462', 'EdgeColor', 'none', 'DisplayName', 'Solar');
area(hours_all, supply_components.batt_dis, 'FaceColor', '#8DD3C7', 'EdgeColor', 'none', 'DisplayName', 'Battery Discharge');
area(hours_all, supply_components.excess, 'FaceColor', '#BEBADA', 'EdgeColor', 'none', 'DisplayName', 'Excess (Unused)');
area(hours_all, supply_components.slack, 'FaceColor', '#FB8072', 'EdgeColor', 'none', 'DisplayName', 'Unmet');
hold off;
xlabel('Hour of Year'); ylabel('Power (MW)');
title(sprintf('Annual Generation Mix (SOC0 = 50%%)\n%s', titleSuffix));
legend('Location', 'best');
grid on;

% --- WEEKLY SUPPLY-DEMAND BALANCE ---
fig3 = figure('Name', 'Weekly Supply-Demand Balance - SOC0 = 50%', 'NumberTitle', 'off', 'Position', [center_x center_y 800 600], 'WindowStyle', 'docked');
hold on;
fill(hours_week, demand_components.load(1:numel(hours_week)), 'k', 'FaceAlpha', 0.2, 'EdgeColor', 'none', 'DisplayName', 'Total Demand');
fill(hours_week, total_met_demand(1:numel(hours_week)), 'g', 'FaceAlpha', 0.3, 'EdgeColor', 'none', 'DisplayName', 'Met Demand');
fill(hours_week, total_unmet_demand(1:numel(hours_week)), 'r', 'FaceAlpha', 0.4, 'EdgeColor', 'none', 'DisplayName', 'Unmet Demand');
plot(hours_week, total_generation(1:numel(hours_week)), 'b-', 'LineWidth', 1.5, 'DisplayName', 'Total Generation');
hold off;
xlabel('Hour of Week 1'); ylabel('Power (MW)');
title(sprintf('First Week Supply-Demand Balance (SOC0 = 50%%)\n%s', titleSuffix));
legend('Location', 'best');
grid on;

% --- WEEKLY STACKED SUPPLY ---
fig4 = figure('Name', 'Weekly Generation Mix - SOC0 = 50%', 'NumberTitle', 'off', 'Position', [center_x center_y 800 600], 'WindowStyle', 'docked');
hold on;
area(hours_week, supply_components.solar(1:numel(hours_week)), 'FaceColor', '#FDB462', 'EdgeColor', 'none', 'DisplayName', 'Solar');
area(hours_week, supply_components.batt_dis(1:numel(hours_week)), 'FaceColor', '#8DD3C7', 'EdgeColor', 'none', 'DisplayName', 'Battery Discharge');
area(hours_week, supply_components.excess(1:numel(hours_week)), 'FaceColor', '#BEBADA', 'EdgeColor', 'none', 'DisplayName', 'Excess (Unused)');
area(hours_week, supply_components.slack(1:numel(hours_week)), 'FaceColor', '#FB8072', 'EdgeColor', 'none', 'DisplayName', 'Unmet');
hold off;
xlabel('Hour of Week 1'); ylabel('Power (MW)');
title(sprintf('First Week Generation Mix (SOC0 = 50%%)\n%s', titleSuffix));
legend('Location', 'best');
grid on;

% --- WEEKLY DISPATCH DETAIL (Renewables, Battery, Curtailment) ---
if isfield(result_50, 'p_ch')
    fig5 = figure('Name', 'Weekly Dispatch Detail - SOC0 = 50%', 'NumberTitle', 'off', 'Position', [center_x center_y 1000 600], 'WindowStyle', 'docked');
    
    hours_week_range = 1:numel(hours_week);
    
    hold on;
    % Stacked supply sources
    bar(hours_week_range, supply_components.solar(hours_week_range), 'FaceColor', '#FDB462', 'EdgeColor', 'none', 'DisplayName', 'Solar');
    bar(hours_week_range, supply_components.batt_dis(hours_week_range), 'FaceColor', '#8DD3C7', 'EdgeColor', 'none', 'DisplayName', 'Battery Discharge');
    
    % Battery charge (negative bars)
    bar(hours_week_range, -demand_components.batt_ch(hours_week_range), 'FaceColor', '#FB8072', 'EdgeColor', 'none', 'DisplayName', 'Battery Charge');
    
    % Curtailment/Excess as a line
    plot(hours_week_range, supply_components.excess(hours_week_range), 'mo-', 'LineWidth', 1.5, 'MarkerSize', 4, 'DisplayName', 'Curtailment');
    
    hold off;
    xlabel('Hour of Week 1'); 
    ylabel('Power (MW)');
    title(sprintf('First Week Dispatch Detail (SOC0 = 50%%)\n%s', titleSuffix));
    legend('Location', 'best');
    grid on;
    yline(0, 'k--', 'LineWidth', 0.5);
end

% --- ANNUAL BATTERY STATE OF CHARGE ---
if isfield(result_50, 'e_stored') && isfield(result_50, 'E_bess')
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
end

% --- WEEKLY BATTERY STATE OF CHARGE ---
if isfield(result_50, 'e_stored') && isfield(result_50, 'E_bess')
    fig7 = figure('Name', 'Weekly Battery State of Charge - SOC0 = 50%', 'NumberTitle', 'off', 'Position', [center_x center_y 800 600], 'WindowStyle', 'docked');
    soc_weekly = result_50.e_stored(1:numel(hours_week)+1) / result_50.E_bess;
    plot(0:numel(hours_week), soc_weekly, 'LineWidth', 1.5, 'Color', '#0066FF');
    hold on;
    yline(params.soc_min, 'r--', 'LineWidth', 1.5, 'DisplayName', sprintf('Min SOC (%.0f%%)', params.soc_min*100));
    yline(params.soc_max, 'g--', 'LineWidth', 1.5, 'DisplayName', sprintf('Max SOC (%.0f%%)', params.soc_max*100));
    hold off;
    xlabel('Hour of Week 1'); 
    ylabel('State of Charge (SOC)');
    title(sprintf('First Week Battery State of Charge (SOC0 = 50%%)\n%s', titleSuffix));
    legend('Location', 'best');
    grid on;
    ylim([0 1]);
end  % End of visualization block

