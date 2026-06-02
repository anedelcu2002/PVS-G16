function [Solar, SolarCsvPath] = step05b_generate_solar_profile_for_1_inverter(inputsDir, outDir)

    fprintf("==============================\n")
    fprintf("------ Solar Generation -------\n")
    fprintf("==============================\n")


    SolarCsvPathInput = fullfile(inputsDir,'Solar_1_Inverter_Profile_2024_hourly.csv');
    T = readtable(SolarCsvPathInput); % in J

    % Parse datetime
    T.DateTime = datetime(T.DateTime, ...
        'InputFormat','dd-MMM-yyyy HH:mm:ss', ...
        'Locale','en_US');

    % Base hourly AC power of ONE inverter block
    P_inv_AC_W = T.P_inv_AC_W;
    E_inv_AC_J = T.E_inv_AC_J;

    % Convert datetime to seconds from start
    t_sec = seconds(T.DateTime - T.DateTime(1));

    % Prepare for output
    if ~exist(outDir,'dir'); mkdir(outDir); end
    SolarCsvPath = fullfile(outDir, sprintf('solar_profiles_1_inverter.csv'));
    X = table(t_sec, E_inv_AC_J, 'VariableNames', {'DateTime','SolarEnergy_J'});
    writetable(X, SolarCsvPath);

    Solar = [t_sec, P_inv_AC_W];

end