function p = wilcoxon(delta)
    % SciPy 1.17 method='auto', zero_method='wilcox', two-sided, correction=false.
    % Exact sign distributions for <=13 samples with ties/zeros; asymptotic beyond.
    delta = delta(:)';
    nTotal = numel(delta);
    v = delta(delta ~= 0);
    n = numel(v);
    if n == 0
        p = [];
        return
    end
    [values, ix] = sort(abs(v));
    ranks = zeros(size(v));
    tieCorrection = 0;
    k = 1;
    hasTies = false;
    while k <= n
        j = k + 1;
        while j <= n && values(j) == values(k)
            j = j + 1;
        end
        t = j - k;
        ranks(ix(k:j - 1)) = .5 * (k + j - 1);
        tieCorrection = tieCorrection + t^3 - t;
        hasTies = hasTies || t > 1;
        k = j;
    end
    positive = sum(ranks(v > 0));
    if nTotal <= 50 && ~hasTies && n == nTotal
        weights = 1:n;
        exact = true;
    elseif nTotal <= 13
        weights = round(2 * ranks);
        positive = 2 * positive;
        exact = true;
    else
        exact = false;
    end
    if exact
        probability = 1;
        for w = weights
            old = probability;
            probability = zeros(1, numel(old) + w);
            probability(1:numel(old)) = probability(1:numel(old)) + .5 * old;
            probability(w + 1:w + numel(old)) = probability(w + 1:w + numel(old)) + .5 * old;
        end
        lo = sum(probability(1:floor(positive) + 1));
        hi = sum(probability(ceil(positive) + 1:end));
        p = min(1, 2 * min(lo, hi));
    else
        mu = n * (n + 1) / 4;
        se = sqrt((n * (n + 1) * (2 * n + 1) - tieCorrection / 2) / 24);
        z = (positive - mu) / se;
        p = erfc(abs(z) / sqrt(2));
    end
end
