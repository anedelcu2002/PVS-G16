function constraints = bind_battery_dynamics(vars, data, params)
    % BIND_BATTERY_DYNAMICS Battery energy state progression with efficiency losses
    %
    % Enforces: e_stored(t+1) = e_stored(t) + (eta_ch * p_ch(t) - p_dis(t)/eta_dis) * dt_h
    % with asymmetric charging and discharging losses
    
    if ~isfield(params, 'enable_battery') || ~params.enable_battery
        constraints = [];
        return;
    end
    
    T = numel(data.P_load);
    eta_ch = get_param_or_default(params, 'eta_ch', sqrt(0.93));      % Charge efficiency
    eta_dis = get_param_or_default(params, 'eta_dis', sqrt(0.93));    % Discharge efficiency
    dt_h = params.dt_h;
    
    constraint_list = [];
    
    % Energy balance: e_stored(t+1) = e_stored(t) + (eta_ch * p_ch - p_dis/eta_dis) * dt_h
    for t = 1:T
        eq = (vars.e_stored(t+1) == vars.e_stored(t) + (eta_ch * vars.p_ch(t) - vars.p_dis(t) / eta_dis) * dt_h);
        if t == 1
            constraint_list = eq;
        else
            constraint_list = [constraint_list, eq];
        end
    end
    
    constraints = constraint_list;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
