function obj = cost_wt(vars, data, params)
    % COST_WT Wind turbine sizing cost (CapEx + FOM)
    CRF = compute_crf(params.discount_rate, params.project_life);
    obj = CRF * params.c_wt_unit_capex * vars.x_wt + ...
          params.c_wt_unit_fom_per_year * vars.x_wt;
end
