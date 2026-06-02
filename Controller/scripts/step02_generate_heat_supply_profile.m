function HeatSupplyCsv = step02_generate_heat_supply_profile(outDir)

    fprintf("============================\n")
    fprintf("------ Geothermal System Design  -------\n")
    fprintf("============================\n")

    %% Geothermal System Design
    
    % Parameters
    annual_target_MWh = 757169.02;
    depth = 2500;           % m
    L_spacing = 1500;       % m (well spacing)
    phi = 0.20;             % porosity
    rho_r = 2650;           % kg/m3
    rho_f = 1000;           % kg/m3
    Cr = 800;               % J/kgK
    Cf = 4180;              % J/kgK
    T_surf = 10;            % C
    grad = 0.0313;          % C/m
    Ti = 35;                % Injection temp C
    num_doublets = 5;       % N
    H_thickness = 65.5;     % Calculated thickness in meters
    
    % Power and Flow Calculations
    T0 = T_surf + (grad * depth);
    delta_T = T0 - Ti;
    P_th_total_W = (annual_target_MWh * 1e6) / 8760; % Continuous Power (W)
    Q_total_m3s = P_th_total_W / (rho_f * Cf * delta_T);
    
    % Total Extractable Heat
    % A = Total area of all doublets
    A_total = num_doublets * (L_spacing^2); 
    Q_total_extract_J = A_total * H_thickness * ((1-phi)*rho_r*Cr + phi*rho_f*Cf) * delta_T;
    
    % Lifetime Calculation
    t_sec = (H_thickness * A_total * (phi*rho_f*Cf + (1-phi)*rho_r*Cr)) / (rho_f * Cf * Q_total_m3s);
    t_years = t_sec / (365.25 * 24 * 3600);
    
    % Pumping Power (assuming 40 bar drop, 75% efficiency)
    P_pump = (Q_total_m3s * 40e5) / 0.75; 
    
    % Visualization
    hours = (1:8784)';
    gen_MW = (P_th_total_W / 1e6) * ones(size(hours));
    cum_gen_MWh = cumsum(gen_MW);
    
    % figure('Color', 'w');
    % subplot(2,1,1);
    % plot(hours, gen_MW, 'r', 'LineWidth', 1.5);
    % title('Annual Power Generation Profile (MW_{th})');
    % ylabel('MW'); grid on;
    % 
    % subplot(2,1,2);
    % plot(hours, cum_gen_MWh, 'b', 'LineWidth', 2);
    % title('Cumulative Heat Production (MWh_{th})');
    % ylabel('MWh'); xlabel('Hours'); grid on;
    % yline(annual_target_MWh, '--k', 'Annual Target');
    
    % Outputs
    fprintf('Geothermal Design\n');
    fprintf('Reservoir Temp: %.2f C\n', T0);
    fprintf('Number of Doublets: %.2f C\n', num_doublets);
    fprintf('Total Flow Rate: %.2f m3/h\n', Q_total_m3s * 3600);
    fprintf('Flow per Doublet: %.2f m3/h\n', (Q_total_m3s * 3600)/num_doublets);
    fprintf('System Lifetime: %.2f years\n', t_years);
    fprintf('Pumping Power: %.2f MW_e\n', P_pump/1e6);
    
    annual_target_MWh = 757169.02;
    COP = 42;   % choose assumed COP
    
    P_th_avg_MW = annual_target_MWh / 8784;     % MW_th
    P_hp_el_avg_MW = P_th_avg_MW / COP;         % MW_e
    Pump_supply = (P_hp_el_avg_MW * 3.6e9) * ones(size(hours));  % in J
    annual_hp_el_MWh = annual_target_MWh / COP; % MWh_e/year
    
    fprintf('Average thermal demand: %.2f MW_th\n', P_th_avg_MW);

    fprintf('Average HP electric power: %.2f MW_e\n', P_hp_el_avg_MW);
    fprintf('Annual HP electricity use: %.2f MWh_e\n', annual_hp_el_MWh);

    hp_th_MW = P_th_avg_MW * ones(size(hours));   % hourly profile (MW_th)
    hp_th_MWh_cum = cumsum(hp_th_MW);             % cumulative MWh_th (1h steps)
    
    % plot(hours, hp_th_MW); grid on
    % xlabel('Hour'); ylabel('MW_{th}');
    % title('Heat pump thermal output profile (constant)');
    
    % Prepare for output
    if ~exist(outDir,'dir'); mkdir(outDir); end
    HeatSupplyCsv = fullfile(outDir,'heat_supply_pump_profiles.csv');
    T = table(hours, Pump_supply, 'VariableNames', {'Hours','Heat_Pump_Electricity_J'});
    writetable(T, HeatSupplyCsv);

end