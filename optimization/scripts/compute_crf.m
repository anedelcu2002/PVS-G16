function crf = compute_crf(discount_rate, project_life)
    % COMPUTE_CRF Capital Recovery Factor
    if discount_rate == 0
        crf = 1 / project_life;
        return;
    end
    crf = discount_rate * (1 + discount_rate)^project_life / ...
        ((1 + discount_rate)^project_life - 1);
end