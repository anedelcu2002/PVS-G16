function constraints = bind_grid_charging(vars, data, params)
    T = numel(data.P_load);
    constraint_list = [];

    for t = 1:T
        % Disallow grid-to-battery
        c1 = (vars.p_ch_grid(t) == 0);

        % Solar-only charging: cannot exceed available PV after curtailment
        avail_pv = vars.x_pv * data.P_solar_unit(t);
        c2 = (vars.p_ch_solar(t) <= avail_pv - vars.p_curt(t));

        if t == 1
            constraint_list = [c1, c2];
        else
            constraint_list = [constraint_list, c1, c2];
        end
    end

    constraints = constraint_list;
end