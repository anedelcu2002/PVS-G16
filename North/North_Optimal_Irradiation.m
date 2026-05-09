
%% Load dataset
data = readtable('Goa-hour.csv');

%% Extract variables
Gbn = data.G_Bn;
Gdh = data.G_Dh;
Ggh = data.G_Gh;

hs = deg2rad(data.hs);

%% Azimuth conversion
Az = mod(data.Az + 180, 360);
Az = deg2rad(Az);

%% Optimal orientation
beta = deg2rad(15); %TOY WITH THIS
Ap   = deg2rad(0);

albedo = 0.168;   % FIXED

%% Extraterrestrial radiation (YOUR FORMULA)
G_sc = 1367;

DOY = day(datetime(data.Year, data.Month, data.Day), 'dayofyear');
b = 2*pi*DOY/365;

E0 = 1.00011 ...
   + 0.034221*cos(b) ...
   + 0.00128*sin(b) ...
   + 0.000719*cos(2*b) ...
   + 0.000077*sin(2*b);

G_on = G_sc .* E0;

%% AOI
alpha_F = Az - Ap;
alpha_F = atan2(sin(alpha_F), cos(alpha_F));

cos_theta_i = sin(hs).*cos(beta) + ...
              cos(hs).*sin(beta).*cos(alpha_F);

%% Errata condition
mask = (cos_theta_i > 0) & (hs > 0);

%% DIRECT
G_dir = zeros(size(Gbn));
G_dir(mask) = Gbn(mask) .* cos_theta_i(mask);

%% HAY–DAVIES DIFFUSE 
Ai = Gbn ./ G_on;
Ai(Ai < 0) = 0;
Ai(Ai > 1) = 1;

cosZ = sin(hs);
cosZ(cosZ <= 0) = 1e-6;

Rb = cos_theta_i ./ cosZ;
Rb(Rb < 0) = 0;

G_diff = Gdh .* ( ...
    Ai .* Rb + ...
    (1 - Ai) .* (1 + cos(beta)) / 2 ...
);

%% REFLECTED
G_refl = Ggh .* albedo .* (1 - cos(beta)) / 2;

%% TOTAL POA
G_POA = G_dir + G_diff + G_refl;

%% Annual irradiation
H_total = sum(G_POA);
H_kWh = H_total / 1000;

fprintf('Annual irradiation: %.2f kWh/m^2\n', H_kWh);

%% Build output table (EXCEL)
output = table( ...
    data.Year, data.Month, data.Day, data.Hour, ...
    G_dir, G_diff, G_refl, G_POA, ...
    'VariableNames', { ...
    'Year','Month','Day','Hour', ...
    'Direct_Irradiance', ...
    'Diffuse_Irradiance', ...
    'Reflected_Irradiance', ...
    'Total_Irradiance'});

%% Export
writetable(output, 'POA_Optimal_HayDavies.xlsx');

%% Plot
figure;
plot(G_POA(1:48), 'LineWidth', 1.5);
xlabel('Hour');
ylabel('Irradiance (W/m^2)');
title('POA Irradiance (First 2 Days)');
grid on;