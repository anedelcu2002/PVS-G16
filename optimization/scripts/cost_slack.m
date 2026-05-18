function obj = cost_slack(vars, data, params)
    % COST_SLACK Fixed hourly penalty for any unmet demand
    
    penalty_per_hour = get_param_or_default(params, 'slack_hourly_penalty_eur', 112.5);
    obj = penalty_per_hour * sum(vars.u_slack);
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end