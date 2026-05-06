clear; clc;

%% ================= RUN PV DESIGN =================
run('PVDesign.m');   % must output: G_POA, data

G_POA = G_POA(:);

T_amb = data.Ta;

% Wind (constant or replace with data.FF if available)
w = 3.49;

%% ================= TIME VECTOR =================
time = datetime(data.Year, data.Month, data.Day, data.Hour, 0, 0);

%% ================= CONSTANTS =================
G_NOCT = 800;
tau_alpha = 0.9;

%% ================= MODULES =================
modules(1).name = 'LONGi';
modules(1).P = 600;
modules(1).gamma = -0.0029;
modules(1).NOCT = 45;
modules(1).eta = 0.22;

modules(2).name = 'AIKO';
modules(2).P = 490;
modules(2).gamma = -0.0026;
modules(2).NOCT = 45;
modules(2).eta = 0.24;

%% ================= STORAGE =================
G_Duffie_all = zeros(length(G_POA),2);

%% ================= LOOP =================
for m = 1:2
    
    Pm = modules(m).P;
    gamma = modules(m).gamma;
    NOCT = modules(m).NOCT;
    eta = modules(m).eta;
    
    %% -------- DUFFIE–BECKMAN --------
    Tm_Duffie = T_amb + ...
        (G_POA / G_NOCT) .* (NOCT - 20) .* ...
        (1 - eta/tau_alpha) .* ...
        (9.5 ./ (5.7 + 3.8*w));
    
    P_Duffie = Pm .* (G_POA/1000) .* (1 + gamma*(Tm_Duffie - 25));
    P_Duffie(P_Duffie < 0) = 0;
    
    G_Duffie_all(:,m) = P_Duffie / 1000;   % kWh per hour
end

%% ================= 8760-HOUR PLOT =================
figure;

plot(G_Duffie_all(:,1), 'r', 'LineWidth', 0.5); hold on;
plot(G_Duffie_all(:,2), 'g', 'LineWidth', 0.5);

xlabel('Hour of Year (1–8760)');
ylabel('Generation (kWh)');
title('Hourly PV Generation (Duffie–Beckman)');

legend('LONGi','AIKO');
grid on;

%% ================= WEEKLY AGGREGATION =================

N = length(G_POA);
week_idx = ceil((1:N)' / 168);
n_weeks = max(week_idx);

weekly_LONGi = zeros(n_weeks,1);
weekly_AIKO  = zeros(n_weeks,1);

for w = 1:n_weeks
    
    idx = (week_idx == w);
    
    weekly_LONGi(w) = sum(G_Duffie_all(idx,1));
    weekly_AIKO(w)  = sum(G_Duffie_all(idx,2));
    
end

%% ================= WEEKLY PLOT =================
figure;

bar(1:n_weeks, [weekly_LONGi weekly_AIKO], 'grouped');

xlabel('Week Number');
ylabel('Energy (kWh)');
title('Weekly PV Generation (Duffie–Beckman)');

legend('LONGi','AIKO','Location','best');
grid on;

%% ================= EXPORT =================
output = table( ...
    time, ...
    G_Duffie_all(:,1), ...
    G_Duffie_all(:,2), ...
    'VariableNames', { ...
    'Time', ...
    'LONGi_Duffie', ...
    'AIKO_Duffie'});

writetable(output, 'Duffie_Generation_8760.xlsx');

%% ================= TOTAL ENERGY =================
E_Duffie = sum(G_Duffie_all);

fprintf('\n--- ANNUAL ENERGY (Duffie–Beckman) ---\n');
fprintf('LONGi: %.2f kWh\n', E_Duffie(1));
fprintf('AIKO : %.2f kWh\n', E_Duffie(2));

%% ================= CLEAN 8760-HOUR PLOT =================

figure;

plot(G_Duffie_all(:,1), 'r', 'LineWidth', 0.5); hold on;
plot(G_Duffie_all(:,2), 'g', 'LineWidth', 0.5);

xlabel('Hour of Year (1–8760)');
ylabel('Generation (kWh)');
title('Hourly PV Generation (8760 Hours)');

legend('LONGi Duffie','AIKO Duffie');

grid on;


%% ================= SPECIFIC YIELD (kWh/kWp) =================

P_rated_LONGi = 0.6;   % kWp
P_rated_AIKO  = 0.49;  % kWp

Y_LONGi = E_Duffie(1) / P_rated_LONGi;
Y_AIKO  = E_Duffie(2) / P_rated_AIKO;

fprintf('\n--- SPECIFIC YIELD ---\n');
fprintf('LONGi: %.2f kWh/kWp/year\n', Y_LONGi);
fprintf('AIKO : %.2f kWh/kWp/year\n', Y_AIKO);