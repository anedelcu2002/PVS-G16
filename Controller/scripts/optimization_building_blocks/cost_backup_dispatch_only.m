function cost = cost_backup_dispatch_only(vars, data, params)
    % COST_BACKUP_DISPATCH_ONLY Dispatch-only costs for fixed backup (ED mode)
    %
    % In Economic Dispatch mode with fixed backup power capacity, this function
    % computes only dispatch costs (VOM + fuel), excluding capex and FOM.
    %
    % Cost = (VOM + fuel_cost) * sum(p_bg) * dt_h
    
    if ~isfield(params, 'enable_backup') || ~params.enable_backup
        cost = 0;
        return;
    end
    
    if ~isfield(vars, 'p_bg')
        cost = 0;
        return;
    end
    
    dt_h = params.dt_h;
    
    % Dispatch cost parameters (VOM + fuel, no capex/FOM)
    c_backup_vom_per_Wh = get_param_or_default(params, 'c_backup_vom_per_Wh', 0);
    c_fuel_per_Wh_el = get_param_or_default(params, 'c_fuel_per_Wh_el', 0);
    
    % Backup dispatch cost (VOM + fuel only)
    dispatch_cost = (c_backup_vom_per_Wh + c_fuel_per_Wh_el) * sum(vars.p_bg) * dt_h;
    
    cost = dispatch_cost;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
