function [strategy, probabilities] = cpoDefenseSchedule(progress, rng)
    % Shared VEFC LINEAR defense schedule for the active CPO and restored DCPO implementations.
    % Not the fixed-probability policy of Abdel-Basset et al. (2024).
    % Initial: Sight/Sound/Odor/Attack = 25/25/40/10 percent.
    % Final:   Sight/Sound/Odor/Attack =  5/ 5/15/75 percent.
    p = max(0, min(1, double(progress)));
    probabilities = [.25 - .20*p, .25 - .20*p, .40 - .25*p, .10 + .65*p];
    assert(all(probabilities >= 0) && abs(sum(probabilities) - 1) < 1e-12, ...
        'Invalid CPO/DCPO defense probabilities');
    draw = rng.random();
    strategy = find(draw < cumsum(probabilities), 1, 'first');
    if isempty(strategy)
        strategy = 4;
    end
end
