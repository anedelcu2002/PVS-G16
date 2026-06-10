clc; clear; close all; warning("off");

%% Parameters for Battery Assignment exercise

%% Grid Parameters
f = 50;         % Grid frequency                [Hz]
V = 400;        % Grid (RMS) line voltage       [V]

%% Simulation parameters
Ts    = 3600;     % Step-size of the simulation   [s]

%% Load electricity demand
elec_tbl = readtable('load_values_3_years.csv');
P_load = elec_tbl{:, 11}.*1000; % 3-year hourly load in W
Load = [transpose(1:26280).*3600, P_load];

Grid=Load;
Grid(Load==6000)=0;

%% Load the solar generation profiles
module=1; % 1 for longi, 2 for aiko
south_tbl = readtable('generation_profile_south.xlsx', 'Sheet', 'Sheet1');
if module == 1
    cost_module = 950;
    P_solar = south_tbl{:,2};
    nr_panels = 5; % 5 panels in series
else
    cost_module = 800;
    P_solar = south_tbl{:,3};
    nr_panels = 8; % 6 panels in series
end

years = 3;
P_solar = repmat(P_solar, years, 1); % 3-year range of per-panel generation in kWh
P_solar = P_solar .* nr_panels .* 1000; % multiply per-panel generation by nr of panels
Solar = [transpose(1:26280).*3600, P_solar];

%% handle battery degradation
P_blackout = elec_tbl{:, 10}; % uses the 3-year range
blackout_event_start = zeros(size(P_blackout));
if ~isempty(P_blackout)
    blackout_event_start(1) = P_blackout(1) > 0;
    blackout_event_start(2:end) = (P_blackout(2:end) > 0) & (P_blackout(1:end-1) == 0);
end
T = numel(P_load);
cycles_at_e = zeros(T+1, 1);
cycles_at_e(2:end) = cumsum(blackout_event_start);
batt_cap_factor = 1 - 0.02/100 * cycles_at_e;
batt_cap_factor = max(batt_cap_factor, 0); % safety clamp

%% run LFP
cost_bat_unit = 990;         % LFP Battery capex
effConv = sqrt(0.92);                 % Charging efficiency (round-trip loss: 0.92)
Q       = 5120;    % Battery (energy) capacity             [W*hr]
Vnom    = 25.6;       % Nominal voltage                       [V]
AH      = Q/Vnom;   % Ampere-hour rating (capacity)         [A*hr]
AH_EOL = AH*batt_cap_factor(end);
SOC0    = 95;       % Initial State of Charge               [%]
Nb_s    = 2;        % number of batteries in series         [-]     
Nb_p    = 7;        % number of batteries in parallel       [-]    
eff_cc = 0.95;

out = sim("Performance_Analysis.slx");
fprintf('\n--- LFP ---\n');
fprintf('  Maximum power imbalance (W):   %.2f\n', max(power_imbalance.Data));

eff_inv = eff_inv_grid_tied + eff_inv_blackout;
%avg_nonzero = mean(eff_inv_grid_tied.Data (eff_inv_grid_tied.Data  ~= 0))

max(system_current)
min(system_current)
%figure;
%plot(eff_inv)
%plot(system_current)
%plot(SoC)
%plot(solar_to_load)
sum(solar_to_load/1000)

%figure;

%figure;

% Extract time and data
%time_seconds = eff_inv.Time;      % Time in seconds
%data = SoC;              % Your data

% Convert seconds to hours
%time_hours = time_seconds / 3600;

% Plot with thicker line
%plot(time_hours, data, 'LineWidth', 2.5);  % Adjust thickness as needed

% Label axes
%xlabel('Time (hours)');
%ylabel('Data Value');
%title('Line Plot of eff_inv');
%grid on;

start_date = datetime(2025, 1, 1, 0, 0, 0);
end_date = datetime(2028, 1, 1, 0, 0, 0);
dt_array = start_date:hours(1):end_date;
plot(transpose(dt_array), solar_to_load.Data)

% Create timetable from your data
TT = timetable(transpose(dt_array), solar_to_load.Data, ...
    'VariableNames', {'SolarPV'});

