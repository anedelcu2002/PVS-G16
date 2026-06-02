function cost = cost_backup(vars, data, params)
    % COST_BACKUP Backup generation cost function
    %
    % Computes annualized backup costs:
    %   CRF * (capex + FOM) + (VOM + fuel) * sum(p_bg)
    %
    % where CRF = Capital Recovery Factor
    
    if ~isfield(params, 'enable_backup') || ~params.enable_backup
        cost = 0;
        return;
    end
    
    if ~isfield(vars, 'P_backup') || ~isfield(vars, 'p_bg')
        cost = 0;
        return;
    end
    
    dt_h = params.dt_h;
    
    % Economics parameters
    discount_rate = get_param_or_default(params, 'discount_rate', 0.05);
    project_life = get_param_or_default(params, 'project_life', 20);
    
    c_backup_capex_per_W = get_param_or_default(params, 'c_backup_capex_per_W', 0);
    c_backup_fom_per_W_yr = get_param_or_default(params, 'c_backup_fom_per_W_yr', 0);
    c_backup_vom_per_Wh = get_param_or_default(params, 'c_backup_vom_per_Wh', 0);
    c_fuel_per_Wh_el = get_param_or_default(params, 'c_fuel_per_Wh_el', 0);
    
    % Capital Recovery Factor
    CRF = discount_rate * (1 + discount_rate)^project_life / ...
        ((1 + discount_rate)^project_life - 1);
    
    % Backup capex and FOM (annualized)
    capex_fom = CRF * c_backup_capex_per_W * vars.P_backup + ...
                c_backup_fom_per_W_yr * vars.P_backup;
    
    % Backup dispatch cost (VOM + fuel)
    dispatch_cost = (c_backup_vom_per_Wh + c_fuel_per_Wh_el) * sum(vars.p_bg) * dt_h;
    
    cost = capex_fom + dispatch_cost;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
