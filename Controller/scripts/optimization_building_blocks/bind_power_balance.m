function constraints = bind_power_balance(vars, data, params)
    % BIND_POWER_BALANCE Power balance with optional slack and battery dispatch
    
    T = numel(data.P_load);
    constraint_list = [];
    battery_enabled = isfield(params, 'enable_battery') && params.enable_battery;
    slack_enabled = isfield(params, 'enable_slack') && params.enable_slack;
    backup_enabled = isfield(params, 'enable_backup') && params.enable_backup;
    
    for t = 1:T
        if battery_enabled
            % Power balance with battery dispatch
            if slack_enabled
                % With slack (supply side redundancy) - include backup too
                if backup_enabled
                    balance = (vars.x_pv * data.P_solar_unit(t) + ...
                              vars.x_wt * data.P_wind_unit(t) + ...
                              vars.p_dis(t) + vars.p_bg(t) + vars.slack(t) == ...
                              data.P_load(t) + vars.p_ch(t) + vars.p_curt(t));
                else
                    balance = (vars.x_pv * data.P_solar_unit(t) + ...
                              vars.x_wt * data.P_wind_unit(t) + ...
                              vars.p_dis(t) + vars.slack(t) == ...
                              data.P_load(t) + vars.p_ch(t) + vars.p_curt(t));
                end
            else
                % No slack (exact balance) - include backup if enabled
                if backup_enabled
                    balance = (vars.x_pv * data.P_solar_unit(t) + ...
                              vars.x_wt * data.P_wind_unit(t) + ...
                              vars.p_dis(t) + vars.p_bg(t) == ...
                              data.P_load(t) + vars.p_ch(t) + vars.p_curt(t));
                else
                    balance = (vars.x_pv * data.P_solar_unit(t) + ...
                              vars.x_wt * data.P_wind_unit(t) + ...
                              vars.p_dis(t) == ...
                              data.P_load(t) + vars.p_ch(t) + vars.p_curt(t));
                end
            end
        else
            % MVP mode without battery
            if slack_enabled
                % With slack (feasibility valve)
                balance = (vars.x_pv * data.P_solar_unit(t) + ...
                          vars.x_wt * data.P_wind_unit(t) + ...
                          vars.slack(t) >= data.P_load(t));
            else
                % Strict renewables (no slack)
                balance = (vars.x_pv * data.P_solar_unit(t) + ...
                          vars.x_wt * data.P_wind_unit(t) >= data.P_load(t));
            end
        end
        
        if t == 1
            constraint_list = balance;
        else
            constraint_list = [constraint_list, balance];
        end
    end
    
    constraints = constraint_list;
end