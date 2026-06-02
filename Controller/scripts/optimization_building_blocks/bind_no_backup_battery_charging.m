function constraints = bind_no_backup_battery_charging(vars, data, params)
% Forbid the battery from charging unless there is raw RES surplus
% before backup is used.
%
% Requires vars:
%   vars.x_pv   scalar
%   vars.x_wt   scalar
%   vars.p_ch   [T x 1]
% Optional but recommended:
%   vars.p_bg   [T x 1]
%
% This adds a binary z_sur(t):
%   z_sur(t) = 1  <=>  P_RES(t) >= P_load(t)
%
% Then enforces:
%   p_ch(t) <= P_RES(t) - P_load(t)    when surplus exists
%   p_ch(t) = 0                        when surplus does not exist
%
% This prevents backup-supported charging.

    T = numel(data.P_load);

    % Raw renewable generation expression [W]
    P_res = vars.x_pv * data.P_solar_unit(:) + vars.x_wt * data.P_wind_unit(:);

    % Binary indicator: 1 if raw RES surplus exists, 0 otherwise
    z_sur = binvar(T,1);

    % Big-M
    M = params.x_pv_ub * max(data.P_solar_unit) + ...
        params.x_wt_ub * max(data.P_wind_unit) + ...
        max(data.P_load);

    constraints = [];

    % Force z_sur to indicate whether P_res >= load
    constraints = [constraints, ...
        P_res - data.P_load(:) <= M * z_sur, ...
        data.P_load(:) - P_res <= M * (1 - z_sur)];

    % If no RES surplus -> no battery charging
    constraints = [constraints, ...
        vars.p_ch <= M * z_sur];

    % If RES surplus exists -> charging limited to that surplus
    constraints = [constraints, ...
        vars.p_ch <= P_res - data.P_load(:) + M * (1 - z_sur)];

    % Optional strengthening:
    % If there is raw RES surplus, force backup OFF.
    % This is not strictly required, but it tightens the model and
    % removes weird simultaneous "backup on during surplus" behavior.
    if isfield(vars, 'p_bg')
        constraints = [constraints, ...
            vars.p_bg <= params.P_backup_ub * (1 - z_sur)];
    end
end