%% Parameters for Battery Assignment exercise

%% Battery Parameters
Q       = 13500;    % Battery (energy) capacity             [W*hr]
Vnom    = 50;       % Nominal voltage                       [V]
AH      = Q/Vnom;   % Ampere-hour rating (capacity)         [A*hr]
SOC0    = 95;       % Initial State of Charge               [%]
Nb_s    = 1;        % number of batteries in series         [-]     <-- Replace with the parameter for your system
Nb_p    = 20000;        % number of batteries in parallel       [-]     <-- Replace with the parameter for your system

%% Other Parameters
effConv = 1;        % Power converters (BESS) efficiency     [-]    <-- Replace with the correct value

%% Grid Parameters
f = 50;         % Grid frequency                [Hz]
V = 400;        % Grid (RMS) line voltage       [V]

%% Simulation parameters
Ts    = 3600;     % Step-size of the simulation   [s]

%% Load electricity demand
elec_tbl = readtable('load_values_3_years.csv');
P_load = elec_tbl{:, 11}.*1000; % 3-year hourly load in kW
Load = [transpose(1:26280).*3600, P_load];

Grid=Load;
Grid(Load==6000)=0.0001;