function constraints = bind_battery_exclusivity(vars, data, params)
    % BIND_BATTERY_EXCLUSIVITY Charge/discharge mutual exclusivity using Big-M
    %
    % Enforces:
    %   - If z(t) = 1: can charge (p_ch > 0), discharge forced to 0
    %   - If z(t) = 0: can discharge (p_dis > 0), charge forced to 0
    % Uses Big-M constraints: p_ch <= P_max * z(t), p_dis <= P_max * (1 - z(t))
    
    if ~isfield(params, 'enable_battery') || ~params.enable_battery
        constraints = [];
        return;
    end
    
    T = numel(data.P_load);
    c_rating = get_param_or_default(params, 'battery_c_rating', 0.5);  % C-rating (h^-1)
    E_bess_ub = get_param_or_default(params, 'E_bess_ub', 1e10);
    P_bess_ub = E_bess_ub * c_rating;  % Max power upper bound for Big-M
    
    constraint_list = [];
    
    % Prevent simultaneous charge and discharge using binary mode
    % z(t) = 1 => charge mode; z(t) = 0 => discharge mode
    for t = 1:T
        ch_constraint = vars.p_ch(t) <= P_bess_ub * vars.z(t);
        dis_constraint = vars.p_dis(t) <= P_bess_ub * (1 - vars.z(t));
        
        if t == 1
            constraint_list = [ch_constraint, dis_constraint];
        else
            constraint_list = [constraint_list, ch_constraint, dis_constraint];
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
