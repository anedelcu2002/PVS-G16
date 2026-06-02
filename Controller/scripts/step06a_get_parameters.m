function pars = step06a_get_parameters()
%GET_PARAMS Returns all model/economic parameters in one struct

    % General
    pars.dt_h = 1.0;
    pars.soc_min = 0.10;
    pars.soc_max = 0.90;
    pars.eta_ch = sqrt(0.93);
    pars.eta_dis = sqrt(0.93);
    pars.soc0 = 0.50;
    pars.battery_c_rating = 0.25;

    % Upper bounds
    pars.x_pv_ub = 1000;
    pars.x_wt_ub = 100;
    pars.E_bess_ub = 100 * 10e9;     % GWh
    pars.P_backup_ub = 100 * 10e9;    % GW

    % Economics
    pars.discount_rate = 0.05;
    pars.project_life = 20;

    pars.c_pv_unit_capex = 100000;
    pars.c_pv_unit_fom_per_year = 1500;

    pars.c_wt_unit_capex = 400000;
    pars.c_wt_unit_fom_per_year = 8000;

    pars.c_bess_E_capex_per_Wh = 250;
    pars.c_bess_E_fom_per_Wh_yr = 5;

    pars.c_backup_capex_per_W = 100;
    pars.c_backup_fom_per_W_yr = 100;
    pars.c_backup_vom_per_Wh = 100.00;
    pars.c_fuel_per_Wh_el = 110.0;
end