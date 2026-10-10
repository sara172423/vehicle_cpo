function out = nfeSummary(rows)
    out = struct([]);
    if isempty(rows)
        return
    end
    rows = rows(strcmp({rows.point_type}, 'best'));
    if isempty(rows)
        return
    end
    names = unique({rows.algorithm}, 'stable');
    groups = {};
    start = 0;
    stop = Inf;
    for j = 1:numel(names)
        seeds = unique([rows(strcmp({rows.algorithm}, names{j})).seed]);
        for seed = seeds
            sel = rows(strcmp({rows.algorithm}, names{j}) & [rows.seed] == seed);
            [~, ix] = sort([sel.function_evaluations]);
            sel = sel(ix);
            groups{end + 1} = sel;
            start = max(start, sel(1).function_evaluations);
            stop = min(stop, sel(end).function_evaluations);
        end
    end
    if stop < start
        return
    end
    if stop == start
        grid = stop;
    else
        grid = unique(optim.PythonRandom.roundEven(start + (stop - start) * (0:24) / 24));
    end
    for j = 1:numel(names)
        for nfe = grid
            vals = [];
            for k = 1:numel(groups)
                g = groups{k};
                if ~strcmp(g(1).algorithm, names{j})
                    continue
                end
                v = [g([g.function_evaluations] <= nfe).total_efficiency];
                vals(end + 1) = max(v);
            end
            st = bench.stats(vals);
            summaryRecord = struct('figure', 'figure_6', 'algorithm', names{j}, 'function_evaluations', nfe, 'best_total_efficiency', st.mean, 'best_total_efficiency_std', st.std, 'best_total_efficiency_ci95', st.ci95, 'best_total_efficiency_min', st.min, 'best_total_efficiency_max', st.max, 'sample_count', numel(vals), 'common_budget_start', start, 'common_budget_end', stop);
            if isempty(out)
                out = summaryRecord;
            else
                out(end + 1) = summaryRecord;
            end
        end
    end
end
