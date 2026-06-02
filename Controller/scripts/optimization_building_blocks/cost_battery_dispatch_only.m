function obj = cost_battery_dispatch_only(vars, data, params)
    % COST_BATTERY_DISPATCH_ONLY Dispatch-only costs for fixed battery (ED mode)
    %
    % In Economic Dispatch mode with fixed battery capacity, this function
    % computes only dispatch/operational costs (excludes capex and FOM).
    %
    % Currently returns 0 as there are no explicit variable dispatch costs
    % for battery cycling in the simplified model. Could be extended to include:
    %  - Energy losses (round-trip efficiency)
    %  - Degradation costs
    %  - Cycling costs
    
    if ~isfield(params, 'enable_battery') || ~params.enable_battery
        obj = 0;
        return;
    end
    
    if ~isfield(vars, 'E_bess') || ~isfield(vars, 'p_ch') || ~isfield(vars, 'p_dis')
        obj = 0;
        return;
    end
    
    % No variable dispatch costs modeled for battery cycling currently
    % Placeholder for future expansion (e.g., degradation model)
    obj = 0;
end
