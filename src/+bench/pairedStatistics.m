function out = pairedStatistics(rows, mode)
    if nargin < 2
        mode = 'scipy_1_17';
    end
    assert(ismember(mode, {'scipy_1_17', 'none'}), 'Unknown statistics mode');
    % Effect sizes match the uploaded benchmark; p-values are optional.
    out = struct([]);
    if isempty(rows)
        return
    end
    names = sort(unique({rows.algorithm}));
    for i = 1:numel(names)
        for j = i + 1:numel(names)
            left = rows(strcmp({rows.algorithm}, names{i}));
            right = rows(strcmp({rows.algorithm}, names{j}));
            delta = [];
            for q = 1:numel(left)
                ix = find(strcmp({right.scenario_id}, left(q).scenario_id) & [right.seed] == left(q).seed, 1);
                if ~isempty(ix)
                    delta(end + 1) = left(q).total_efficiency - right(ix).total_efficiency;
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
            pairRecord = struct('algorithm_a', names{i}, 'algorithm_b', names{j}, 'metric', 'total_efficiency', 'paired_sample_count', numel(delta), 'mean_difference_a_minus_b', mn, 'median_difference_a_minus_b', md, 'wins_a', sum(delta > 1e-12), 'ties', sum(abs(delta) <= 1e-12), 'wins_b', sum(delta < -1e-12), 'rank_biserial_a_minus_b', effect, 'wilcoxon_two_sided_p', p, 'holm_adjusted_p', []);
            if isempty(out)
                out = pairRecord;
            else
                out(end + 1) = pairRecord;
            end

        end
    end
    if ~isempty(out)
        available = find(~cellfun(@isempty, {out.wilcoxon_two_sided_p}));
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
