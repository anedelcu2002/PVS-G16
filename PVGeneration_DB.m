clear; clc;

%% ================= RUN PV DESIGN =================
run('PVDesign.m');

G_POA = G_POA(:);
T_amb = data.Ta;

%% ================= TIME =================
time = datetime(data.Year, data.Month, data.Day, data.Hour, 0, 0);

%% ================= CONSTANTS =================
G_STC  = 1000;
G_NOCT = 800;
T_STC  = 25;

%Electrical Model
n = 1; %Assume Ideal
kB = 1.38e-23;
q  = 1.6e-19;
T  = 298;

%% ================= MODULE DATA =================

% LONGi
modules(1).name = 'LONGi';
modules(1).NOCT = 45;
modules(1).Area = 2.58;
modules(1).eta_STC = 0.228;
modules(1).gamma_P = -0.0029;

modules(1).Voc = 52.51;
modules(1).Isc = 14.33;
modules(1).Voc_coeff = -0.13;   % V/°C (FIXED UNIT)
modules(1).Isc_coeff = 0.005;   % A/°C

modules(1).Vmpp = 44.36;
modules(1).Impp = 13.31;

modules(1).Ns = 72; %Not Sure
modules(1).FF = 44.36*13.31/(52.51*14.33); %Not Sure
% AIKO
modules(2).name = 'AIKO';
modules(2).NOCT = 45;
modules(2).Area = 2;
modules(2).eta_STC = 0.24;
modules(2).gamma_P = -0.0026;

modules(2).Voc = 41;
modules(2).Isc = 14.84;
modules(2).Voc_coeff = -0.12;
modules(2).Isc_coeff = 0.0045;

modules(2).Vmpp = 34.5;
modules(2).Impp = 13.92;
modules(2).Ns = 62; %Not Sure
modules(2).FF = 32.73*11.13/(11.96*38.80);

%% ================= STORAGE =================
N = length(G_POA);

Voc_T = zeros(N,2);   % V_OC(Tm, G_STC)
Isc_T = zeros(N,2);   % I_SC(Tm, G_STC)
P_T   = zeros(N,2);   % P_MPP(Tm, G_STC)
eta_T = zeros(N,2);   % eta(Tm, G_STC)

Voc_I = zeros(N,2);   % V_OC(25, g)
Isc_I = zeros(N,2);   % I_SC(25, g)
P_I   = zeros(N,2);   % P_MPP(25, g)
eta_I = zeros(N,2);   % eta(25, g)

eta_IT = zeros(N,2);  % eta(T, g)
P_DC = zeros(N,2);

%% ================= LOOP =================
for m = 1:2
    
    NOCT = modules(m).NOCT;
    
    Voc_STC = modules(m).Voc;
    Isc_STC = modules(m).Isc;
    
    Voc_coeff = modules(m).Voc_coeff;
    Isc_coeff = modules(m).Isc_coeff;
    gamma_P   = modules(m).gamma_P;
    
    Vmpp = modules(m).Vmpp;
    Impp = modules(m).Impp;
    Area = modules(m).Area;
    
    FF = modules(m).FF;
    Ns = modules(m).Ns;
    
    %% -------- DUFFIE --------
    tau_alpha = 0.9;
    
    Tm_Duffie = T_amb + ...
        (G_POA / G_NOCT) .* (NOCT - 20) .* ...
        (1 - eta_ref/tau_alpha) .* ...
        (9.5 ./ (5.7 + 3.8*w));
        
    dT = Tm_Duffie - T_STC;  
    %% ===== FORMULAS FROM YOUR SLIDE =====
    
    % V_OC(Tm, G_STC)
    Voc_varT = Voc_STC + Voc_coeff .* dT;
    
    % I_SC(Tm, G_STC)
    Isc_varT = Isc_STC + Isc_coeff .* dT;
    
    % P_MPP(Tm, G_STC)
    Pmpp_STC = Vmpp * Impp;
    Pmpp_varT = Pmpp_STC + gamma_P .* dT;
    
    % eta(Tm, G_STC)
    eta_varT = Pmpp_varT ./ (Area * G_STC);
    

    % V_OC(Tm, G_STC)
    Voc_varI = Voc_STC + (n*kB*T/q).* log(G_POA./G_STC) .* Ns;
    
    % I_SC(Tm, G_STC)
    Isc_varI = Isc_STC * G_POA ./ G_STC;
    
    % P_MPP(Tm, G_STC)
    Pmpp_varI = FF .* Isc_varI .* Voc_varI;
    
    % eta(Tm, G_STC)
    eta_varI = Pmpp_varI ./ (Area * G_POA);

    %Variable IT Efficiency
    eta_varIT = eta_varI .* (1 - 0.0035.*(dT));

    %Power Yield
    P_DC_var = eta_varIT.*Area.*G_POA;
    P_DC_var(isnan(P_DC_var)) = 0;
    P_DC_var(isinf(P_DC_var)) = 0;
  
    %% STORE
    Voc_T(:,m) = Voc_varT;
    Isc_T(:,m) = Isc_varT;
    P_T(:,m)   = Pmpp_varT;
    eta_T(:,m) = eta_varT;
   
    Voc_I(:,m) = Voc_varI;
    Isc_I(:,m) = Isc_varI;
    P_I(:,m)   = Pmpp_varI;
    eta_I(:,m) = eta_varI;

    eta_IT(:,m) = eta_varIT;
    P_DC(:,m) = P_DC_var;
end
%% ================= 8760 GENERATION (kWh) =================

% Convert W → kWh (since timestep = 1 hour)
G_8760 = P_DC / 1000;

%% ================= 8760 PLOT =================
figure;

plot(G_8760(:,1), 'r', 'LineWidth', 0.5); hold on;
plot(G_8760(:,2), 'g', 'LineWidth', 0.5);

xlabel('Hour of Year (1–8760)');
ylabel('Generation (kWh)');
title('Hourly PV Generation (8760)');

legend('LONGi','AIKO');
grid on;

%% ================= WEEKLY GENERATION =================

week_idx = ceil((1:N)' / 168);
n_weeks = max(week_idx);

weekly_LONGi = zeros(n_weeks,1);
weekly_AIKO  = zeros(n_weeks,1);

for w = 1:n_weeks
    
    idx = (week_idx == w);
    
    weekly_LONGi(w) = sum(G_8760(idx,1),'omitnan');
    weekly_AIKO(w)  = sum(G_8760(idx,2),'omitnan');
end

%% ================= WEEKLY PLOT =================
figure;

bar(1:n_weeks, [weekly_LONGi weekly_AIKO], 'grouped');

xlabel('Week Number');
ylabel('Energy (kWh)');
title('Weekly PV Generation');

legend('LONGi','AIKO','Location','best');
grid on;

%% ================= OPTIONAL EXPORT =================
output = table(time, G_8760(:,1), G_8760(:,2), ...
    'VariableNames', {'Time','LONGi_kWh','AIKO_kWh'});

writetable(output, 'Final_8760_Generation.xlsx');

%% ================= TOTAL ENERGY =================
E_total = sum(G_8760);

fprintf('\n--- ANNUAL GENERATION ---\n');
fprintf('LONGi: %.2f kWh\n', E_total(1));
fprintf('AIKO : %.2f kWh\n', E_total(2));
