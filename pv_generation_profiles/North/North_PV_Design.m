clear; clc;

%% ================= LOAD DATA =================
run('North_Optimal_Irradiation.m');
G_POA = G_POA(:);

T_amb = data.Ta;
T_sky = data.Tsky;
T_ground = T_amb;

%% CONSTANTS
G_NOCT = 800;

%% MODULE (ONLY FOR THERMAL PARAMETERS)
NOCT = 45;
eta_ref = 0.22;   % choose representative module (LONGi)

%% WIND
w = 3.49;

%% ================= MAIN TEMPERATURE CALC =================

%% -------- INOCT --------
INOCT = NOCT + 11;   % stand-off example
Tm_INOCT = T_amb + (G_POA / G_NOCT) .* (INOCT - 20);

%% -------- DUFFIE --------
tau_alpha = 0.9;

Tm_Duffie = T_amb + ...
    (G_POA / G_NOCT) .* (NOCT - 20) .* ...
    (1 - eta_ref/tau_alpha) .* ...
    (9.5 ./ (5.7 + 3.8*w));

%% -------- SANDIA --------
a = -3.56;
b = -0.075;

Tm_Sandia = G_POA .* exp(a + b*w) + T_amb;

%% -------- FAIMAN --------
U0 = 25;
U1 = 6.84;

Tm_Faiman = T_amb + G_POA ./ (U0 + U1*w);

%% -------- FLUID (FIXED) --------

sigma = 5.67e-8;
epsilon = 0.9;
R = 0.08;

phi = (1 - R) * (1 - eta_ref);
hc = 5 + 3.8*w;

Tm_Fluid = T_amb + 20;

for iter = 1:5
    
    TmK = Tm_Fluid + 273.15;
    TskyK = T_sky + 273.15;
    TgroundK = T_ground + 273.15;
    
    hr_sky = epsilon * sigma .* (TmK.^2 + TskyK.^2) .* (TmK + TskyK);
    hr_ground = epsilon * sigma .* (TmK.^2 + TgroundK.^2) .* (TmK + TgroundK);
    
    Tm_Fluid = ( ...
        phi .* G_POA + ...
        hc .* T_amb + ...
        hr_sky .* T_sky + ...
        hr_ground .* T_ground ) ./ ...
        (hc + hr_sky + hr_ground);
end

%% ================= COMPARE TEMPERATURES =================

figure;
plot(Tm_INOCT, 'k'); hold on;
plot(Tm_Duffie, 'b');
plot(Tm_Sandia, 'g');
plot(Tm_Faiman, 'r');
plot(Tm_Fluid, 'm');

xlabel('Hour (1–8760)');
ylabel('Module Temperature (°C)');
title('Temperature Models Comparison');

legend('INOCT','Duffie','Sandia','Faiman','Fluid');
grid on;

%% ================= WIND SWEEP =================

w_range = linspace(0,10,30);

Tm_INOCT_w = zeros(size(w_range));
Tm_Duffie_w = zeros(size(w_range));
Tm_Sandia_w = zeros(size(w_range));
Tm_Faiman_w = zeros(size(w_range));
Tm_Fluid_w = zeros(size(w_range));

for k = 1:length(w_range)
    
    w = w_range(k);
    
    %% INOCT
    Tm1 = T_amb + (G_POA / G_NOCT) .* (INOCT - 20);
    
    %% DUFFIE
    Tm2 = T_amb + ...
        (G_POA / G_NOCT) .* (NOCT - 20) .* ...
        (1 - eta_ref/tau_alpha) .* ...
        (9.5 ./ (5.7 + 3.8*w));
    
    %% SANDIA
    Tm3 = G_POA .* exp(a + b*w) + T_amb;
    
    %% FAIMAN
    Tm4 = T_amb + G_POA ./ (U0 + U1*w);
    
    %% FLUID
    hc = 5 + 3.8*w;
    Tm5 = T_amb + 20;
    
    for iter = 1:5
        
        TmK = Tm5 + 273.15;
        TskyK = T_sky + 273.15;
        TgroundK = T_ground + 273.15;
        
        hr_sky = epsilon * sigma .* (TmK.^2 + TskyK.^2) .* (TmK + TskyK);
        hr_ground = epsilon * sigma .* (TmK.^2 + TgroundK.^2) .* (TmK + TgroundK);
        
        Tm5 = ( ...
            phi .* G_POA + ...
            hc .* T_amb + ...
            hr_sky .* T_sky + ...
            hr_ground .* T_ground ) ./ ...
            (hc + hr_sky + hr_ground);
    end
    
    %% AVERAGES
    Tm_INOCT_w(k) = mean(Tm1);
    Tm_Duffie_w(k) = mean(Tm2);
    Tm_Sandia_w(k) = mean(Tm3);
    Tm_Faiman_w(k) = mean(Tm4);
    Tm_Fluid_w(k) = mean(Tm5);
end

%% ================= WIND PLOT =================

figure;
plot(w_range, Tm_INOCT_w, 'k--', 'LineWidth', 2); hold on;
plot(w_range, Tm_Duffie_w, 'b', 'LineWidth', 2);
plot(w_range, Tm_Sandia_w, 'g', 'LineWidth', 2);
plot(w_range, Tm_Faiman_w, 'r', 'LineWidth', 2);
plot(w_range, Tm_Fluid_w, 'm', 'LineWidth', 2);

xlabel('Wind Speed (m/s)');
ylabel('Average Module Temperature (°C)');
title('Temperature Models vs Wind Speed');

legend('INOCT','Duffie','Sandia','Faiman','Fluid');
grid on;