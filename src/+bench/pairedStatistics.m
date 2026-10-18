function out = pairedStatistics(rows, mode)
    if nargin < 2
        mode = 'scipy_1_17';
    end
    assert(ismember(mode, {'scipy_1_17', 'none'}), 'Unknown statistics mode');
    out = struct([]);
    if isempty(rows)
        return
    end

    if isfield(rows, 'fitness_id')
        fitnesses = unique({rows.fitness_id}, 'stable');
    else
        fitnesses = {'fitness_1'};
    end

    for f = 1:numel(fitnesses)
        fitnessId = fitnesses{f};
        if isfield(rows, 'fitness_id')
            subset = rows(strcmp({rows.fitness_id}, fitnessId));
        else
            subset = rows;
        end
        names = sort(unique({subset.algorithm}));

        for i = 1:numel(names)
            for j = i + 1:numel(names)
                left = subset(strcmp({subset.algorithm}, names{i}));
                right = subset(strcmp({subset.algorithm}, names{j}));
                delta = [];
                for q = 1:numel(left)
                    ix = find(strcmp({right.scenario_id}, left(q).scenario_id) & [right.seed] == left(q).seed, 1);
                    if ~isempty(ix)
                        delta(end + 1) = left(q).optimization_score - right(ix).optimization_score; %#ok<AGROW>
                    end
                end
                nonzero = delta(abs(delta) > 1e-12);
                [~, ix] = sort(abs(nonzero));
                v = nonzero(ix);
                positive = 0;
                negative = 0;
                k = 1;
                while k <= numel(v)
                    last = k + 1;
                    while last <= numel(v) && abs(abs(v(last)) - abs(v(k))) <= 1e-12
                        last = last + 1;
                    end
                    rank = .5 * (k + last - 1);
                    positive = positive + sum(v(k:last - 1) > 0) * rank;
                    negative = negative + sum(v(k:last - 1) < 0) * rank;
                    k = last;
                end
                effect = 0;
                if positive + negative > 0
                    effect = (positive - negative) / (positive + negative);
                end
                p = [];
                if ~isempty(nonzero) && strcmp(mode, 'scipy_1_17')
                    p = bench.wilcoxon(delta);
                end
                if isempty(delta)
                    mn = 0;
                    md = 0;
                else
                    mn = mean(delta);
                    md = median(delta);
                end
                pairRecord = struct('fitness_id', fitnessId, 'fitness_label', vefc.FitnessLibrary.label(fitnessId), 'algorithm_a', names{i}, 'algorithm_b', names{j}, 'metric', 'optimization_score', 'paired_sample_count', numel(delta), 'mean_difference_a_minus_b', mn, 'median_difference_a_minus_b', md, 'wins_a', sum(delta > 1e-12), 'ties', sum(abs(delta) <= 1e-12), 'wins_b', sum(delta < -1e-12), 'rank_biserial_a_minus_b', effect, 'wilcoxon_two_sided_p', p, 'holm_adjusted_p', []);
                if isempty(out)
                    out = pairRecord;
                else
                    out(end + 1) = pairRecord;
                end
            end
        end
    end

    % Holm correction is applied within each fitness because each fitness is
    % a distinct objective landscape.
    if ~isempty(out)
        for f = 1:numel(fitnesses)
            idxF = find(strcmp({out.fitness_id}, fitnesses{f}));
            available = idxF(~cellfun(@isempty, {out(idxF).wilcoxon_two_sided_p}));
            if isempty(available)
                continue
            end
            [~, ix] = sort([out(available).wilcoxon_two_sided_p]);
            available = available(ix);
            running = 0;
            for k = 1:numel(available)
                j = available(k);
                running = max(running, min(1, out(j).wilcoxon_two_sided_p * (numel(available) - k + 1)));
                out(j).holm_adjusted_p = running;
            end
        end
    end
end
