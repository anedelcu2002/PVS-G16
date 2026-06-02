function [Load, Pump] = step04_cosumption_sizing(debug_mode, args)

    fprintf("============================\n")
    fprintf("------ Generation sizing -------\n")
    fprintf("============================\n")

    %% Load data import 
   
    electricity_demand_csvPath   = args.elecCsv; % in J
    heat_pump_supply_consumption_csvPath   = args.heatSupplyCsv; % in kW(h)
    heat_pump_storage_consumption_csvPath  = args.heatStorCsv; % in kW(h)
    
    Load = readtable(electricity_demand_csvPath);      % Reads load profile
    Heat_Pump_Supply = readtable(heat_pump_supply_consumption_csvPath);
    Heat_Pump_Storage = readtable(heat_pump_storage_consumption_csvPath);
    
    t = Load{:,1};
    % Convert datetime to seconds
    t_sec = seconds(t - t(1)); % s
    E_load = Load{:,2}; % J
    E_heat_pump_supply = Heat_Pump_Supply{:,2} ; % in J
    E_heat_pump_storage = Heat_Pump_Storage{:,2}; % in J

    E_total_heat_pump_load = E_heat_pump_supply + E_heat_pump_storage; % in J

    Load = [t_sec, E_load /3600]; % in W
    Pump = [t_sec, E_total_heat_pump_load /3600]; % in W

    if debug_mode
        figure;
        plot(t, (E_load+E_total_heat_pump_load)/3600/1e6, 'b');
        xlabel('Date/time');
        ylabel('Hourly electricity demand (MWh)');
        xlim tight;
        grid on;
        fprintf('  Initial electricity demand: %d \n', sum(E_load)/3600/1e9, ' GWh');
        fprintf('  Recalculated electricity demand: %d \n', sum(E_load+E_total_heat_pump_load)/3600/1e9, ' GWh');
    end

end
