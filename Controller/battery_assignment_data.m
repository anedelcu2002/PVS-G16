%% Parameters for Battery Assignment exercise

%% Battery Parameters
Q       = 78000;    % Battery (energy) capacity             [W*hr]
Vnom    = 48;       % Nominal voltage                       [V]
AH      = Q/Vnom;   % Ampere-hour rating (capacity)         [A*hr]
SOC0    = 95;       % Initial State of Charge               [%]
Nb_s    = 1;        % number of batteries in series         [-]     <-- Replace with the parameter for your system
Nb_p    = 1;        % number of batteries in parallel       [-]     <-- Replace with the parameter for your system

%% Other Parameters
effConv = sqrt(0.92);        % Power converters (BESS) efficiency     [-]    <-- Replace with the correct value

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
module=2; % 1 for longi, 2 for aiko
south_tbl = readtable('generation_profile_south.xlsx', 'Sheet', 'Sheet1');
if module == 1
    P_solar = south_tbl{:,2};
    nr_panels = 6; % 6 panels in series
else
    P_solar = south_tbl{:,3};
    nr_panels = 7; % 8 panels in series
end

years = 3;
P_solar = repmat(P_solar, years, 1); % 3-year range of per-panel generation in kWh
P_solar = P_solar .* nr_panels .* 1000; % multiply per-panel generation by nr of panels
Solar = [transpose(1:26280).*3600, P_solar];

eff_cc = 0.95;