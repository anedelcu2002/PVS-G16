function constraints = bind_power_balance(vars, data, params)
    % BIND_POWER_BALANCE Power balance with optional slack and battery dispatch
    
    T = numel(data.P_load);
    constraint_list = [];
    
    for t = 1:T
        balance = (vars.x_pv * data.P_solar_unit(t) + ...
                    vars.p_dis(t) + vars.slack(t) == ...
                    data.P_load(t) + vars.p_ch(t) + vars.p_curt(t));
        
        if t == 1
            constraint_list = balance;
        else
            constraint_list = [constraint_list, balance];
        end
    end
    
    constraints = constraint_list;
end