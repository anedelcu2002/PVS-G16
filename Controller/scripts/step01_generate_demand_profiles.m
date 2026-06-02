% calculate_amersfoort_demand.m
%
% Description:
%   Runs generate_demand_profiles.m to produce normalized electricity and gas demand profiles
%   for Amersfoort, then calculates absolute demand profiles in joules for each time step
%   by multiplying the yearly demand (in J) with each value in the normalized profile.
%
% Workflow:
%   1. Set debug_mode (optional) and run generate_demand_profiles.m.
%   2. Read output CSVs: electricity_profiles.csv and gas_profiles.csv.
%   3. Specify yearly demand (in joules) for each profile (E1A, E3B, G1A, G2C).
%   Demand values for each sector based on 2024 Kilmaatmonitor data according to
%   https://klimaatmonitor.databank.nl/dashboard/dashboard/energieverbruik.
%   Convert gas demand from m3 to J using 38.6 MJ/m3 (average of LHV and HHV according to
%   https://www.engineeringtoolbox.com/fuels-higher-calorific-values-d_169.html
%   and apply a boiler efficiency of 85.7% for heat (according to
%   https://energy.nl/data/natural-gas-steam-boiler-industry/).
%   4. Multiply yearly demand by each normalized profile value to obtain time-resolved demand in joules.
%   5. Store results in new columns in the tables for further analysis or export.
%
% Sources:
%   - generate_demand_profiles.m (local script)
%   - electricity_profiles.csv (output from generate_demand_profiles.m)
%   - gas_profiles.csv (output from generate_demand_profiles.m)
%
% Profiles:
%   - E1A: Residential electricity (normalized)
%   - E3B: Non-residential electricity (normalized)
%   - G1A: Residential gas (normalized)
%   - G2C: Non-residential gas (normalized)
%


function [elecDemandCsvPath, heatDemandCsvPath] = step01_generate_demand_profiles(debug_mode, inputsDir, outDir)

    % Run the demand profile generation script
    step01_generate_normalized_demand_profiles(debug_mode, inputsDir, outDir);

    % Read the resulting CSV files
    elec_profiles = readtable(fullfile(outDir,'electricity_profiles.csv'));
    gas_profiles  = readtable(fullfile(outDir,'gas_profiles.csv'));
    
    % Calculate the yearly demand for electricity and gas in Amersfoort in J
    yearly_residential_electricity_demand=186.1*3600*10^9; % 186.1 GWh converted to J
    yearly_residential_heat_demand=56.3*10^6*38.6*10^6*0.857; % 56.3 million m3 converted to J using 38.6 MJ/m3 and efficiency of 85.7%

    yearly_non_residential_electricity_demand=332.8*3600*10^9; % 332.8 GWh converted to J
    yearly_non_residential_heat_demand=26.1*10^6*38.6*10^6*0.857; % 26.1 million m3 converted to J using 38.6 MJ/m3 and efficiency of 85.7%

    electricity_demand_profile_residential = elec_profiles.E1A*yearly_residential_electricity_demand;
    heat_demand_profile_residential = gas_profiles.G1A*yearly_residential_heat_demand;
    electricity_demand_profile_non_residential = elec_profiles.E3B*yearly_non_residential_electricity_demand;
    heat_demand_profile_non_residential = gas_profiles.G2C*yearly_non_residential_heat_demand;

    if debug_mode
        plot_profile(elec_profiles.DateTime, electricity_demand_profile_residential/3600/1e6, '15-minute residential electricity demand (MWh)', 'b');
        plot_profile(elec_profiles.DateTime, electricity_demand_profile_non_residential/3600/1e6, '15-minute non-residential electricity demand (MWh)', 'r');
        plot_profile(gas_profiles.DateTime, heat_demand_profile_residential/3600/1e6, 'Hourly residential heat demand (MWh)', 'b');
        plot_profile(gas_profiles.DateTime, heat_demand_profile_non_residential/3600/1e6, 'Hourly non-residential heat demand (MWh)', 'r');
    end

    electricity_demand_profile=electricity_demand_profile_residential + electricity_demand_profile_non_residential;
    heat_demand_profile=heat_demand_profile_residential + heat_demand_profile_non_residential;

    if debug_mode
        plot_profile(elec_profiles.DateTime, electricity_demand_profile/3600/1e6, '15-minute electricity demand (MWh) ', 'b');
        plot_profile(gas_profiles.DateTime, heat_demand_profile/3600/1e6, 'Hourly heat demand (MWh)', 'r');
    end

    function plot_profile(dt, data, label, color)
        figure;
        plot(dt, data, color);
        xlabel('Date/time');
        ylabel(label);
        xlim tight;
        grid on;
    end

    % Create electricity profile table
    % elec_output = table(elec_profiles.DateTime, electricity_demand_profile, 'VariableNames', {'DateTime', 'Electricity_Demand_J'});
    TT15 = timetable(elec_profiles.DateTime, electricity_demand_profile, ...
    'VariableNames', {'Electricity_Demand_J'});
    TTh = retime(TT15, 'hourly', 'sum'); 
    elec_output_hourly = timetable2table(TTh);
    % Create gas profile table
    heat_output = table(gas_profiles.DateTime, heat_demand_profile, 'VariableNames', {'DateTime', 'Heat_Demand_J'});

    if ~exist(outDir,'dir'); mkdir(outDir); end
    elecDemandCsvPath = fullfile(outDir,'amersfoort_electricity_demand.csv');
    heatDemandCsvPath = fullfile(outDir,'amersfoort_heat_demand.csv');
    
    writetable(elec_output_hourly, elecDemandCsvPath);
    writetable(heat_output, heatDemandCsvPath);

    if debug_mode==true
        disp('CSV files exported successfully:');
        disp('  - amersfoort_electricity_demand.csv');
        disp('  - amersfoort_heat_demand.csv');
    end
end