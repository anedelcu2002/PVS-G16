function obj = cost_battery(vars, data, params)
    % COST_BATTERY Battery capex and FOM costs
    %
    % Computes annualized battery costs:
    %   - Capex: annualized capital cost via CRF
    %   - FOM: fixed annual operating & maintenance cost
    
    dt_h = params.dt_h;
    discount_rate = params.discount_rate;
    project_life = params.project_life;
    
    % Capital recovery factor for levelization
    CRF = discount_rate * (1 + discount_rate)^project_life / ...
          ((1 + discount_rate)^project_life - 1);
    
    % Battery costs per kWh
    c_bess_E_capex = get_param_or_default(params, 'c_bess_E_capex_per_kWh', 0.1);      % $/kWh
    c_bess_E_fom = get_param_or_default(params, 'c_bess_E_fom_per_kWh_yr', 0.005);    % $/kWh/year
    
    % Annualized battery cost = capex + FOM
    obj_battery = CRF * c_bess_E_capex * vars.E_bess + c_bess_E_fom * vars.E_bess;
    
    obj = obj_battery;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
