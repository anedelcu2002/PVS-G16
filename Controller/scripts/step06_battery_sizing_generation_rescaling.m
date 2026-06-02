function step06_battery_sizing_generation_rescaling(inputs)
    fprintf('==========================================================\n');
    fprintf(' Generation Resizing-Scaling \n ');
    fprintf('==========================================================\n');

    projectRoot = fileparts(fileparts(mfilename('fullpath')));
    wind_outDir    = fullfile(projectRoot,"outputs","step_05a_wind_calculations");
    solar_outDir   = fullfile(projectRoot,"outputs","step_05b_solar_calculations");  

    %% -------------------- Simulation step --------------------
    Ts = 3600;                 % [s] 60 minutes
   
    %% -------------------- Battery "unit" definition --------------------
    % HyperStrong HyperBlock M (AC version) — treat as ONE unit block
    % Rated energy: 12.8 MWh  => 12.8e6 Wh
    % Rated DC voltage: 1331.2 V
    E_unit_Wh = 12.8e6;            % [Wh] per block
    Vnom_unit = 1331.2;            % [V]  per block (DC)
    AH_unit   = E_unit_Wh ./ Vnom_unit;  % [Ah] equivalent per block (~9615 Ah)
    
    % Converter efficiencies (used in energy-balance SoC model)
    effConvBESS = 0.93;
    
    % One-way efficiency approximation for charging/discharging through BESS path
    eta = sqrt(effConvBESS);
    
    %% -------------------- Grid params (kept for consistency) --------------------
    f = 50; %#ok<NASGU>
    V = 400; %#ok<NASGU>
    
    %% =======================================================================
    %  STEP 2: Electrical demand 
    %  =======================================================================    
    Load   = inputs.Load; % in W 
    Pump   = inputs.Pump; % in W 
    Wind   = inputs.Wind; % in W 
    Solar   = inputs.Solar; % in W 

    P_Wind_1turb = Wind(:,2);
    P_Solar_1inv = Solar(:,2);
    E_Wind_1turb = sum(P_Wind_1turb) * 3600; % in J
    E_Solar_1inv = sum(P_Solar_1inv) * 3600; % in J
   
    %% =======================================================================
    %  Scale generation so cumulative net energy ends at ~0 Wh
    %  (ensures Final SoC = Initial SoC with your loss model)
    %  =======================================================================
    fprintf('Scaling generation so cumulative net energy ends at 0 (no drift)...\n');
    
    P_load_all = Load(:,2) + Pump(:,2);      % W
    P_gen_1 = P_Wind_1turb + P_Solar_1inv;     % W 
            

       % Bisection on additional factor lf to force dE(end)=0 using efficiency model
    lf_lo = sum(P_load_all) / max(sum(P_gen_1), eps); % start at a factor without the losses
    lf_hi = 1.40 * lf_lo; 

    for it = 1:40
        lf = (lf_lo + lf_hi)/2;

        P_gen_test = P_gen_1 * lf;
        dE_end = net_energy_end_Wh(P_load_all, P_gen_test, Ts, eta);

        if abs(dE_end) < 1e3   % within 1 kWh 
            fprintf('Generation converged at scale = %3f\n', lf);
            break;
        elseif dE_end < 0
            lf_lo = lf;   % ended deficit => need more generation
        else
            lf_hi = lf;   % ended surplus => too much generation
        end
    end

    E_req_total = sum(P_gen_test) * 3600;   % J

    E_wind_target  = 0.5 * E_req_total;
    E_solar_target = 0.5 * E_req_total;

    N_turb_0 = round(E_wind_target  / E_Wind_1turb);
    N_inv_0  = round(E_solar_target / E_Solar_1inv);

    bestScore = inf;
    
    for Nt = max(1, N_turb_0-3):N_turb_0+3
        for Ni = max(1, N_inv_0-30):N_inv_0+30
    
            Ew = Nt * E_Wind_1turb;
            Es = Ni * E_Solar_1inv;
            Etot = Ew + Es;
    
            share_wind = Ew / Etot;
            share_err = abs(share_wind - 0.5);
    
            P_try = Nt * P_Wind_1turb + Ni * P_Solar_1inv;
            dE = net_energy_end_Wh(P_load_all, P_try, Ts, eta);
    
            % weighted score: prioritize net drift, then 50/50 share
            score = abs(dE) + 1e12 * share_err;
    
            if score < bestScore
                bestScore = score;
                bestNt = Nt;
                bestNi = Ni;
                bestdE = dE;
                bestShareWind = share_wind;
            end
        end
    end

    N_turbines = bestNt;
    N_inverters = bestNi;
    
    Wind(:,2) = N_turbines * P_Wind_1turb;
    Solar(:,2) = N_inverters * P_Solar_1inv;

    if ~exist(wind_outDir,'dir'); mkdir(wind_outDir); end
    windCsvPath = fullfile(wind_outDir,sprintf('wind_profile_49_turbines.csv'));
    
    T = table(Load(:,1), Wind(:,2) * 3600, 'VariableNames', {'DateTime','WindEnergy_J'});
    writetable(T, windCsvPath); % in J

    if ~exist(solar_outDir,'dir'); mkdir(solar_outDir); end
    SolarCsvPath = fullfile(solar_outDir,sprintf('solar_profile_863_inverters.csv'));
    
    X = table(Load(:,1), Solar(:,2) * 3600, 'VariableNames', {'DateTime','SolarEnergy_J'});
    writetable(X, SolarCsvPath); % in J

    
     
    E_wind_generated_all = N_turbines * E_Wind_1turb;

    % E_solar_required_all = E_gen_required_all - E_wind_generated_all;
    % N_inverters = ceil(E_solar_required_all/E_Solar_1inv);
    % % N_inverters = 830;
    E_solar_generated_all = N_inverters * E_Solar_1inv;

    Wind(:,2) = N_turbines * P_Wind_1turb;
    Solar(:,2) = N_inverters * P_Solar_1inv;

    P_gen_all = Solar(:,2) + Wind(:,2); % in W
  
    
    fprintf('  Total turbines needed: %d \n', N_turbines);
    fprintf('  Total inverters needed: %d \n', N_inverters); 
    fprintf('  Total wind energy generated: %.2f * 1e13 J/yr\n', E_wind_generated_all/1e13);
    fprintf('  Total solar energy generated: %.2f * 1e13 J/yr\n', E_solar_generated_all/1e13);
    fprintf('  Total energy generated: %.2f * 1e13 J/yr\n', (E_wind_generated_all + E_solar_generated_all)/1e13);
    fprintf('  Net energy end (should ~0): %.3f * 1e13 J/yr\n', net_energy_end_Wh(P_load_all, P_gen_all, Ts, eta)*3600/1e13);
    
    raw_end_MWh = sum((P_gen_all - P_load_all)) * Ts / 3.6e9;
    fprintf('Raw annual end mismatch: %.2f MWh\n', raw_end_MWh);

    loss_end_MWh = net_energy_end_Wh(P_load_all, P_gen_all, Ts, eta) / 1e6;
    fprintf('Loss-aware end mismatch: %.2f MWh\n', loss_end_MWh);

    %% =======================================================================
    %  Sensitivity sizing (SoC windows)
    %  =======================================================================    
    soc_windows = [0 1; 0.05 0.95; 0.10 0.90; 0.20 0.80];
    labels = ["0-100","5-95","10-90","20-80"];
    usable_pct = [100; 90; 80; 60];
    
    % Build net energy trajectory once (starts at 0 Wh)
    dE_Wh = net_energy_trajectory_Wh(P_load_all, P_gen_all, Ts, eta);
    
    n_units_all   = zeros(4,1);
    cap_need_MWh  = zeros(4,1);
    AH_case       = zeros(4,1);
    SOC0_case     = zeros(4,1);
    feasible_case = false(4,1);
    soc_traj      = cell(4,1);    % <-- store SoC curves for plotting
    
    for i = 1:4
        smin = soc_windows(i,1);
        smax = soc_windows(i,2);
    
        cap_need_Wh = required_capacity_Wh_from_dE(dE_Wh, smin, smax);
    
        % Convert to HyperBlock units
        n_units_all(i) = ceil(cap_need_Wh / E_unit_Wh);
        cap_case_Wh    = n_units_all(i) * E_unit_Wh;
    
        cap_need_MWh(i) = cap_case_Wh / 1e6;
        AH_case(i)      = AH_unit * n_units_all(i);
    
        % Compute SOC0 and SOC trajectory (no clipping)
        [SOC0_opt, soc, feasible] = soc0_for_zero_grid(dE_Wh, cap_case_Wh, smin, smax);
        SOC0_case(i)     = SOC0_opt;
        feasible_case(i) = feasible;
        soc_traj{i}      = soc;
    
        fprintf('  SoC %s: %d blocks (%.0f MWh), SOC0=%.2f%%, feasible=%d\n', ...
            labels(i), n_units_all(i), cap_need_MWh(i), SOC0_case(i), feasible_case(i));
    end
    
    % Export these for your later figure checks
    soc_0_100  = soc_traj{1};
    soc_5_95   = soc_traj{2};
    soc_10_90  = soc_traj{3};
    soc_20_80  = soc_traj{4};
    
    cap_0_100_MWh = cap_need_MWh(1);
    cap_5_95_MWh  = cap_need_MWh(2);
    cap_10_90_MWh = cap_need_MWh(3);
    cap_20_80_MWh = cap_need_MWh(4);
    
    %% =======================================================================
    %  STEP 6: SHOW values
    %  =======================================================================
    fprintf('\n==========================================================\n');
    fprintf('  VALUES TO APPLY (ZERO GRID / NO CLIPPING)\n');
    fprintf('==========================================================\n');
    
    fprintf('  Unit: 12.8 MWh @ %.1f Vdc => %.0f Ah (equivalent)\n\n', Vnom_unit, AH_unit);
    
    fprintf('  %-7s  %-12s  %-12s  %-12s  %-10s  %-8s\n', ...
        'Case','Nb_p','AH (Ah)','Cap (MWh)','SOC0 (%)','Usable');
    fprintf('  %s\n', repmat('-',1,75));
    for i = 1:4
        fprintf('  %-7s  %-12d  %-12.0f  %-12.0f  %-10.2f  %-8.0f\n', ...
            labels(i), n_units_all(i), AH_case(i), cap_need_MWh(i), SOC0_case(i), usable_pct(i));
    end
    
    %% =======================================================================
    %  STEP 7: APPLY ONE CASE to exported battery parameters
    % =======================================================================
    chosen_case = "20-80";  % "0-100" / "5-95" / "10-90" / "20-80"
    idx = find(labels == chosen_case, 1);
    if isempty(idx), error("chosen_case must be 0-100 / 5-95 / 10-90 / 20-80"); end
    
    Nb_s = 1;
    Nb_p = n_units_all(idx);
    Vnom = Vnom_unit * Nb_s;
    AH   = AH_unit   * Nb_p;
    Q    = Vnom * AH;
    
    SOC0 = SOC0_case(idx);
    
    fprintf('\n[APPLIED] Case %s => Nb_p=%d, Vnom=%.1f V, AH=%.0f Ah, SOC0=%.2f%%, Cap=%.0f MWh\n', ...
        chosen_case, Nb_p, Vnom, AH, SOC0, Q/1e6);
    
    % fprintf('\nWorkspace ready:\n');
    % fprintf('  Load/Pump/Solar/Wind/Backup are %dx2 [time(s) W]\n', N);
    fprintf('  Exported battery (APPLIED): Vnom=%.1f V, AH=%.0f Ah, SOC0=%.2f%%, Nb_s=%d, Nb_p=%d\n', ...
        Vnom, AH, SOC0, Nb_s, Nb_p);    
    
    % if debug_mode
    %     plot_profile(elec_profiles.DateTime, electricity_demand_profile, 'Electricity Demand Profile', 'b');
    %     plot_profile(gas_profiles.DateTime, heat_demand_profile, 'Heat Demand Profile', 'r');
    % end


   
    
    %% ===================== Helper functions =====================
    
    function dE_end = net_energy_end_Wh(Pload_W, Pgen_W, Ts, eta)
    % Returns end cumulative energy change in Wh (should be ~0 after scaling)
        dt_h = Ts/3600;
        E = 0;
        for k = 1:numel(Pload_W)
            Pnet = Pgen_W(k) - Pload_W(k);
            dWh = Pnet * dt_h;
            if dWh >= 0
                E = E + dWh * eta;
            else
                E = E + dWh / eta;
            end
        end
        dE_end = E;
    end
    
    function dE_Wh = net_energy_trajectory_Wh(Pload_W, Pgen_W, Ts, eta)
    % Returns cumulative energy change trajectory dE(t) in Wh (starts at 0)
        dt_h = Ts/3600;
        dE_Wh = zeros(numel(Pload_W),1);
        E = 0;
        for k = 1:numel(Pload_W)
            Pnet = Pgen_W(k) - Pload_W(k);
            dWh = Pnet * dt_h;
            if dWh >= 0
                E = E + dWh * eta;
            else
                E = E + dWh / eta;
            end
            dE_Wh(k) = E;
        end
    end
    
    function cap_Wh = required_capacity_Wh_from_dE(dE_Wh, smin, smax)
    % Capacity required so that there exists an E0 keeping E0+dE within bounds.
    % If dE swings by (max-min), you need cap >= swing/(smax-smin)
        swing = max(dE_Wh) - min(dE_Wh);
        usable = max(smax - smin, eps);
        cap_Wh = swing / usable;
    end
    
    function [SOC0_opt, soc, feasible] = soc0_for_zero_grid(dE_Wh, cap_Wh, smin, smax)
    % Choose SOC0 so trajectory stays within limits WITHOUT clipping.
        Emin = smin * cap_Wh;
        Emax = smax * cap_Wh;
    
        dEmin = min(dE_Wh);
        dEmax = max(dE_Wh);
    
        E0_lo = Emin - dEmin;
        E0_hi = Emax - dEmax;
    
        feasible = (E0_lo <= E0_hi);
    
        if ~feasible
            SOC0_opt = NaN;
            soc = NaN(size(dE_Wh));
            return;
        end
    
        % Choose the midpoint of feasible interval
        E0 = 0.5*(E0_lo + E0_hi);
    
        soc = 100 * (E0 + dE_Wh) / cap_Wh;
        SOC0_opt = 100 * E0 / cap_Wh;
    end
    
        %% ==========================================
    
    function plot_profile(dt, data, label, color)
        figure;
        plot(dt, data, color);
        xlabel('Date/time');
        ylabel(label);
        title([label, ' vs Date/time']);
        xlim tight;
        grid on;
    end

 %% =========================
    %  8. FIGURES (SAVE TO FOLDER)
    % ==========================
    
    
    t     = Load(:,1);
    Ppump = Pump(:,2);
    Pload = Load(:,2);
    Psol  = Solar(:,2);
    Pwind = Wind(:,2);
    
        
    Pgen = Psol + Pwind;

    rootdir = fileparts(fileparts(mfilename('fullpath')));
    outdir = fullfile(rootdir,'outputs', 'step06_battery_sizing_generation_rescaling');
    if ~exist(outdir,'dir'); mkdir(outdir); end
    
    vis = 'off';
    if inputs.debug_mode
        vis = 'on';
        fprintf('\n[FIGURES] Creating slide-style SoC plots (no clipping, SOC0 chosen)...\n');
    end

    time_days = t / 86400;
    bounds_plot = [0 100; 5 95; 10 90; 20 80];
    labels_slide = ["0%-100%","5%-95%","10%-90%","20%-80%"];

    fig1 = figure('Position',[100 100 1400 800], 'Visible', vis);

    for i = 1:4
        subplot(2,2,i);
        plot(time_days, soc_traj{i}, 'LineWidth', 0.8);
        grid on; hold on;

        yline(bounds_plot(i,1), '--r', 'LineWidth', 1.0);
        yline(bounds_plot(i,2), '--r', 'LineWidth', 1.0);
        yline(SOC0_case(i), '--', 'LineWidth', 0.8);

        ylim([-2 102]); xlim([0 365]);
        yticks([0 10 20 30 40 50 60 70 80 90 100]);
        xlabel('Time [days]');
        ylabel('SoC [%]');

        if feasible_case(i)
            title(sprintf('%s — %.0f MWh — SOC0=%.1f%% — Final=%.1f%%', ...
                labels_slide(i), cap_need_MWh(i), SOC0_case(i), soc_traj{i}(end)));
        else
            title(sprintf('%s — %.0f MWh — NOT FEASIBLE (increase capacity)', ...
                labels_slide(i), cap_need_MWh(i)));
        end

        hold off;
    end

    sgtitle('Sensitivity Analysis', 'FontWeight','bold');
    saveas(fig1,fullfile(outdir,'bess_sensitivity_soc_zero_grid.png'));

          
    Pnet = Pgen - P_load_all;      % W
    % dt = median(diff(t));      % ~3600 s
    % samplesPerDay = round(24*3600/dt);
    % N  = numel(t);
    % Nd = floor(N/samplesPerDay);
    % idx = (1:Nd*samplesPerDay);
    % 
    % tdays = (0:Nd-1)';
    % 
    % Ptotal_d = reshape(P_load_all(idx), samplesPerDay, Nd);
    % Pgen_d   = reshape(Pgen(idx),   samplesPerDay, Nd);
    % Pnet_d   = reshape(Pnet(idx),   samplesPerDay, Nd);
    % 
    % Eload_day = sum(Ptotal_d,1)' * dt / 3.6e9;   % MWh/day
    % Egen_day  = sum(Pgen_d,1)'   * dt / 3.6e9;   % MWh/day
    % Emis_day  = sum(Pnet_d,1)'   * dt / 3.6e9;   % MWh/day
    % Ecum      = cumsum(Emis_day);                % MWh

    dt = median(diff(t));                    % s
    samplesPerDay = round(24*3600/dt);
    N  = numel(t);
    Nd = floor(N/samplesPerDay);
    idx = 1:(Nd*samplesPerDay);
    
    tdays = (0:Nd-1)';
    
    Ptotal_d = reshape(P_load_all(idx), samplesPerDay, Nd);
    Pgen_d   = reshape(Pgen(idx),       samplesPerDay, Nd);
    
    Eload_day = sum(Ptotal_d,1)' * dt / 3.6e9;   % MWh/day
    Egen_day  = sum(Pgen_d,1)'   * dt / 3.6e9;   % MWh/day
    
    % --- LOSS-AWARE daily mismatch, consistent with battery sizing ---
    dE_Wh_plot = net_energy_trajectory_Wh(P_load_all(idx), Pgen(idx), Ts, eta);
    dE_step_Wh = [dE_Wh_plot(1); diff(dE_Wh_plot)];   % per-step loss-aware energy increment
    
    dE_day_Wh = sum(reshape(dE_step_Wh, samplesPerDay, Nd), 1)';   % Wh/day
    Emis_day  = dE_day_Wh / 1e6;                                   % MWh/day
    Ecum      = cumsum(Emis_day);                                  % MWh
    
    Emax = max(Ecum); Emin = min(Ecum); Erange = Emax - Emin;
    fprintf('Emax = %.4f, Emin = %.4f, Erange = %.4f\n', Emax, Emin, Erange);
    
    % 1) Daily Load vs RES Generation
    fig2 = figure('Color','w','Position',[80 80 1500 520], 'Visible', vis);
    hold on; grid on;
    area(tdays, Eload_day, 'FaceAlpha',0.25, 'EdgeAlpha',0.9);
    area(tdays, Egen_day,  'FaceAlpha',0.25, 'EdgeAlpha',0.9);
    plot(tdays, Eload_day,'LineWidth',1.5);
    plot(tdays, Egen_day, 'LineWidth',1.5);
    xlabel('Time [days]'); ylabel('Energy [MWh/day]');
    title('Daily Electrical Load vs. RES Generation');
    legend({'Total Load (incl. ATES pump)','RES Generation (scaled)'},'Location','northeast');
    saveas(fig2, fullfile(outdir,'bess_load_vs_gen.png'));

    
    % 2a) Daily mismatch + cumulative mismatch
    fig3 = figure('Color','w','Position',[80 80 1500 820], 'Visible', vis);
    tiledlayout(2,1,'Padding','compact','TileSpacing','compact');
    
    nexttile; hold on; grid on;
    pos = Emis_day; pos(pos<0)=0;
    neg = Emis_day; neg(neg>0)=0;
    bar(tdays, pos);
    bar(tdays, neg);
    yline(0,'k-');
    xlabel('Time [days]'); ylabel('Mismatch [MWh/day]');
    title('Daily Generation - Load Mismatch');
    
    nexttile; hold on; grid on;
    plot(tdays, Ecum,'LineWidth',1.5);
    yline(Emax,'--','LineWidth',1.2);
    yline(Emin,'--','LineWidth',1.2);
    xlabel('Time [days]'); ylabel('Cumulative Mismatch [MWh]');
    title('Cumulative Energy Mismatch');
    text(round(0.45*Nd), 0.5*(Emax+Emin), sprintf('Range: %.0f MWh',Erange), ...
        'BackgroundColor',[.95 .95 .95],'EdgeColor',[.4 .4 .4],'Margin',6);
    legend({'Cumulative mismatch', sprintf('Max: %.0f MWh',Emax), sprintf('Min: %.0f MWh',Emin)}, ...
        'Location','best');
    saveas(fig3, fullfile(outdir,'bess_mismatch.png'));

    % 2b) cumulative hourly mismatch - swing
    dE_Wh = net_energy_trajectory_Wh(P_load_all, Pgen, Ts, eta);   % cumulative loss-aware Wh
    Ecum_hourly = dE_Wh / 1e6;                                     % MWh
    
    t_days = (t - t(1)) / 86400 + 1;   % if t is in seconds
    % if t is datetime:
    % t_days = days(t - t(1)) + 1;
    
    Emax = max(Ecum_hourly);
    Emin = min(Ecum_hourly);
    Erange = Emax - Emin;
    
    fig_hourly_cum = figure('Color','w','Position',[80 80 1500 700], 'Visible', vis);
    plot(t_days, Ecum_hourly, 'LineWidth', 1.5);
    grid on; hold on;
    yline(Emax, '--', 'LineWidth', 1.2);
    yline(Emin, '--', 'LineWidth', 1.2);
    
    xlabel('Time [days]');
    ylabel('Cumulative Mismatch [MWh]');
    title('Cumulative Hourly Energy Mismatch (Loss-Aware)');
    
    xlim([1 ceil(max(t_days))]);
    
    text(round(0.45*max(t_days)), 0.5*(Emax+Emin), sprintf('Range: %.0f MWh', Erange), ...
        'BackgroundColor',[.95 .95 .95], 'EdgeColor',[.4 .4 .4], 'Margin',6);
    
    legend({'Cumulative mismatch', sprintf('Max: %.0f MWh', Emax), sprintf('Min: %.0f MWh', Emin)}, ...
        'Location', 'best');
    
    saveas(fig_hourly_cum, fullfile(outdir,'bess_hourly_cumulative_mismatch.png'));
    
    % 3) ATES Pump power profile (kW)
    fig4 = figure('Color','w','Position',[80 80 1500 480], 'Visible', vis);
    plot((t-t(1))/86400, Ppump/1000,'LineWidth',1.0); grid on;
    xlabel('Time [days]'); ylabel('ATES Pump Power [kW]');
    title(sprintf('ATES Heat Storage Pumping Power — Peak: %.0f kW', max(Ppump)/1000));
    saveas(fig4, fullfile(outdir,'bess_ppump_profile.png'));
    
    % 4) SoC sensitivity plot (now it will exist)
    fig5 = figure('Color','w','Position',[80 80 1500 900], 'Visible', vis);
    tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
    socs2   = {soc_0_100, soc_5_95, soc_10_90, soc_20_80};
    lab2    = {'0%-100%','5%-95%','10%-90%','20%-80%'};
    lims2   = [0 100; 5 95; 10 90; 20 80];
    for k=1:4
        nexttile; hold on; grid on;
        plot((t-t(1))/86400, socs2{k}, 'LineWidth',1.1);
        yline(lims2(k,1),'--'); yline(lims2(k,2),'--'); yline(50,':');
        ylim([0 100]);
        xlabel('Time [days]'); ylabel('SoC [%]');
        title(['BESS Sensitivity — ', lab2{k}]);
    end
    saveas(fig5, fullfile(outdir,'bess_sensitivity_soc.png'));
    
    % 5) Capacity comparison bar chart (now it will exist)
    fig6 = figure('Color','w','Position',[80 80 1200 700], 'Visible', vis);
    caps = [cap_0_100_MWh, cap_5_95_MWh, cap_10_90_MWh, cap_20_80_MWh];
    xlbl = {'0%-100%','5%-95%','10%-90%','20%-80%'};
    bar(caps); grid on;
    set(gca,'XTickLabel', xlbl);
    ylabel('Total BESS Capacity [MWh]');
    title('BESS Capacity Required for 100% Autonomy — Sensitivity to SoC Limits');
    for i=1:numel(caps)
        text(i, caps(i), sprintf('%.0f MWh',caps(i)), 'HorizontalAlignment','center','VerticalAlignment','bottom');
    end
    saveas(fig6, fullfile(outdir,'bess_sizing_comparison.png'));

    %% -------------------- Create battery model and push to workspace--------------------
    Ts = 3600;                 % [s] 60 minutes
   
    %% -------------------- Battery "unit" definition --------------------
    % HyperStrong HyperBlock M (AC version) — treat as ONE unit block
    % Rated energy: 12.8 MWh  => 12.8e6 Wh
    % Rated DC voltage: 1331.2 V
    E_unit_Wh = 12.8e6;            % [Wh] per block
    Vnom_unit = 1331.2;            % [V]  per block (DC)
    AH_unit   = E_unit_Wh ./ Vnom_unit;  % [Ah] equivalent per block (~9615 Ah)
    
    % Converter efficiencies (used in energy-balance SoC model)
    effConvBESS = 0.93;
    
    % One-way efficiency approximation for charging/discharging through BESS path
    eta = sqrt(effConvBESS);
    
    %% -------------------- Grid params (kept for consistency) --------------------
    f = 50; %#ok<NASGU>
    V = 400; %#ok<NASGU>








        %% Parameters for System Integration Project

    N_h = 1;                % Number of households              [-]
    effConvPV = 1;          % PV power converter efficiency     [-]
    effConvWind = 1;        % Wind power converter efficiency   [-]
    Backup = [Load(:,1) zeros(length(Load),1)];    %Replace with actual backup generation       [s W]

    % --- push parameters to base workspace (if your model reads from base) ---
    assignin('base',"Q",E_unit_Wh);
    assignin('base',"Vnom",Vnom_unit);
    assignin('base',"AH", AH_unit);
    assignin('base',"SOC0",SOC0);
    assignin('base',"Nb_s",Nb_s);
    assignin('base',"Nb_p",Nb_p);
    assignin('base',"effConvBESS",eta);
    assignin('base',"effConvPV",effConvPV);
    assignin('base',"effConvWind",effConvWind);
    assignin('base',"Load",Load);
    assignin('base',"Pump",Pump);
    assignin('base',"N_h",N_h);
    assignin('base',"f",f);
    assignin('base',"V",V);
    assignin('base',"Ts",Ts);
    assignin('base',"Solar",Solar);
    assignin('base',"Wind",Wind);
    assignin('base',"Backup",Backup);

end

