function ghg = cost_ghg_lifecycle(vars, data, params)
    % COST_GHG_LIFECYCLE Lifecycle GHG emissions from embedded emissions only
    %
    % Computes lifecycle greenhouse gas emissions (kg CO2-eq/year):
    %   - PV manufacturing & disposal (per inverter unit)
    %   - Wind turbine manufacturing & disposal (per turbine unit)
    %   - Battery manufacturing & disposal (per Wh of storage capacity)
    %   - Backup system manufacturing & disposal (per W of power capacity)
    %
    % Assumptions:
    %   - Biomass fuel assumed carbon-neutral (excluded from fuel emissions)
    %   - All intensities are per unit or per energy/power unit
    
    ghg = 0;
    
    % ========== PV EMISSIONS ==========
    % Intensity: kg CO2-eq per inverter unit
    if isfield(vars, 'x_pv')
        ghg_intensity_pv_per_unit = get_param_or_default(params, 'ghg_intensity_pv_per_unit', 1);
        ghg = ghg + ghg_intensity_pv_per_unit * vars.x_pv;
    end
    
    % ========== WIND EMISSIONS ==========
    % Intensity: kg CO2-eq per turbine unit
    if isfield(vars, 'x_wt')
        ghg_intensity_wt_per_unit = get_param_or_default(params, 'ghg_intensity_wt_per_unit', 1);
        ghg = ghg + ghg_intensity_wt_per_unit * vars.x_wt;
    end
    
    % ========== BATTERY EMISSIONS ==========
    % Intensity: kg CO2-eq per Wh of storage capacity
    if isfield(vars, 'E_bess')
        ghg_intensity_batt_per_wh = get_param_or_default(params, 'ghg_intensity_batt_per_wh', 1);
        ghg = ghg + ghg_intensity_batt_per_wh * vars.E_bess;
    end
    
    % ========== BACKUP SYSTEM EMISSIONS ==========
    % Intensity: kg CO2-eq per W of backup power capacity
    if isfield(vars, 'P_backup')
        ghg_intensity_backup_per_w = get_param_or_default(params, 'ghg_intensity_backup_per_w', 1);
        ghg = ghg + ghg_intensity_backup_per_w * vars.P_backup;
    end
    
    % ========== BACKUP DISPATCH EMISSIONS ==========
    % Intensity: kg CO2-eq per Wh of fuel-based backup energy dispatched (operational emissions)
    if isfield(vars, 'p_bg')
        ghg_intensity_backup_per_Wh_dispatch = get_param_or_default(params, 'ghg_intensity_backup_per_Wh_dispatch', 0);
        dt_h = get_param_or_default(params, 'dt_h', 1.0);
        ghg = ghg + ghg_intensity_backup_per_Wh_dispatch * sum(vars.p_bg) * dt_h;
    end
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
