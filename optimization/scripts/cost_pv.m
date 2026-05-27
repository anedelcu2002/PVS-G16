function obj = cost_pv(vars, data, params)
    % COST_PV 3-year total PV cost (CapEx + FOM * project_life)
    obj = (params.c_pv_unit_capex + params.c_pv_unit_fom_per_year * params.project_life) * ...
          (vars.x_pv + vars.x_pv2);
end