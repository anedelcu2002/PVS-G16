clear; clc;

%% ================= RUN PV DESIGN =================
run('PVDesign.m');   % must output: G_POA, data

G_POA = G_POA(:);

T_amb = data.Ta;

%% ================= TIME VECTOR =================
time = datetime(data.Year, data.Month, data.Day, data.Hour, 0, 0);

%% ================= CONSTANTS =================
G_NOCT = 800;

%% ================= MODULES =================
modules(1).name = 'LONGi';
modules(1).P = 600;
modules(1).gamma = -0.0029;
modules(1).NOCT = 45;

modules(2).name = 'AIKO';
modules(2).P = 490;
modules(2).gamma = -0.0026;
modules(2).NOCT = 45;

%% ================= STORAGE =================
G_INOCT_all = zeros(length(G_POA),2);

%% ================= LOOP =================
for m = 1:2
    
    Pm = modules(m).P;
    gamma = modules(m).gamma;
    NOCT = modules(m).NOCT;
    
    %% -------- INOCT (RACK) --------
    INOCT_rack = NOCT - 3;
    
    Tm_INOCT = T_amb + (G_POA / G_NOCT) .* (INOCT_rack - 20);
    
    P_INOCT = Pm .* (G_POA/1000) .* (1 + gamma*(Tm_INOCT - 25));
    P_INOCT(P_INOCT < 0) = 0;
    
    G_INOCT_all(:,m) = P_INOCT / 1000;   % kWh per hour
end

%% ================= 8760-HOUR PLOT =================
figure;

plot(G_INOCT_all(:,1), 'r', 'LineWidth', 0.5); hold on;
plot(G_INOCT_all(:,2), 'g', 'LineWidth', 0.5);

xlabel('Hour of Year (1–8760)');
ylabel('Generation (kWh)');
title('Hourly PV Generation (INOCT Rack)');

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
    
    weekly_LONGi(w) = sum(G_INOCT_all(idx,1));
    weekly_AIKO(w)  = sum(G_INOCT_all(idx,2));
    
end

%% ================= WEEKLY PLOT =================
figure;

bar(1:n_weeks, [weekly_LONGi weekly_AIKO], 'grouped');

xlabel('Week Number');
ylabel('Energy (kWh)');
title('Weekly PV Generation (INOCT Rack)');

legend('LONGi','AIKO','Location','best');
grid on;

%% ================= EXPORT =================
output = table( ...
    time, ...
    G_INOCT_all(:,1), ...
    G_INOCT_all(:,2), ...
    'VariableNames', { ...
    'Time', ...
    'LONGi_INOCT', ...
    'AIKO_INOCT'});

writetable(output, 'INOCT_Generation_8760.xlsx');

%% ================= TOTAL ENERGY =================
E_INOCT = sum(G_INOCT_all);

fprintf('\n--- ANNUAL ENERGY (INOCT Rack) ---\n');
fprintf('LONGi: %.2f kWh\n', E_INOCT(1));
fprintf('AIKO : %.2f kWh\n', E_INOCT(2));

%% ================= CLEAN 8760-HOUR PLOT =================

figure;

plot(G_INOCT_all(:,1), 'r', 'LineWidth', 0.5); hold on;
plot(G_INOCT_all(:,2), 'g', 'LineWidth', 0.5);

xlabel('Hour of Year (1–8760)');
ylabel('Generation (kWh)');
title('Hourly PV Generation (8760 Hours)');

legend('LONGi INOCT','AIKO INOCT');

grid on;