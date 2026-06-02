function obj = cost_heat_generation(~, ~, params)
    % COST_HEAT_GENERATION System-level heat generation cost
    %
    % Computes annualized heat generation (geothermal HP) costs:
    %   - CAPEX: one-time investment annualized via CRF
    %   - OPEX: annual operating costs
    
    if ~isfield(params, 'enable_heat_generation') || ~params.enable_heat_generation
        obj = 0;
        return;
    end
    
    % Extract parameters
    c_hg_capex_total = get_param_or_default(params, 'c_hg_capex_total', 0);
    c_hg_opex_annual = get_param_or_default(params, 'c_hg_opex_annual', 0);
    
    % Annualize CAPEX via CRF
    discount_rate = get_param_or_default(params, 'discount_rate', 0.06);
    project_life = get_param_or_default(params, 'project_life', 20);
    
    CRF = discount_rate * (1 + discount_rate)^project_life / ...
          ((1 + discount_rate)^project_life - 1);
    
    % Total annualized cost
    obj = CRF * c_hg_capex_total + c_hg_opex_annual;
end

function val = get_param_or_default(params, field, default)
    if isfield(params, field)
        val = params.(field);
    else
        val = default;
    end
end
