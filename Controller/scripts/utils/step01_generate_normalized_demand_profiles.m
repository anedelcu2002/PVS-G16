% demand_calculation.m
%
% Description:
%   Loads and processes standard Dutch electricity (E1A, E3B) and gas 
%   (G1A, G2C) demand profiles for the year 2024. Gas profiles are 
%   temperature-dependent and are constructed using KNMI weather 
%   observations from De Bilt.
%
% Workflow:
%   1. Load electricity profiles (15-min resolution) and extract E1A, E3B.
%   2. Load gas profile parameters (TST, RER, TOP) for G1A, G2C (1-hr resolution).
%   3. Load KNMI hourly weather data (temperature, wind speed) and convert
%      from UTC to CET/CEST.
%   4. Calculate daily effective temperature (TAC) per local-time day.
%   5. Compute temperature-dependent gas profiles: TAP = RER*(TST-TAC) 
%      when TAC < TST, then VP = TOP + TAP.
%   6. Shift profiles to start at 2024-01-01 00:00 (source data starts at
%      07:00 for gas, 00:15 for electricity).
%   7. Normalize all profiles so each sums to 1.
%   8. Export to CSV:  electricity_profiles.csv, gas_profiles.csv.
%
% Inputs:
%   - profielen aardgas 2024 versie 1.00.csv          (NEDU gas profiles)
%   - Standaardprofielen elektriciteit 2024 versie 1.10.csv (NEDU elec profiles)
%   - knmi de bilt uurgegevens 2021-2026.txt           (KNMI hourly obs)
%
% Outputs:
%   - electricity_profiles.csv  — DateTime (15-min), E1A, E3B (normalized)
%   - gas_profiles.csv          — DateTime (1-hr),   G1A, G2C (normalized)
%
% Profile definitions:
%   E1A  — Residential electricity, AZI (no smart meter), feed-in excluded
%   E3B  — Non-residential electricity, business hours 2000-3000 h/yr
%   G1A  — Residential gas (heating + cooking + hot water)
%   G2C  — Non-residential gas, business hours >1500 h/yr
%
% Time conventions:
%   - Electricity profiles use CET (no DST handling in source file).
%   - Gas profiles use CET label but span 07:00 Jan 1 to 06:00 Jan 1+1.
%   - KNMI data is in UTC; converted to Europe/Amsterdam (CET/CEST).
%   - TAC is computed per local-time calendar day.
%
% Notes:
%   - 2024 is a leap year (366 days, 8784 hours, 35136 quarter-hours).
%   - Gas profiles contain 8785 rows (07:00 Jan 1 – 06:00 Jan 1+1);
%     after shifting, trimmed to 8784 rows covering the calendar year.
%   - Raw profile sums deviate from 1 due to rounding (electricity) and
%     weather dependence (gas). All profiles are renormalized to sum to 1.

