function constraints = bind_backup(vars, data, params)
    % BIND_BACKUP Backup generation constraints
    %
    % Enforces:
    %   - Hourly backup power limit: p_bg(t) <= P_backup
    %   - Annual backup energy limit: sum(p_bg) * dt_h <= backup_pct * E_load_annual
    %
    % Backup generation represents dispatchable reserves (diesel, biomass, grid, etc.)

    if ~isfield(params, 'enable_backup') || ~params.enable_backup
        constraints = [];
        return;
    end
    
    % Check that backup variables exist
    if ~isfield(vars, 'P_backup') || ~isfield(vars, 'p_bg')
        constraints = [];
        return;
    end
    
    T = numel(data.P_load);
    dt_h = params.dt_h;
    
    % Hourly backup power limit
    constraint_list = [];
    for t = 1:T
        constraint_list = [constraint_list, vars.p_bg(t) <= vars.P_backup];
    end
    
    % Annual backup energy limit (percentage of annual load)
    E_load_annual = sum(data.P_load) * dt_h;
    backup_energy_pct = get_param_or_default(params, 'backup_energy_pct', 0.20);
    max_annual_backup = backup_energy_pct * E_load_annual;
    
    annual_backup = sum(vars.p_bg) * dt_h <= max_annual_backup;
    constraint_list = [constraint_list, annual_backup];
    
    constraints = constraint_list;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
