'clc';
clear 'all'

Soort = 'SW4048';

Gen = readtable("Final_8760_Generation.xlsx");
Gen = Gen(1:8760,2:3);
P_dc = table2array(Gen);
switch Soort
    case 'XW6848'
        A = 6.75776E+03;
        B = 4.2E+01;
        C = -1.2E-05;		
        Vdc = 48;
        P_ac0 = 6.12E+03;
        fprintf('Inverter type is XW6848 \n')
    case 'SW4024'
        A = 3.655E+03;
    	B = 4.2E+01;
        C = -1.2E-05;
        Vdc = 24;
        P_ac0 = 3.4E+03;
        fprintf('Inverter type is SW4024 \n')
    case 'SW4048'
        A = 4.086+03;
        B = 4.2E+01;
        C = -1.2E-05;
        Vdc = 48;
        P_ac0 = 3.8E+03;
        fprintf('Inverter type is SW4048 \n')
    otherwise    
        disp('No inverter type was chosen')
end

P_comp = 3600*1000*P_dc;


%It seems to go wrong here, but what the hell could be the problem?
P_ac = max(((P_ac0/(A-B))-C*(A-B))*(P_comp-B)+C*power((P_comp-B),2),0)./(1000*3600);
t=linspace(0,8760,8760);
avg= movmean(P_ac,24);
plot(t,P_ac(:,1),t,avg)



%writematrix(P_ac,'SW4048.csv')