function [elecCsvPath, gasCsvPath] = step01_generate_normalized_demand_profiles(debug_mode, inputsDir, outDir)
    %% Load and process electricity profiles

    % Load electricity profiles and extract date and E1A/E3B profile columns
    elec_profiles = readtable(fullfile(inputsDir,'Standaardprofielen elektriciteit 2024 versie 1.10.csv'));
    cols = [1, 2, 3, 4, width(elec_profiles)-7];
    elecExtract = elec_profiles(:, cols);

    % Assign new column names, convert to date/time format
    elecExtract.Properties.VariableNames = {'Date/time CET', 'Date/time CEST from', 'Date/time CEST to', 'E1A AZI-A', 'E3B AZI-A'};

    % Extract E1A and E3B columns
    E1A = elec_profiles{:,4}; % E1A AZI-A profile for residential connections, assuming no feed-in
    E3B = elec_profiles{:,5}; % E3B AZI-A profile for non-residential connections, assuming no feed-in and business hours >2000 and <3000


    %% Load gas profiles

    % Load gas profiles and extract date and G1A/G2C profile columns
    gasFile = fullfile(inputsDir,'profielen aardgas 2024 versie 1.00.csv');
    opts = detectImportOptions(gasFile, 'NumHeaderLines', 6);
    gas_profiles = readtable(gasFile, opts);
    numCols = width(gas_profiles);
    cols = [1:6, numCols-2:numCols];
    gasExtract = gas_profiles(:, cols);


    % Assign new column names as needed, for example:
    gasExtract.Properties.VariableNames = {'Date/time_CET', 'Date/time_CEST_from', ...
    'Date/time_CEST_to', 'G1A_TST', 'G1A_RER', 'G1A_TOP', 'G2C_TST', 'G2C_RER', 'G2C_TOP'};


    %% Load and process weather data to calculate daily effective average temperature (TAC)

    % Load weather data for De Bilt from KNMI, extracting date, temperature, and wind speed
    weatherFile = fullfile(inputsDir,'knmi de bilt uurgegevens 2021-2026.txt');
    opts = detectImportOptions(weatherFile, 'Delimiter', ',');
    opts.DataLines = [32 Inf];
    opts.CommentStyle = '#';
    knmiData = readtable(weatherFile, opts);

    % Convert numeric YYYYMMDD to string and then to datetime
    dateStrings = string(knmiData.YYYYMMDD);
    knmiData.Date = datetime(dateStrings, 'InputFormat', 'yyyyMMdd');

    % Process the data to only keep the necessary columns and convert units
    knmiData = movevars(knmiData, 'Date', 'Before', 1);
    knmiData.FH = knmiData.FH / 10;
    knmiData.T = knmiData.T / 10;
    knmiData = knmiData(:, {'Date', 'HH', 'FH', 'T'});
    knmiData.Properties.VariableNames = {'Date', 'Hour', 'Wind_speed_m_s', 'Temperature_C'};
    % knmiData = knmiData(year(knmiData.Date) == 2024, :);


    %% Process gas profiles to calculate temperature-dependent profile (TAP) based on TAC and TST/RER

    % 1. Convert KNMI data from UT to CET/CEST
    % Create datetime with hour from KNMI data (UT timezone)
    knmiData.DateTime_UT = knmiData.Date + hours(knmiData.Hour - 1); % Hour 1 = 00:00-01:00
    knmiData.DateTime_UT.TimeZone = 'UTC';

    % Convert to Europe/Amsterdam timezone (handles CET/CEST automatically)
    knmiData.DateTime_Local = knmiData.DateTime_UT;
    knmiData.DateTime_Local.TimeZone = 'Europe/Amsterdam';

    % 2. Extract date in local time for grouping
    knmiData.Date_Local = dateshift(knmiData.DateTime_Local, 'start', 'day');

    % 3. Calculate daily averages in local time
    dailyStats = varfun(@mean, knmiData, ...
        'InputVariables', {'Temperature_C', 'Wind_speed_m_s'}, ...
        'GroupingVariables', 'Date_Local');
        
    dailyStats.TAC = (dailyStats.mean_Temperature_C - dailyStats.mean_Wind_speed_m_s) / 1.5;

    % 4. Convert gas profile datetime to proper datetime format
    gasExtract.DateTime_Local = datetime(gasExtract.('Date/time_CET'), 'InputFormat', 'yyyy-MM-dd HH:mm');
    gasExtract.DateTime_Local.TimeZone = 'Europe/Amsterdam';
    gasExtract.Date_Local = dateshift(gasExtract.DateTime_Local, 'start', 'day');

    % 5. Join TAC to gas profile by matching dates
    gasExtract = innerjoin(gasExtract, dailyStats(:, {'Date_Local', 'TAC'}), ...
        'Keys', 'Date_Local');

    % Calculate G1A_TAP: TAP = RER*(TST-TAC) if TAC<TST, else 0
    G1A_TAP = zeros(height(gasExtract), 1);
    mask1 = gasExtract.TAC < gasExtract.G1A_TST;
    G1A_TAP(mask1) = gasExtract.G1A_RER(mask1) .* (gasExtract.G1A_TST(mask1) - gasExtract.TAC(mask1));
    gasExtract.G1A_TAP = G1A_TAP;

    % Calculate G2C_TAP: TAP = RER*(TST-TAC) if TAC<TST, else 0
    G2C_TAP = zeros(height(gasExtract), 1);
    mask2 = gasExtract.TAC < gasExtract.G2C_TST;
    G2C_TAP(mask2) = gasExtract.G2C_RER(mask2) .* (gasExtract.G2C_TST(mask2) - gasExtract.TAC(mask2));
    gasExtract.G2C_TAP = G2C_TAP;

    % Calculate G1A and G2C profiles (VP = TOP + TAP)
    gasExtract.G1A = gasExtract.G1A_TOP + gasExtract.G1A_TAP;
    gasExtract.G2C = gasExtract.G2C_TOP + gasExtract.G2C_TAP;


    %% Shift G1A and G2C profiles to start from 00:00 on Jan 1st

    % Original data runs from 2024-01-01 07:00 to 2025-01-01 06:00 (8785 rows including wrap-around)
    % We need to keep only the 2024 calendar year: 2024-01-01 00:00 to 2024-12-31 23:00 (8760 rows)

    G1A = gasExtract.G1A;
    G2C = gasExtract.G2C;

    % Shift by 7 hours to align to 00:00
    hours_to_shift = 7;
    G1A_shifted = [G1A(end-hours_to_shift+1:end); G1A(1:end-hours_to_shift)];
    G2C_shifted = [G2C(end-hours_to_shift+1:end); G2C(1:end-hours_to_shift)];

    % Extrapolate final entry to maintain 8784 rows (2024 calendar year) after shifting
    G1A_shifted = [G1A_shifted; G1A_shifted(end-23) * (G1A_shifted(end) / G1A_shifted(end-24))];
    G2C_shifted = [G2C_shifted; G2C_shifted(end-23) * (G2C_shifted(end) / G2C_shifted(end-24))];

    % Add one row to gasExtract with new values
    new_datetime = gasExtract.DateTime_Local(end) + hours(1);
    new_row = gasExtract(end, :); % Copy last row as template
    new_row.DateTime_Local = new_datetime;
    new_row.Date_Local = dateshift(new_datetime, 'start', 'day');
    new_row.G1A = G1A_shifted(end);
    new_row.G2C = G2C_shifted(end);

    gasExtract = [gasExtract; new_row];

    % Create proper datetime from 2024-01-01 00:00 to 2024-12-31 23:00
    start_datetime = datetime(2024, 1, 1, 0, 0, 0);
    start_datetime.TimeZone = 'Europe/Amsterdam';
    DateTime_Local_shifted = start_datetime + hours(0:8783)';

    % Update gasExtract
    gasExtract = gasExtract(1:8784, :);
    gasExtract.DateTime_Local = DateTime_Local_shifted;
    gasExtract.Date_Local = dateshift(gasExtract.DateTime_Local, 'start', 'day');
    gasExtract.G1A = G1A_shifted;
    gasExtract.G2C = G2C_shifted;

    G1A = gasExtract.G1A;
    G2C = gasExtract.G2C;

    if debug_mode==true
        % Verify the shift
        disp(['G1A starts at: ', string(gasExtract.DateTime_Local(1))]);
        disp(['G2C starts at: ', string(gasExtract.DateTime_Local(1))]);
        disp(['G1A ends at: ', string(gasExtract.DateTime_Local(end))]);
        disp(['G2C ends at: ', string(gasExtract.DateTime_Local(end))]);
    end


    %% Shift the last item in electricity profiles to the beginning and set correct datetime

    % Shift E1A and E3B by moving the last row to the front
    E1A_shifted = [E1A(end); E1A(1:end-1)];
    E3B_shifted = [E3B(end); E3B(1:end-1)];

    % Create proper datetime starting from 2024-01-01 00:00 with 15-minute intervals
    start_datetime = datetime(2024, 1, 1, 0, 0, 0);
    num_rows = length(E1A_shifted);
    dateTimeCET_shifted = start_datetime + minutes(15*(0:num_rows-1))';

    % Update E1A and E3B
    E1A = E1A_shifted;
    E3B = E3B_shifted;
    dateTimeCET = dateTimeCET_shifted;

    % Update elecExtract table
    elecExtract.DateTime = dateTimeCET;
    elecExtract.E1A = E1A;
    elecExtract.E3B = E3B;

    if debug_mode==true
        disp(['E1A starts at: ', string(dateTimeCET(1))]);
        disp(['E3B starts at: ', string(dateTimeCET(1))]);
        disp(['E1A ends at: ', string(dateTimeCET(end))]);
    end


    %% Normalize profiles to sum = 1

    profiles = {E1A, E3B, G1A, G2C};
    names = {'E1A', 'E3B', 'G1A', 'G2C'};
    for i = 1:numel(profiles)
        s = sum(profiles{i}, 'omitnan');
        profiles{i} = profiles{i} / s;
        if debug_mode
            disp(['Sum of ', names{i}, ' (normalized): ', num2str(sum(profiles{i}, 'omitnan'))]);
        end
    end
    [E1A, E3B, G1A, G2C] = profiles{:};

    if debug_mode==true
        disp(['Normalized sum of E1A: ', num2str(sum(E1A, 'omitnan'))]);
        disp(['Normalized sum of E3B: ', num2str(sum(E3B, 'omitnan'))]);
        disp(['Normalized sum of G1A: ', num2str(sum(G1A, 'omitnan'))]);
        disp(['Normalized sum of G2C: ', num2str(sum(G2C, 'omitnan'))]);
    end

    % Update the tables with normalized profiles
    elecExtract.E1A_normalized = E1A;
    elecExtract.E3B_normalized = E3B;
    gasExtract.G1A_normalized = G1A;
    gasExtract.G2C_normalized = G2C;


    %% Export profiles to CSV files

    % Replace each plot block with:
    if debug_mode
        plot_profile(dateTimeCET, E1A, 'E1A Profile', 'b');
        plot_profile(dateTimeCET, E3B, 'E3B Profile', 'r');
        plot_profile(gasExtract.DateTime_Local, G1A, 'G1A Profile', 'b');
        plot_profile(gasExtract.DateTime_Local, G2C, 'G2C Profile', 'r');
    end

    % Add at the end of the file:
    function plot_profile(dt, data, label, color)
        figure;
        plot(dt, data, color);
        xlabel('Date/time');
        ylabel(label);
        title([label, ' vs Date/time']);
        xlim tight;
        grid on;
    end

    % Create electricity profile table
    elec_output = table(dateTimeCET, E1A, E3B, 'VariableNames', {'DateTime', 'E1A', 'E3B'});

    % Create gas profile table
    gas_output = table(gasExtract.DateTime_Local, G1A, G2C, 'VariableNames', {'DateTime', 'G1A', 'G2C'});

   if ~exist(outDir,'dir'); mkdir(outDir); end

    elecCsvPath = fullfile(outDir,'electricity_profiles.csv');
    gasCsvPath  = fullfile(outDir,'gas_profiles.csv');
    
    writetable(elec_output, elecCsvPath);
    writetable(gas_output,  gasCsvPath);

    if debug_mode==true
        disp('CSV files exported successfully:');
        disp('  - electricity_profiles.csv');
        disp('  - gas_profiles.csv');
    end
end