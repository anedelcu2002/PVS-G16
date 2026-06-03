clc; clear; close all; warning("off");

%% Resolve project root and add paths
projectRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(projectRoot,"scripts"));

%% Load electricity demand
elec_tbl = readtable('load_values_3_years.csv');
P_load = elec_tbl{:, 11}; % 3-year hourly load in kW

%% Load the solar generation profiles
module=1; % 1 for longi, 2 for aiko
south_tbl = readtable('generation_profile_south.xlsx', 'Sheet', 'Sheet1');
if module == 1
    P_solar = south_tbl{:,2};
    nr_panels = 6; % 6 panels in series
else
    P_solar = south_tbl{:,3};
    nr_panels = 8; % 8 panels in series
end

years = 3;
P_solar = repmat(P_solar, years, 1); % 3-year range of per-panel generation
P_solar = P_solar .* nr_panels; % multiply per-panel generation by nr of panels in array

%% Load blackout profile and generate counter
P_blackout = elec_tbl{:, 10}; % uses the 3-year range

blackout_event_start = zeros(size(P_blackout));
if ~isempty(P_blackout)
    blackout_event_start(1) = P_blackout(1) > 0;
    blackout_event_start(2:end) = (P_blackout(2:end) > 0) & (P_blackout(1:end-1) == 0);
end

%% Build time-varying battery capacity factor (for e_stored indices 1..T+1)
batt_deg_per_cycle = 0.0002;         % 0.02% per cycle (event)
T = numel(P_load);
cycles_at_e = zeros(T+1, 1);
cycles_at_e(2:end) = cumsum(blackout_event_start);
batt_cap_factor = 1 - batt_deg_per_cycle * cycles_at_e;
batt_cap_factor = max(batt_cap_factor, 0); % safety clamp

%% Create simulink variables
Q = 84480; % 20 batteries x 4224 Wh, can also be 8p x 2s x 200 Wh at 25.6 V
Vnom = 51.2; % system voltage is 51.2V, per-battery voltage is 12.8 V
AH = Q/Vnom;
effConvBESS = sqrt(0.92); % 92% round-trip efficiency
Nb_s = 4;
Nb_p = 5;
SOC0 = 95;
f = 50;
V = 400; % shouldn't this be 230?   
Ts = 60;