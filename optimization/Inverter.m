'clc';
clear 'all'

Soort = 'SW4048';

Gen = readtable("Final_8760_Generation.xlsx");
Gen = Gen(1:8760,2:3);
P_dc = table2array(Gen).*1000;
       
switch Soort
    case 'XW6848'
        A = 6.75776E+03;
        B = 4.2E+01;
        C = -1.2E-05;		
        Vdc = 48;
        P_ac0 = 6.12E+03;
        %fprintf('Inverter type is XW6848 \n')
    case 'SW4024'
        A = 3.655E+03;
    	B = 4.2E+01;
        C = -1.2E-05;
        Vdc = 24;
        P_ac0 = 3.4E+03;
        %fprintf('Inverter type is SW4024 \n')
    case 'SW4048'
        A = 4.086E+03;
        B = 4.2E+01;
        C = -1.2E-05;
        Vdc = 48;
        P_ac0 = 3.8E+03;
        %fprintf('Inverter type is SW4048 \n')
    otherwise    
        disp('No inverter type was chosen')
        
end




%It seems to go wrong here, but what the hell could be the problem?
P_ac = max((((P_ac0/(A-B))-C*(A-B))*(P_dc-B)+C*power((P_dc-B),2)),0);
t=linspace(0,length(P_dc),length(P_dc));
eff = P_ac./(P_dc+10E-16);


subplot(1,2,1)
plot(t,eff(:,1),t,eff(:,2))
legend('Longi-power','Aiko-power')

avg= movmean(eff,24);
subplot(1,2,2)
plot(t,avg(:,1),t,avg(:,2))
legend('Longi-eff','Aiko-eff')

writematrix(eff,'effSW4048.csv')

Dccheck = P_dc >0;
Pnonzero = sum(Dccheck)/length(P_dc)
disp(mean(avg))
effcheck = eff>0;
share = sum(effcheck)/length(eff)