% Aggregate to monthly sum (Wh to monthly Wh, or convert to kWh)
monthly_sum = retime(TT, 'monthly', 'sum');

% Plot monthly totals
figure;
bar(monthly_sum.Time, monthly_sum.SolarPV/1000); % Convert to kWh
xlabel('Month');
ylim([0,220])
ylabel('Monthly Solar PV Output (kWh)');
title('Monthly Solar PV Generation');
grid on;

%% calculate costs
cost_grid = sum(power_grid.Data/1000) * 0.2;
cost_PV = cost_module * nr_panels;
cost_battery = Nb_p * Nb_s * cost_bat_unit;
cost_other = 1193 + 360 + 514 + 1200;
cost_system = cost_PV + cost_battery + cost_other;
cost_compensation = length(Grid(Grid==0))*112.5;
cost_grid_alternative = sum(Grid(:,2))/1000*0.2;
lfp_savings = cost_compensation - cost_system + cost_grid_alternative - cost_grid;

fprintf('\n--- COST BREAKDOWN LFP (3-YEAR TOTAL, EUR) ---\n');
fprintf('  PV array + inverter:         %.2f\n', cost_PV);
fprintf('  Battery:                     %.2f\n', cost_battery);
fprintf('  Other costs:                 %.2f\n', cost_other);
fprintf('  Alternative compensation:    %.2f\n', cost_compensation);
fprintf('  Grid use:                    %.2f\n', cost_grid);
fprintf('  Alternative grid use:        %.2f\n', cost_grid_alternative)
fprintf('  Savings:                     %.2f\n', lfp_savings);

%% run lead-acid

%cost_bat_unit = 485;         % Lead-acid Battery capex
%effConv = sqrt(0.8);                 % Charging efficiency (round-trip loss: 0.8)
%Q       = 1920;    % Battery (energy) capacity             [W*hr]
%Vnom    = 12;       % Nominal voltage                       [V]
%AH      = Q/Vnom;   % Ampere-hour rating (capacity)         [A*hr]
%AH_EOL = AH*batt_cap_factor(end);
%SOC0    = 95;       % Initial State of Charge               [%]
%Nb_s    = 4;        % number of batteries in series         [-]     
%Nb_p    = 9;        % number of batteries in parallel       [-] 

%eff_cc = 0.95;

%out = sim("Performance_Analysis.slx");
%fprintf('\n--- Lead-acid ---\n');
%fprintf('  Maximum power imbalance (W):   %.2f\n', max(power_imbalance.Data));
%eff_inv = eff_inv_grid_tied + eff_inv_blackout;

%% calculate costs
%cost_grid = sum(power_grid.Data/1000) * 0.2;
%cost_PV = cost_module * nr_panels;
%cost_battery = Nb_p * Nb_s * cost_bat_unit;
%cost_other = 1193 + 360 + 514 + 1200;
%cost_system = cost_PV + cost_battery + cost_other;
%cost_compensation = length(Grid(Grid==0))*112.5;
%cost_grid_alternative = sum(Grid(:,2))/1000*0.2;
%la_savings = cost_compensation - cost_system + cost_grid_alternative - cost_grid;

%fprintf('\n--- COST BREAKDOWN LEAD-ACID (3-YEAR TOTAL, EUR) ---\n');
%fprintf('  PV array + inverter:         %.2f\n', cost_PV);
%fprintf('  Battery:                     %.2f\n', cost_battery);
%fprintf('  Other costs:                 %.2f\n', cost_other);
%fprintf('  Alternative compensation:    %.2f\n', cost_compensation);
%fprintf('  Grid use:                    %.2f\n', cost_grid);
%fprintf('  Alternative grid use:        %.2f\n', cost_grid_alternative)
%fprintf('  Savings:                     %.2f\n', la_savings);


%fprintf('\n--- LFP vs lead-acid ---\n');
%fprintf('  LFP savings:                     %.2f\n', lfp_savings);
%fprintf('  Lead-acid savings:               %.2f\n', la_savings);
%fprintf('  Difference:                      %.2f\n', abs(lfp_savings-la_savings));