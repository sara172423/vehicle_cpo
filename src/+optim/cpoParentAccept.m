function [population, scores, accepted, gain] = cpoParentAccept(population, scores, parentIndex, child, childScore)
    % CPO Algorithm 1, parent-wise greedy replacement, adapted to MAXIMIZE Score.
    % Compare ONLY with the parent that generated this child.
    % No global replacement, truncation, or unrelated-parent competition.
    assert(parentIndex >= 1 && parentIndex <= size(population, 1) ...
        && parentIndex == fix(parentIndex), 'Invalid CPO parent index');
    assert(size(child, 1) == 1 && size(child, 2) == size(population, 2), ...
        'Invalid CPO child shape');
    assert(isfinite(childScore), 'Non-finite CPO child score');
    gain = double(childScore) - double(scores(parentIndex));
    accepted = gain > 1e-12;  % Only a strictly better child replaces the parent.
    if accepted
        population(parentIndex, :) = child;
        scores(parentIndex) = childScore;
    end
end
