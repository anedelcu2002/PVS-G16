function ghg = cost_ghg_lifecycle(vars, data, params)
    % COST_GHG_LIFECYCLE Lifecycle GHG emissions from embedded emissions only
    %
    % Computes lifecycle greenhouse gas emissions (kg CO2-eq/year):
    %   - PV manufacturing & disposal (per inverter unit)
    %   - Battery manufacturing & disposal (per kWh of storage capacity)
    %
    % Assumptions:
    %   - All intensities are per unit or per energy/power unit
    
    ghg = 0;
    
    % ========== PV EMISSIONS ==========
    % Intensity: kg CO2-eq per inverter unit
    if isfield(vars, 'x_pv')
        ghg_intensity_pv_per_unit = get_param_or_default(params, 'ghg_intensity_pv_per_unit', 1);
        ghg = ghg + ghg_intensity_pv_per_unit * vars.x_pv;
    end
    
    % ========== BATTERY EMISSIONS ==========
    % Intensity: kg CO2-eq per kWh of storage capacity
    if isfield(vars, 'E_bess')
        ghg_intensity_batt_per_kWh = get_param_or_default(params, 'ghg_intensity_batt_per_kWh', 1);
        ghg = ghg + ghg_intensity_batt_per_kWh * vars.E_bess;
    end
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
