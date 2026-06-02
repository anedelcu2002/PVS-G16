% Wind generation profile
function [Wind, windCsvPath] = step05a_generate_wind_profile_for_1_turbine(inputsDir, outDir)

    fprintf("==============================\n")
    fprintf("------ Wind Generation -------\n")
    fprintf("==============================\n")

    % clear "a"
    % clear "s"
    % Loading in the hourly wind data from De Bilt
    T = readtable(fullfile(inputsDir,"Wind-data-hourly-De-Bilt.csv"));
    
    % As the concept of 0 is not a thing in matlab I shift all 0 values by a very slight bit. 
    v01 = T{:,1};         
    v01(v01==0) = eps;     
    % Divide by 10 to account for the fact that all of the data is in 0.1 m/s
    u = v01/10;
    % The measured data of the weather station is measured at 10 m high, but this needs to be converted to the wind profile at hub height of the wind turbine.
    % The height of the chosen windturbine is 155 meters. 
    % As it is not reasonable to put a park of wind turbines in the centre of Amersfoort a spot west of Amersfoort was chosen at between 5.31 and 5.35 E and 52.21 and 52.17 N 
    % The roughness length in this area is 0.03 with some buildings causing a slight bit of interference. This will be accounted for by choosing a slightly higher value of 0.04.
    
    % u(155) = u(10) * ln (155/0.04)/ln(10/0.04)
    
    h_1 = 10;
    h_inter = 60;
    h_2 = 155;
    u_comp = u * log(60/0.04)/log(10/0.04);
    alpha = 0.143; %This should be iterated upon perhaps to get a better value for alpha
    v = u_comp * (h_2/h_inter)^alpha;
    %z_0 = 0.04;
    %v = u * (log(h_2/z_0)/log(h_1/z_0));
    
    a = fitdist(v,"Weibull");
    
    scale = 5.11405;
    shape= 1.28658;
    
    
    % The weather stations measure the wind at about 10 meters. 
    % The wind profile needs to be built
    % Wind turbine dimensioning, the turbine I chose was the Vestas V150-4.2 MW™. 
    % As it seemed fit for the type of wind profile that was found for De Bilt/Amersfoort (Relatively low average wind speed) 
    
    % I added rng in order to get the same results in every run.
    rng(1,"twister");
    t = 1:(366*24);
    s = [];
    v_cutin  = 3; % m/s
    v_cutout  = 22.5; % m/s
    for i = 1:length(t)
        
        % Get a random windspeed based on the shape and scale factors
        P = wblrnd(scale,shape);
        % I did the slightly basic thing of assuming no wind was blowing when
        % the probability that the Weibull function spat out was lower than 3
        % or higher than 22.5
        if P < v_cutin
            P = 0;
        elseif P > v_cutout    
            P = 0; 
        end
        % Append it to a larger vector
        
        s = [s;P];
    end
    
    rho = 1.229; %kg/m^3 
    A = 17671; %m 
    
    C_d = (4.2*10^6 / (0.5*rho*A*9.9^3 ));
    
    P_v = 0.5 * rho * A * C_d * power(s,3);
    P_max = 4.2 *10^6;
    
    P_out = min(P_max,P_v)*3600;
       
    % % N = 240; % A nice round number to have the winmdmills supply the power based on the sum total of P_req which is the sum total of the electricity needed
    % N = ceil(sum(P_req)/ sum(P_out)); % We need 36 wind turbines to cover half of the demand of electricity + losses
    % fprintf('Total wind turbines: %d\n', N);
    % P_c = P_out * N;
    % E_Wind_Generation = sum(P_c); % in J
    
    yearNum = 2024;
    t0 = datetime(yearNum,1,1,0,0,0);
    t1 = datetime(yearNum+1,1,1,0,0,0);   % start of next year (exclusive)
    t = (t0:minutes(60):t1-minutes(60)).'; % column vector
    t_sec = seconds(t - t(1)); % s
    
    if ~exist(outDir,'dir'); mkdir(outDir); end
    windCsvPath = fullfile(outDir,sprintf('wind_profile_1_turbine.csv'));
    
    T = table(t, P_out(:), 'VariableNames', {'DateTime','WindEnergy_J'});
    writetable(T, windCsvPath); % in J

    Wind = [t_sec P_out /3600]; % in W
    subplot(1,2,1)
    
    h = histogram(P_out, "BinWidth",1E9, "BinLimits",[2E9,16E9]);
    title("Histogram of the poweroutput of the windturbine per hour (GJ)");
    xlabel("Poweroutput per hour in GJ");
    subplot(1,2,2)
    plot(a)
    title("Weibull distribution of the windspeed at 155 meters")
    xlabel("Windspeed in m/s")
    P_rated_farm_W = 4.2e6;          % 4.2 MW per turbine

    CF = mean(Wind(:,2)) / P_rated_farm_W;
    fprintf("Capacity Factor = %3f \n", CF);
end
 
 
