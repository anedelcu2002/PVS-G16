clc; clear; close all; warning("off");

%% 1) Resolve project root and add paths (scripts + utils + optimization_building_blocks)
projectRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(projectRoot,"scripts"));                 % step_*.m live here
addpath(genpath(fullfile(projectRoot,"scripts","utils")));% utils live here
addpath(genpath(fullfile(projectRoot,"scripts","optimization_building_blocks"))); % optimization functions

if ~exist('outputs','dir'); mkdir('outputs'); end

debug_mode = false;

%% 1. Create the demand profiles
demand_inputsDir = fullfile(projectRoot,"inputs","step01_demand_calculations");   
if ~exist('outputs/step01_demand_calculations','dir'); mkdir('outputs/step01_demand_calculations'); end
demandoutDir = fullfile(projectRoot,"outputs","step01_demand_calculations");
[elecDemandCsvPath, heatDemandCsvPath] = step01_generate_demand_profiles(debug_mode, demand_inputsDir, demandoutDir);

%% 2. Create heat supply profiles
HeatSupplyoutDir = fullfile(projectRoot,"outputs","step02_heat_supply_calculations");
heatSupplyCsv = step02_generate_heat_supply_profile(HeatSupplyoutDir);

%% 3. Create heat storage profiles
heat_inputsDir = fullfile(projectRoot, "outputs", "step01_demand_calculations");
if ~exist('outputs/step03_heat_storage_calculations','dir'); mkdir('outputs/step03_heat_storage_calculations'); end
heat_outDir = fullfile(projectRoot, "outputs", "step03_heat_storage_calculations");

heatStorCsv = step03_generate_heat_storage_profile(debug_mode, heat_inputsDir, heat_outDir);

%% 4. Calculate starting total electricity load (Load + Pump)
args = struct( ...
    'elecCsv',    elecDemandCsvPath, ...
    'heatStorCsv', heatStorCsv, ...
    'heatSupplyCsv', heatSupplyCsv ...
);
[Load, Pump] = step04_cosumption_sizing(debug_mode, args);

P_load = Load(:,2) + Pump(:,2); % compute total electrical load

%% 5a. Create the initial wind profile for 1 turbine
wind_inputsDir = fullfile(projectRoot,"inputs","step_05a_wind_calculations");
wind_outDir    = fullfile(projectRoot,"outputs","step_05a_wind_calculations");

[Wind1, windCsv] = step05a_generate_wind_profile_for_1_turbine(wind_inputsDir, wind_outDir);

%% 5b. Create the initial solar profile for 1 inverter
solarCsvInput = fullfile(projectRoot, "inputs", "step_05b_solar_calculations");
solarCsvOutput    = fullfile(projectRoot,"outputs","step_05b_solar_calculations");
[Solar1, SolarCsv] = step05b_generate_solar_profile_for_1_inverter(solarCsvInput, solarCsvOutput);

%% Create simulink variables

% Input values for simulink
Q = 12.8e6;
Vnom = 1331.2;
AH = Q/Vnom;
effConvBESS = sqrt(0.93);
Nb_s = 1;
Nb_p = ceil(3.7e9/Q);
SOC0 = 50;
f = 50;
V = 400;   
Ts = 60;
