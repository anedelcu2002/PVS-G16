function obj = cost_grid(vars, data, params)
    price = get_param_or_default(params, 'grid_price_eur_per_kwh', 0.2);
    E_grid_kwh = sum(vars.p_grid) * params.dt_h;
    obj = price * E_grid_kwh;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end