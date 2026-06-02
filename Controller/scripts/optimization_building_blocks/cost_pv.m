function obj = cost_pv(vars, data, params)
    % COST_PV PV sizing cost (CapEx + FOM)
    CRF = compute_crf(params.discount_rate, params.project_life);
    obj = CRF * params.c_pv_unit_capex * vars.x_pv + ...
          params.c_pv_unit_fom_per_year * vars.x_pv;
end
