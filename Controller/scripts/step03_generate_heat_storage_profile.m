function outCsvPath = step03_generate_heat_storage_profile(debug_mode, inputsDir, outDir)

    fprintf("======================================\n")
    fprintf("------ Heat Generation/Storage -------\n")
    fprintf("======================================\n")

    % Define Parameters
    filename = fullfile(inputsDir,'amersfoort_heat_demand.csv');
    T_hot = 90;           % Supply temperature [°C]
    T_warm = 30;          % Warm Temperature [°C]
    T_cold = 60;          % Return temperature [°C]
    
    porosity = 0.3;
    rho_fluid = 965;      % Density fluid [kg/m^3]
    rho_aquifer = 2640;   % Density Aquifer [kg/m^3]
    cp_fluid = 4205;      % Heat capacity fluid [J/kgK]
    cp_aquifer = 710;      % Heat capacity aquifer [J/kgK]
    rho = rho_fluid*porosity+rho_aquifer*(1-porosity);           % Density [kg/m^3]
    cp = cp_fluid*porosity+cp_aquifer*(1-porosity);            % Specific heat capacity [J/kgK]
    delta_T = T_hot - T_warm; 
    
    permeability = 1500;   % Permeability [mD]
    
    %Well parameter
    u_max = 1/3600; %Maximum flow velocity [m/s]
    r_w = 0.2; %Well radius [m]
    h_w = 100; %height of the well [m]
    
    % Import Data
    Demand = readtable(filename);
    hour = (1:height(Demand))';
    Input = table(hour);
    
    % Convert Heat Demand from Joules to kW
    % (Assuming 1 hour timesteps: J/3.6e6 = kWh/h = kW)
    Input.Heat_Demand_kW = Demand.Heat_Demand_J / 3.6e6;
    
    maxHeat = max(Input.Heat_Demand_kW);
    minHeat = min(Input.Heat_Demand_kW);
    totalHeat = sum(Input.Heat_Demand_kW);
    avgHeat = mean(Input.Heat_Demand_kW);
        
    % Output Maximum and Minimum Heat generated
    fprintf('Maximum Heat Demand: %.2f kW\n', maxHeat);
    fprintf('Minimum Heat Demand: %.2f kW\n', minHeat);
    fprintf('Total Heat Demand:   %.2f kW\n', totalHeat); % Note: If summing kW over hours, unit is kWh
    fprintf('Average Heat Demand: %.2f kW\n', avgHeat);
    
    % --- Energy Calculations ---
    Input.supply_kW = avgHeat * ones(height(Input), 1);
    
    % Calculate the difference (Net Flow)
    % Positive = Surplus (Charge), Negative = Deficit (Discharge)
    difference = Input.supply_kW - Input.Heat_Demand_kW;
    net_flow = difference;
    
    % Split into Save/Take for clarity
    Input.Save_To_Storage = max(difference, 0);
    Input.Take_From_Storage = min(difference, 0);
    
    % Calculate Cumulative Energy Stored
    Input.Total_Stored = cumsum(net_flow);
    
    % Shift Energy Storage to ensure it never drops below zero
    minEnergy = min(Input.Total_Stored);
    if minEnergy < 0
        Input.Total_Stored_shifted = Input.Total_Stored + abs(minEnergy);
    else
        Input.Total_Stored_shifted = Input.Total_Stored; 
    end
    
    maxEnergy = max(Input.Total_Stored_shifted);
    fprintf('Maximum Heat Storage needed: %.2f kWh\n', maxEnergy);

    vis = "off";
    if debug_mode
        vis = "on";
    end
    
    fig1 = figure('Name', 'Energy Analysis', 'Position', [150, 150, 800, 600], 'Visible', vis);
    
    % PLOT 1: Power Balance
    subplot(2, 1, 1);
    hold on; grid on;
    
    % Visualize Discharging (Demand > Supply) and Charging (Supply > Demand) relative to avg
    plot(Input.hour, -Input.Take_From_Storage + avgHeat, 'b-', 'LineWidth', 1, 'DisplayName', 'Discharging');
    plot(Input.hour, -Input.Save_To_Storage + avgHeat, 'r-', 'LineWidth', 1, 'DisplayName', 'Charging');
    plot(Input.hour, Input.supply_kW, '--', 'LineWidth', 2, 'DisplayName', 'Supply (Average)');
    
    title('Hourly Heat Demand vs. Constant Supply');
    xlabel('Hour of the Year');
    ylabel('Power (kW)');
    legend('Location', 'best');
    xlim([1 height(Input)]);
    
    % PLOT 2: State of Charge (Energy)
    subplot(2, 1, 2);
    hold on; grid on;
    
    plot(Input.hour, Input.Total_Stored_shifted, 'Color', [0.1 0.6 0.1], 'LineWidth', 1.5);
    %yline(0, 'k--', 'LineWidth', 1);
    
    title('State of Charge (Total Energy Stored)');
    xlabel('Hour of the Year');
    ylabel('Energy (kWh)'); 
    xlim([1 height(Input)]);
    
    %HIP = V*rho*Cp*deltaT
    %V = HIP/(rho*CP*deltaT)
    Volume_needed = (maxEnergy * 3.6e6) / (rho * cp * delta_T);
    fprintf('Volume needed: %.2f m^3\n', Volume_needed); 
    
    % Well Parameter Calculation
    V_max = u_max * 2 * pi * h_w * r_w;        % Maximum volumetric extraction rate [m^3/s]
    
    % Calculate Power in Watts (J/s) then convert to kW
    Power_Watts = V_max * rho_fluid * cp_fluid * delta_T; 
    Q_max = Power_Watts / 1000;                % [kW]
    
    D_max = max(Input.Heat_Demand_kW);         % Maximum demand [kW]
    num_Wells = D_max / Q_max;
    
    fprintf('Maximum flow rate per well: %.4f m^3/s (%.1f m^3/h)\n', V_max, V_max*3600);
    fprintf('Maximum power per well: %.2f kW\n', Q_max);
    fprintf('Maximum demand: %.2f MW\n', D_max/1000);
    fprintf('Wells needed: %.2f\n', num_Wells);
    
    %% --- HEAT RECOVERY EFFICIENCY (Based on Image Formulas) ---
    
    % 1. Define Missing Constants required by the formula
    % Viscosity of water (Pa.s) at ~60°C (Average of 90°C and 30°C)
    mu_avg = 0.00047; 
    
    % Permeability: Convert from milliDarcy (mD) to m^2
    % 1 mD = 9.869e-16 m^2
    k_m2 = permeability * 9.869e-16; 
    
    %Modified Rayleigh Number (Ra*)
    % Formula: Ra* = 1634 * (rho_fluid * h^2.5 * sqrt(k_h*k_v) * delta_T) / (mu * sqrt(Vi))
    % We assume Horizontal Perm (k_h) = Vertical Perm (k_v), so sqrt(k*k) = k
    % Vi is the annual injected volume (m^3). We use the Theoretical Volume calculated earlier.
    Vi = Volume_needed; 
    
    numerator = 1634 * rho_fluid * (h_w^2.5) * k_m2 * delta_T;
    denominator = mu_avg * sqrt(Vi);
    
    Ra_star = numerator / denominator;
    
    % Calculate Coefficients A and B
    % Coefficient A
    A = 0.82 - (1.7 / h_w);
    
    % Coefficient B (depends on height ranges in the image)
    if h_w < 60
        B = (-1.2 / (h_w^1.35)) + 0.0022;
    elseif h_w >= 60 && h_w < 200
        B = -2.7 / (h_w^1.7);
    else
        % Fallback for h > 200 (using the 60-200 formula as approximation)
        B = -2.7 / (h_w^1.7); 
        warning('Well height is outside the explicit range defined in the formula.');
    end
    
    % Calculate Recovery Efficiency (eta)
    % Formula: eta = A * exp(B * Ra*)
    eta = A * exp(B * Ra_star);
    
    % Recalculate Volume based on Efficiency
    % If efficiency is 70%, you need to store more water to get the same heat out.
    Real_Volume_Needed = Volume_needed / eta;
    
    %% --- FINAL OUTPUTS ---
    
    fprintf('     RECOVERY EFFICIENCY RESULTS     \n');
    
    fprintf('Modified Rayleigh Number (Ra*): %.2f\n', Ra_star);
    fprintf('Calculated Efficiency (eta):    %.2f%%\n', eta * 100);
    fprintf('----------------------------------------\n');
    fprintf('Theoretical Volume:   %.0f m^3\n', Volume_needed);
    fprintf('ACTUAL Volume Needed: %.0f m^3 (adjusted for loss)\n', Real_Volume_Needed);
    
    
    %HIP = V*rho*Cp*deltaT
    %V = HIP/(rho*CP*deltaT)
    Volume_needed = (maxEnergy * 3.6e6) / (rho * cp * delta_T);
    %fprintf('Volume needed: %.2f m^3\n', Volume_needed); 
    
    % Well Parameter Calculation
    V_max = u_max * 2 * pi * h_w * r_w;        % Maximum volumetric extraction rate [m^3/s]
    
    % Calculate Power in Watts (J/s) then convert to kW
    Power_Watts = V_max * rho_fluid * cp_fluid * delta_T; 
    Q_max = Power_Watts / 1000;                % [kW]
    
    D_max = max(Input.Heat_Demand_kW);         % Maximum demand [kW]
    num_Wells = D_max / Q_max;
    
    fprintf('Maximum flow rate per well: %.4f m^3/s (%.1f m^3/h)\n', V_max, V_max*3600);
    fprintf('Maximum power per well: %.2f kW\n', Q_max);
    fprintf('Maximum demand: %.2f MW\n', D_max/1000);
    fprintf('Wells needed: %.2f\n', num_Wells);
    
    %HYDRAULIC & THERMAL DIMENSIONS
    
    % Thermal Radius (R_th) [m]
    % Formula: R_th = sqrt( (rho_f * Cf * V) / (rho_alpha * C_alpha * pi * h) )
    
    % Volumetric Heat Capacities [J / (m^3 K)]
    VC_fluid = rho_fluid * cp_fluid; 
    VC_aquifer_bulk = porosity * VC_fluid + (1-porosity) * rho_aquifer * cp_aquifer;
    
    numerator_R = VC_fluid * Real_Volume_Needed;
    denominator_R = VC_aquifer_bulk * pi * h_w;
    
    R_th = sqrt(numerator_R / denominator_R);
    
    
    % Pressure Drop (Delta P) [Pa]
    % Formula: Delta P = (Q * mu * ln(L/r_w)) / (2 * pi * k * h)
    L = 2 * R_th; 
    
    % Q: Flow rate per well [m^3/s]
    Q_well = V_max; 
    
    numerator_P = Q_well * mu_avg * log(L / r_w);
    denominator_P = 2 * pi * k_m2 * h_w;
    
    Delta_P_Pa = numerator_P / denominator_P; % Pressure in Pascal
    Delta_P_Bar = Delta_P_Pa / 1e5;           % Convert to Bar (1 Bar = 100,000 Pa)
    
    
    % FINAL OUTPUTS
    
    fprintf('     HYDRAULIC & THERMAL ANALYSIS    \n');
    
    fprintf('Thermal Radius (R_th):    %.2f m\n', R_th);
    fprintf('Assumed Well Spacing (L): %.2f m\n', L);
    fprintf('----------------------------------------\n');
    fprintf('Pressure Drop per Well:   %.2f Pa\n', Delta_P_Pa);
    fprintf('Pressure Drop per Well:   %.2f Bar\n', Delta_P_Bar);
    
    %PUMPING ENERGY CALCULATION
    
    % Combined Pump & Motor Efficiency (Change once real equipment is chosen)
    eta_pump = 0.70; 
    
    % Calculate Flow Rate for Every Hour [m^3/s]
    % Flow = Power / (rho * cp * DeltaT)
    
    Hourly_Flow_m3s = abs(Input.supply_kW - Input.Heat_Demand_kW) * 1000 ./ (rho_fluid * cp_fluid * delta_T);
    
    % Calculate Pressure Drop (Dynamic)
    % Pressure drop is proportional to Flow Rate (Darcy-Weisbach).
    Input.Delta_P_hourly = Delta_P_Pa * (Hourly_Flow_m3s / V_max);
    
    
    % Calculate Electric Power for Each Hour [kW]
    % Power (Watts) = (Pressure_Pa * Flow_m3s) / Efficiency
    Input.Hourly_Pump_Power_kW = (Input.Delta_P_hourly .* Hourly_Flow_m3s) ./ eta_pump / 1000;
    
    
    % Sum for Annual Energy [kWh]
    Total_Pump_Energy_kWh = sum(Input.Hourly_Pump_Power_kW);
    
    
    %  Calculate Costs
    % (Change to actual prices)
    Elec_Price = 0.15; 
    Total_Pump_Cost = Total_Pump_Energy_kWh * Elec_Price;
    
    
    %PUMPING OUTPUTS
    
    fprintf('     PUMPING ENERGY ANALYSIS       \n');
    
    fprintf('Assumed Pump Efficiency:  %.2f%%\n', eta_pump * 100);
    fprintf('Total Pump Energy/Year:   %.2f MWh\n', Total_Pump_Energy_kWh / 1000);
    %fprintf('Estimated Annual Cost:    € %.2f\n', Total_Pump_Cost);
    fprintf('----------------------------------------\n');
    % Comparison: Energy In vs Energy Used
    fprintf('Pumping Energy/Heat Energy: %.2f%%\n', (Total_Pump_Energy_kWh / totalHeat) * 100);
    
    % RECALCULATION WITH EFFICIENCY LOSSES
    
    
    fprintf('   CORRECTED SUPPLY & STORAGE SIZING    \n');
    
    
    % Calculate the New Required Supply [kW]
    % To meet demand with losses, we must increase the constant supply
    % from the "Average Demand" to "Average Demand / Efficiency".
    Required_Supply_kW = avgHeat / eta;
    
    fprintf('Original Supply (Ideal):  %.2f kW\n', avgHeat);
    fprintf('Required Supply (Real):   %.2f kW\n', Required_Supply_kW);
    fprintf('Extra Source Capacity:    %.2f kW\n', Required_Supply_kW - avgHeat);
    
    
    % Recalculate Storage Balance with New Supply
    % We repeat the energy balance calc with the higher supply value.
    % Calculate the adjustment factor dynamically
    demand = Input.Heat_Demand_kW;
    factor = (demand <= 0) .* eta + (demand > 0) .* (1/eta);
    
    % Apply it to flow equation
    Input.Real_Net_Flow = Required_Supply_kW - (demand .* factor);
    
    % Calculate the new cumulative storage curve
    Input.Real_Total_Stored = cumsum(Input.Real_Net_Flow);
    
    % Shift so minimum is 0
    minRealEnergy = min(Input.Real_Total_Stored);
    if minRealEnergy < 0
        Input.Real_Total_Stored_shifted = Input.Real_Total_Stored + abs(minRealEnergy);
    else
        Input.Real_Total_Stored_shifted = Input.Real_Total_Stored; 
    end
    
    % New Maximum Storage Needed
    Real_Max_Energy_kWh = max(Input.Real_Total_Stored_shifted);
    
    % New Volume Needed
    Real_Volume_Actual = (Real_Max_Energy_kWh * 3.6e6) / (rho * cp * delta_T);
    
    
    
    fprintf('Original Storage Need:    %.2f MWh\n', maxEnergy / 1000);
    fprintf('Real Storage Need:        %.2f MWh\n', Real_Max_Energy_kWh / 1000);
    fprintf('----------------------------------------\n');
    fprintf('Original Volume:          %.0f m^3\n', Volume_needed);
    fprintf('Real Volume Required:     %.0f m^3\n', Real_Volume_Actual);
    
    
    
    % PLOT THE DIFFERENCE
    fig2 = figure('Name', 'Ideal vs Real Storage', 'Position', [150, 150, 800, 400], 'Visible', vis);
    hold on; grid on;
    plot(Input.hour, Input.Total_Stored_shifted, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Ideal (100% Eff)');
    plot(Input.hour, Input.Real_Total_Stored_shifted, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Real (w/ Losses)');
    yline(abs(minRealEnergy), 'k--', 'LineWidth', 1);
    title('Impact of Efficiency on Storage Volume');
    xlabel('Hour'); ylabel('Energy Stored (kWh)');
    legend('Location', 'best');
    
    %EXPORT DATA TO CSV
    
    % Define Conversion Factors
    % Factor to convert Power (kW) to Water Flow (m^3/h)
    % Logic: Flow = Power / (rho_fluid * cp_fluid * delta_T)
    % Units: (kW * 1000 * 3600) / (J/m^3K * K) = m^3/h
    kW_to_m3h_fluid = (1000 * 3600) / (rho_fluid * cp_fluid * delta_T);
    
    % Factor to convert Energy (kWh) to Aquifer Volume (m^3)
    % Logic: Vol = Energy / (rho_bulk * cp_bulk * delta_T)
    % Units: (kWh * 3.6e6) / (J/m^3K * K) = m^3
    kWh_to_m3_aquifer = 3.6e6 / (rho * cp * delta_T);
    
    
    % Prepare Data Vectors
    % Expand scalar Supply to a vector for the table
    Vector_Supply_Real = Required_Supply_kW * ones(height(Input), 1);
    
    % Calculate Water Volume Flows (Positive = Into Storage, Negative = Out of Storage)
    Input.Flow_Optimal_m3h = (Input.supply_kW - Input.Heat_Demand_kW) * kW_to_m3h_fluid;
    Input.Flow_Real_m3h    = Input.Real_Net_Flow * kW_to_m3h_fluid; 
    
    % Calculate Physical Storage Volume (The size of the hot 'bubble' in the ground)
    Input.Vol_Stored_Optimal_m3 = Input.Total_Stored_shifted * kWh_to_m3_aquifer;
    Input.Vol_Stored_Real_m3    = Input.Real_Total_Stored_shifted * kWh_to_m3_aquifer;
    
    
    % Create the Final Output Table
    Output = table();
    
    % Group 1: General Info
    Output.Hour = Input.hour;
    Output.Heat_Demand_kW = Input.Heat_Demand_kW;
    
    % Group 2: Optimal Scenario (100% Efficiency)
    Output.Opt_Supply_kW        = Input.supply_kW;
    Output.Opt_Storage_kWh      = Input.Total_Stored_shifted;
    Output.Opt_Water_Flow_m3h   = Input.Flow_Optimal_m3h;       % (+ Charge / - Discharge)
    Output.Opt_Aquifer_Vol_m3   = Input.Vol_Stored_Optimal_m3;  % Current size of hot zone
    
    % Group 3: Real Scenario (With Efficiency Losses)
    Output.Real_Supply_kW       = Vector_Supply_Real;
    Output.Real_Storage_kWh     = Input.Real_Total_Stored_shifted;
    Output.Real_Water_Flow_m3h  = Input.Flow_Real_m3h;
    Output.Real_Aquifer_Vol_m3  = Input.Vol_Stored_Real_m3;
    Output.Estimated_Pump_Power_kW = Input.Hourly_Pump_Power_kW;
    
    
    % Write to CSV
    out = fullfile(outDir,"Amersfoort_Hourly_Data.csv");
    writetable(Output, out);

    NewT = table(Output.Hour, Output.Estimated_Pump_Power_kW * 3.6e6, ... % Convert kW to J
    'VariableNames', {'Hours','Estimated_Pump_Power_J'});

    outCsvPath = fullfile(outDir,"Heat_pump_storage_demand.csv");
    writetable(NewT, outCsvPath);
    
    fprintf('Data successfully exported to:\n%s\n', outCsvPath);
    
    % Preview the first 5 rows in Command Window
    %head(Output, 5)
    
    Param_Names = {
        'SYSTEM EFFICIENCY';
        'Thermal Recovery Efficiency (eta)';
        'Modified Rayleigh Number (Ra*)';
        ' '; % Empty row for spacing
        'WELL CONFIGURATION';
        'Number of Wells Needed';
        'Max Flow Rate per Well';
        'Well Spacing (L)';
        'Thermal Radius (R_th)';
        ' ';
        'STORAGE DIMENSIONS';
        'Max Heat Demand';
        'Max Storage Capacity (Real)';
        'Aquifer Volume Required (Real)';
        ' ';
        'ECONOMICS & ENERGY';
        'Total Pump Energy per Year';
        'Pump Energy vs Heat Energy';
        'Estimated Pump Cost'
    };
    
    Param_Values = [
        NaN;                        % Header
        eta * 100;
        Ra_star;
        NaN;                        % Spacer
        NaN;                        % Header
        num_Wells;
        V_max * 3600;               % Convert m3/s to m3/h
        L;
        R_th;
        NaN;                        % Spacer
        NaN;                        % Header
        D_max;
        Real_Max_Energy_kWh / 1000; % Convert to MWh
        Real_Volume_Actual;
        NaN;                        % Spacer
        NaN;                        % Header
        Total_Pump_Energy_kWh / 1000; % MWh
        (Total_Pump_Energy_kWh / totalHeat) * 100;
        Total_Pump_Cost
    ];
    
    Param_Units = {
        '';
        '%';
        '-';
        '';
        '';
        'Doublets';
        'm^3/h';
        'm';
        'm';
        '';
        '';
        'kW';
        'MWh';
        'm^3';
        '';
        '';
        'MWh/yr';
        '%';
        'EUR/yr'
    };
    
    % Create the table
    SummaryTable = table(Param_Names, Param_Values, Param_Units, ...
        'VariableNames', {'Parameter', 'Value', 'Unit'});
    
    % 3. Export the Summary File
    output_filename_summary = fullfile(outDir, 'Amersfoort_Key_Parameters.csv');
    writetable(SummaryTable, output_filename_summary);
    
    
    %FINAL COMPLETION MESSAGE
    
    fprintf('     EXPORT SUCCESSFUL \n');
    
    fprintf('1. Time Series Data:  %s\n', outCsvPath);
    fprintf('2. System Summary:    %s\n', output_filename_summary);
    
    
    % Show the summary in the Command Window for a quick check
    disp(SummaryTable);
    
    filename_xls = fullfile(outDir, 'Amersfoort_Heat_Storage_Full_Report.xlsx');
    writetable(SummaryTable, filename_xls, 'Sheet', 'Summary');
    writetable(Output, filename_xls, 'Sheet', 'Hourly_Data');
    
    %PLOT EXPORTS    
    fig3 = figure('Name', 'Energy Analysis', 'Position', [150, 150, 800, 600], 'Visible', vis);
    
    % PLOT 1: Power Balance
    subplot(2, 1, 1);
    hold on; grid on;
    
    % Visualize Discharging (Demand > Supply) and Charging (Supply > Demand) relative to avg
    plot(Input.hour, -Input.Take_From_Storage + avgHeat, 'b-', 'LineWidth', 1, 'DisplayName', 'Discharging');
    plot(Input.hour, -Input.Save_To_Storage + avgHeat, 'r-', 'LineWidth', 1, 'DisplayName', 'Charging');
    plot(Input.hour, Input.supply_kW, '--', 'LineWidth', 2, 'DisplayName', 'Supply (Average)');
    
    title('Hourly Heat Demand vs. Constant Supply');
    xlabel('Hour of the Year');
    ylabel('Power (kW)');
    legend('Location', 'best');
    xlim([1 height(Input)]);
    
    % PLOT 2: State of Charge (Energy)
    subplot(2, 1, 2);
    hold on; grid on;
    
    plot(Input.hour, Input.Total_Stored_shifted, 'Color', [0.1 0.6 0.1], 'LineWidth', 1.5);
    %yline(0, 'k--', 'LineWidth', 1);
    
    title('State of Charge (Total Energy Stored)');
    xlabel('Hour of the Year');
    ylabel('Energy (kWh)'); 
    xlim([1 height(Input)]);
    
    outFile1 = fullfile(outDir, "ATES_Energy_Analysis.png");
    print(fig1, outFile1, '-dpng', '-r300'); %Save to png

    if ~debug_mode
        close(fig1);
    end
    
    
    
    fig4 = figure('Name', 'Ideal vs Real Storage', 'Position', [150, 150, 800, 400], 'Visible', vis);
    hold on; grid on;
    plot(Input.hour, Input.Total_Stored_shifted, 'b--', 'LineWidth', 1.5, 'DisplayName', 'Ideal (100% Eff)');
    plot(Input.hour, Input.Real_Total_Stored_shifted, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Real (w/ Losses)');
    yline(abs(minRealEnergy), 'k--', 'LineWidth', 1);
    title('Impact of Efficiency on Storage Volume');
    xlabel('Hour'); ylabel('Energy Stored (kWh)');
    legend('Location', 'best');
    
    outFile4 = fullfile(outDir,"ATES_Efficiency_Impact.png");
    print(fig4, outFile4, '-dpng', '-r300');

    if ~debug_mode
        close(fig4);
    end
    
    % ADDITIONAL PLOTS
    
    %Load Duration Curve
    fig5 = figure('Name', 'Load Duration Curve', 'Position', [150, 150, 800, 600], 'Visible', vis);
    hold on; grid on;
    
    % Sort demand from highest to lowest
    sorted_demand = sort(Input.Heat_Demand_kW, 'descend');
    hours_axis = 1:length(sorted_demand);
    
    % Plot Demand
    plot(hours_axis, sorted_demand, 'k-', 'LineWidth', 2, 'DisplayName', 'Heat Demand');
    
    % Plot Optimal Supply Line
    yline(Input.supply_kW(1), 'r--', 'LineWidth', 2, 'DisplayName', 'Base Load Supply');
    
    title('Load Duration Curve');
    xlabel('Hours per Year');
    ylabel('Thermal Power (kW)');
    legend('Location', 'best');
    xlim([0 8760]);
    
    % Save Plot 3
    outFile5 = fullfile(outDir, 'ATES_Load_Duration.png');
    print(fig5, outFile5, '-dpng', '-r300');

    if ~debug_mode
        close(fig5);
    end
    
    
    
    % Monthly Energy Balance
    fig6 = figure('Name', 'Monthly Balance', 'Position', [150, 150, 800, 600], 'Visible', vis);
    
    time_vec = (datetime(2024,1,1,0,0,0) : hours(1) : datetime(2024,12,31,23,0,0))';
    months = month(time_vec);
    
    % Sum flows per month
    monthly_net_flow = zeros(12, 1);
    for m = 1:12
        % Sum the Real Net Flow (Energy into/out of ground) for month m
        monthly_net_flow(m) = sum(Input.Real_Net_Flow(months == m));
    end
    
    % Plot Bar Chart
    b = bar(1:12, monthly_net_flow / 1000); % Convert to MWh
    b.FaceColor = 'flat';
    b.CData(monthly_net_flow > 0, :) = repmat([1 0 0], sum(monthly_net_flow > 0), 1); % Red for Charging
    b.CData(monthly_net_flow < 0, :) = repmat([0 0 1], sum(monthly_net_flow < 0), 1); % Blue for Discharging
    
    grid on;
    title('Monthly Energy Balance (Net Flow)');
    xlabel('Month');
    ylabel('Net Energy Stored (MWh)');
    xticks(1:12);
    xticklabels({'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'});
    legend('Positive = Charging (Summer)', 'Negative = Discharging (Winter)', 'Location', 'northwest');
    
    % Save Plot
    outFile6 = fullfile(outDir, 'ATES_Monthly_Balance.png');
    print(fig6, outFile6, '-dpng', '-r300');

    if ~debug_mode
        close(fig6);
    end
    
    
    % Physical Footprint (Top-Down View)
    fig7 = figure('Name', 'Well Layout', 'Position', [150, 150, 600, 600], 'Visible', vis);
    hold on; axis equal; grid on;
    
    % Define Centers
    warm_well = [-L/2, 0];
    cold_well = [L/2, 0];
    
    % Draw Wells (Points)
    plot(warm_well(1), warm_well(2), 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
    plot(cold_well(1), cold_well(2), 'bo', 'MarkerSize', 10, 'MarkerFaceColor', 'b');
    
    % Draw Thermal Radius (Circles)
    theta = linspace(0, 2*pi, 100);
    x_circle = R_th * cos(theta);
    y_circle = R_th * sin(theta);
    
    % Warm Plume
    fill(warm_well(1) + x_circle, warm_well(2) + y_circle, 'r', 'FaceAlpha', 0.1, 'EdgeColor', 'r');
    % Cold Plume
    fill(cold_well(1) + x_circle, cold_well(2) + y_circle, 'b', 'FaceAlpha', 0.1, 'EdgeColor', 'b');
    
    % Labels
    text(warm_well(1), warm_well(2)+R_th*1.2, 'Warm Well', 'HorizontalAlignment', 'center');
    text(cold_well(1), cold_well(2)+R_th*1.2, 'Cold Well', 'HorizontalAlignment', 'center');
    plot([warm_well(1), cold_well(1)], [0, 0], 'k--', 'DisplayName', sprintf('Spacing L = %.0f m', L));
    
    title('Top-Down View of Thermal Plumes');
    xlabel('Distance (m)');
    ylabel('Distance (m)');
    legend('Warm Well', 'Cold Well', 'Thermal Plume', 'Thermal Plume', 'Spacing');
    
    % Save Plot
    outFile7 = fullfile(outDir, 'ATES_Well_Layout.png');
    print(fig7, outFile7, '-dpng', '-r300');

    if ~debug_mode
        close(fig7);
    end
end
