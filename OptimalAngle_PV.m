clear all; clc;

%% Load dataset
Raw_Hourly_Data = readtable('Goa-hour.csv');

%% Extract variables
Gbn = Raw_Hourly_Data.G_Bn;   % DNI
Gdh = Raw_Hourly_Data.G_Dh;   % Diffuse
Ggh = Raw_Hourly_Data.G_Gh;   % Global

hs = deg2rad(Raw_Hourly_Data.hs);

%% Azimuth conversion (Meteonorm → course)
Az = mod(Raw_Hourly_Data.Az + 180, 360);
Az = deg2rad(Az);

%% Constants
albedo = 0.168;
G_sc = 1367;

%% Day of year
DOY = day(datetime(Raw_Hourly_Data.Year, ...
                   Raw_Hourly_Data.Month, ...
                   Raw_Hourly_Data.Day), 'dayofyear');

%% Extraterrestrial radiation (YOUR FORMULA)
b = 2*pi*DOY/365;

E0 = 1.00011 ...
   + 0.034221*cos(b) ...
   + 0.00128*sin(b) ...
   + 0.000719*cos(2*b) ...
   + 0.000077*sin(2*b);

G_on = G_sc .* E0;

%% Zenith cosine
cos_theta_z = sin(hs);
cos_theta_z(cos_theta_z <= 0) = 1e-6;

%% Storage
H = zeros(91, 360);

%% MAIN LOOP
for beta_deg = 0:90
    beta = deg2rad(beta_deg);
    
    for Ap_deg = 0:359
        Ap = deg2rad(Ap_deg);
        
        %% Relative azimuth (FIXED)
        alpha_F = Az - Ap;
        alpha_F = atan2(sin(alpha_F), cos(alpha_F));
        
        %% AOI (Equation 13)
        cos_theta_i = sin(hs).*cos(beta) + ...
                      cos(hs).*sin(beta).*cos(alpha_F);
        
        %% Errata condition
        mask = (cos_theta_i > 0) & (hs > 0);
        
        %% DIRECT
        G_dir = zeros(size(Gbn));
        G_dir(mask) = Gbn(mask) .* cos_theta_i(mask);
        
       %% ---- HAY–DAVIES DIFFUSE (STRICT FROM SLIDE) ----

% Anisotropy index
Ai = Gbn ./ G_on;

% Clamp values
Ai(Ai < 0) = 0;
Ai(Ai > 1) = 1;

% Zenith cosine
cosZ = sin(hs);
cosZ(cosZ <= 0) = 1e-6;

% Beam ratio
Rb = cos_theta_i ./ cosZ;
Rb(Rb < 0) = 0;

% Diffuse irradiance
G_diff = Gdh .* ( ...
    Ai .* Rb + ...
    (1 - Ai) .* (1 + cos(beta)) / 2 ...
);
        
        %% REFLECTED
        G_refl = Ggh .* albedo .* (1 - cos(beta)) / 2;
        
        %% TOTAL POA
        G_POA = G_dir + G_diff + G_refl;
        
        %% ANNUAL IRRADIATION
        H(beta_deg+1, Ap_deg+1) = sum(G_POA);
    end
end

%% PLOT HEATMAP
figure;
imagesc(0:359, 0:90, H);
xlabel('Azimuth (deg)');
ylabel('Tilt (deg)');
title('Annual Irradiation (Wh/m^2)');
colorbar;

%% FIND OPTIMUM
[max_val, idx] = max(H(:));
[row, col] = ind2sub(size(H), idx);

optimal_tilt = row - 1;
optimal_azimuth = col - 1;

fprintf('Optimal tilt: %d deg\n', optimal_tilt);
fprintf('Optimal azimuth: %d deg\n', optimal_azimuth);

%% OPTIMAL IRRADIATION
H_opt = H(optimal_tilt + 1, optimal_azimuth + 1);
H_opt_kWh = H_opt / 1000;

fprintf('Annual irradiation at optimum: %.2f kWh/m^2\n', H_opt_kWh);

%% LINE PLOT (TILT)
Ap_south = 180;
irr_vs_tilt = H(:, Ap_south + 1);

figure;
plot(0:90, irr_vs_tilt, 'LineWidth', 2);
xlabel('Tilt (deg)');
ylabel('Irradiation (Wh/m^2)');
title('Irradiation vs Tilt (South-facing)');
grid on;

%% LINE PLOT (AZIMUTH)
beta_fixed = 15;
irr_vs_azimuth = H(beta_fixed + 1, :);

figure;
plot(0:359, irr_vs_azimuth, 'LineWidth', 2);
xlabel('Azimuth (deg)');
ylabel('Irradiation (Wh/m^2)');
title('Irradiation vs Azimuth (Tilt = 15°)');
grid on;

%% MARK OPTIMUM
figure;
imagesc(0:359, 0:90, H);
colorbar;
xlabel('Azimuth (deg)');
ylabel('Tilt (deg)');
title('Annual Irradiation (Wh/m^2)');

hold on;
plot(optimal_azimuth, optimal_tilt, 'ro', 'MarkerSize', 8, 'LineWidth', 2);
text(optimal_azimuth+5, optimal_tilt, 'Optimal', 'Color', 'red');