function obj = cost_slack(vars, data, params)
    % COST_SLACK Penalty for unmet demand (slack variable) - only if enabled

    slack_enabled = isfield(params, 'enable_slack') && params.enable_slack;
    if ~slack_enabled
        obj = 0;
        return;
    end
    
    % Slack penalty when enabled
    penalty_per_kWh = 10000000;
    E_slack_kWh = sum(vars.slack) * params.dt_h;
    obj = penalty_per_kWh * E_slack_kWh;
end