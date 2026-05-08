function constraints = bind_grid_availability(vars, data, params)
    % data.P_blackout: 1 = blackout, 0 = available
    T = numel(data.P_load);
    constraint_list = [];

    % Big-M for "unlimited" grid import when available
    grid_big_m = get_param_or_default(params, 'grid_big_m', 1e6);

    for t = 1:T
        availability = 1 - data.P_blackout(t);
        c = (vars.p_grid(t) <= grid_big_m * availability);

        if t == 1
            constraint_list = c;
        else
            constraint_list = [constraint_list, c];
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