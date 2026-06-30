clear; clc;

%% ================= LOAD DATA =================
run('Optimal_Irradiation.m');
G_POA = G_POA(:);

T_amb = data.Ta;
T_sky = data.Tsky;
T_ground = T_amb;

% Wind
w = 3.49;

%% CONSTANTS
G_NOCT = 800;
tau_alpha = 0.9;

%% MODULES
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

%% INSTALLATIONS (ONLY FOR INOCT)
inst = {'Direct','StandOff','Rack'};
INOCT_offset = [18, 11, -3];

results = [];

%% ================= MAIN LOOP =================
for m = 1:2
    
    Pm = modules(m).P;
    gamma = modules(m).gamma;
    NOCT = modules(m).NOCT;
    eta = modules(m).eta;
    
    %% -------- INOCT (3 INSTALLATIONS) --------
    for i = 1:3
        
        INOCT = NOCT + INOCT_offset(i);
        
        Tm1 = T_amb + (G_POA / G_NOCT) .* (INOCT - 20);
        
        P1 = Pm .* (G_POA/1000) .* (1 + gamma*(Tm1 - 25));
        P1(P1<0)=0;
        
        E1 = sum(P1)/1000;
        
        results = [results;
            {modules(m).name, inst{i}, 'INOCT', E1};
        ];
    end
    
    %% -------- DUFFIE --------
    Tm2 = T_amb + ...
          (G_POA / G_NOCT) .* (NOCT - 20) .* ...
          (1 - eta/tau_alpha) .* ...
          (9.5 ./ (5.7 + 3.8*w));
      
    P2 = Pm .* (G_POA/1000) .* (1 + gamma*(Tm2 - 25));
    P2(P2<0)=0;
    
    E2 = sum(P2)/1000;
    
    results = [results;
        {modules(m).name, 'Wind-based', 'Duffie', E2};
    ];
    
    %% -------- SANDIA (Open Rack) --------
    a = -3.56;
    b = -0.075;
    
    Tm3 = G_POA .* exp(a + b*w) + T_amb;
    
    P3 = Pm .* (G_POA/1000) .* (1 + gamma*(Tm3 - 25));
    P3(P3<0)=0;
    
    E3 = sum(P3)/1000;
    
    results = [results;
        {modules(m).name, 'Wind-based', 'Sandia', E3};
    ];
    
    %% -------- FAIMAN --------
    U0 = 25;
    U1 = 6.84;
    
    Tm4 = T_amb + G_POA ./ (U0 + U1*w);
    
    P4 = Pm .* (G_POA/1000) .* (1 + gamma*(Tm4 - 25));
    P4(P4<0)=0;
    
    E4 = sum(P4)/1000;
    
    results = [results;
        {modules(m).name, 'Wind-based', 'Faiman', E4};
    ];
    
%% -------- FINAL FLUID MODEL (LECTURE-CORRECT) --------

sigma = 5.67e-8;
epsilon = 0.9;
R = 0.08;

phi = (1 - R) * (1 - eta);   % heat fraction

hc = 5 + 3.8*w;

% Initial guess
Tm = T_amb + 20;

for iter = 1:5
    
    % Convert to Kelvin
    TmK = Tm + 273.15;
    TskyK = T_sky + 273.15;
    TgroundK = T_ground + 273.15;
    
    % Radiative coefficients
    hr_sky = epsilon * sigma .* (TmK.^2 + TskyK.^2) .* (TmK + TskyK);
    hr_ground = epsilon * sigma .* (TmK.^2 + TgroundK.^2) .* (TmK + TgroundK);
    
    % Update temperature
    Tm5 = ( ...
        phi .* G_POA + ...
        hc .* T_amb + ...
        hr_sky .* T_sky + ...
        hr_ground .* T_ground ) ./ ...
        (hc + hr_sky + hr_ground);
end

    P5 = Pm .* (G_POA/1000) .* (1 + gamma*(Tm5 - 25));
    P5(P5<0)=0;
    
    E5 = sum(P5)/1000;
    
    results = [results;
        {modules(m).name, 'Wind+Rad', 'Fluid', E5};
    ];
end

%% ================= RESULTS =================
results_table = cell2table(results,...
    'VariableNames',{'Module','Installation','Model','Annual_kWh'});

disp(results_table);

%% ================= WIND SWEEP =================

w_range = linspace(0,10,30);

Tm_INOCT = zeros(size(w_range));
Tm_Duffie = zeros(size(w_range));
Tm_Sandia = zeros(size(w_range));
Tm_Faiman = zeros(size(w_range));
Tm_Fluid = zeros(size(w_range));

NOCT = 45;
eta = 0.22;
INOCT = NOCT + 11;

for k = 1:length(w_range)
    
    w = w_range(k);
    
    %% INOCT
    Tm1 = T_amb + (G_POA / G_NOCT) .* (INOCT - 20);
    
    %% DUFFIE
    Tm2 = T_amb + ...
          (G_POA / G_NOCT) .* (NOCT - 20) .* ...
          (1 - eta/tau_alpha) .* ...
          (9.5 ./ (5.7 + 3.8*w));
    
    %% SANDIA
    a = -3.56; b = -0.075;
    Tm3 = G_POA .* exp(a + b*w) + T_amb;
    
    %% FAIMAN
    U0 = 25; U1 = 6.84;
    Tm4 = T_amb + G_POA ./ (U0 + U1*w);
    
   %% FLUID
sigma = 5.67e-8;
epsilon = 0.9;
R = 0.08;

phi = (1 - R) * (1 - eta);

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

Tm_Fluid(k) = mean(Tm5);
    
    %% AVERAGES
    Tm_INOCT(k) = mean(Tm1);
    Tm_Duffie(k) = mean(Tm2);
    Tm_Sandia(k) = mean(Tm3);
    Tm_Faiman(k) = mean(Tm4);
    Tm_Fluid(k) = mean(Tm5);
end

%% ================= PLOT =================
figure;
plot(w_range, Tm_INOCT, 'k--', 'LineWidth', 2); hold on;
plot(w_range, Tm_Duffie, 'b', 'LineWidth', 2);
plot(w_range, Tm_Sandia, 'g', 'LineWidth', 2);
plot(w_range, Tm_Faiman, 'r', 'LineWidth', 2);
plot(w_range, Tm_Fluid, 'm', 'LineWidth', 2);

xlabel('Wind Speed (m/s)');
ylabel('Average Module Temperature (°C)');
title('Temperature Models vs Wind Speed');

legend('INOCT','Duffie','Sandia','Faiman','Fluid','Location','best');
grid on;