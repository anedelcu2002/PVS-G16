function constraints = bind_battery_curtailment(vars, data, params)
    % BIND_BATTERY_CURTAILMENT (DEPRECATED - use bind_curtailment instead)
    %
    % This function is kept for backward compatibility.
    % Curtailment is now a separate, independent constraint.
    % See bind_curtailment.m for the actual implementation.
    
    % For backward compatibility: if called, delegate to bind_curtailment
    % But only apply if battery is explicitly enabled
    if ~isfield(params, 'enable_battery') || ~params.enable_battery
        constraints = [];
        return;
    end
    
    % If curtailment is disabled, return empty
    if ~isfield(params, 'enable_curtailment') || ~params.enable_curtailment
        constraints = [];
        return;
    end
    
    % Otherwise, delegate to the new independent bind_curtailment
    constraints = bind_curtailment(vars, data, params);
end

