function [best, ev, history] = dtosc(ctx, cfg)
    % Legacy DTOSC provider-path DP, preserved exactly as uploaded.
    % This is a DP comparator; its transition count is not a population NFE count.

    %% 1. Settings and shared evaluation budget
    % Preserve uploaded legacy provider-path DP (not a repaired DTOSC2022 variant).
    A = ctx.applicationCount;
    first = zeros(A, 1);
    for a = 1:A
        j = find(ctx.taskApp(ctx.optimTaskIds) == a, 1);
        if isempty(j)
            j = ctx.dimension + 1;
        end
        first(a) = j;
    end
    [~, apps] = sortrows([first ctx.deadline ctx.applicationId], [1 2 3]);
    order = [];
    for a = apps'
        order = [order ctx.optimTaskIds(ctx.taskApp(ctx.optimTaskIds) == a)];
    end
    state = vefc.Evaluator.initial(ctx);
    transitions = 0;
    stages = 0;
    peak = 1;
    for a = apps'
        tasks = order(ctx.taskApp(order) == a);
        front = {struct('state', state, 'utility', 0, 'path', [])};
        for t = tasks
            stages = stages + 1;
            pos = find(order == t, 1);
            remaining = order(pos + 1:end);
            dom = ctx.domain{t};
            dom = dom(ctx.isRsu(dom)' | dom == ctx.localProvider(a));
            next = cell(1, numel(dom));
            for i = 1:numel(front)
                node = front{i};
                for j = 1:numel(dom)
                    p = dom(j);
                    transitions = transitions + 1;
                    q = vefc.Evaluator.candidate(ctx, node.state, t, p);
                    child = vefc.Evaluator.assign(ctx, node.state, t, p, remaining, false);
                    candidate = struct('state', child, 'utility', node.utility + q, 'path', [node.path p]);
                    if better(candidate, next{j}, a, false)
                        next{j} = candidate;
                    end
                end
            end
            front = next;
            peak = max(peak, numel(front));
        end
        chosen = [];
        for i = 1:numel(front)
            if better(front{i}, chosen, a, true)
                chosen = front{i};
            end
        end
        state = chosen.state;
    end
    best = state.assignment(ctx.optimTaskIds)';
    ev = vefc.Evaluator.finish(ctx, state, best);
    history = struct('iteration', 0, 'functionEvaluations', [], 'bestTotalEfficiency', ev.score, 'populationTotalEfficiencies', [], 'diagnostics', struct('dp_applications', A, 'dp_stages', stages, 'dp_transitions', transitions, 'dp_peak_frontier', peak));

    function tf = better(x, y, a, final)
        if isempty(y)
            tf = true;
            return
        end
        kx = key(x, a, final);
        ky = key(y, a, final);
        jx = find(kx ~= ky, 1);
        if ~isempty(jx)
            tf = kx(jx) > ky(jx);
            return
        end
        px = ctx.providerId(x.path);
        py = ctx.providerId(y.path);
        jx = find(px ~= py, 1);
        tf = ~isempty(jx) && px(jx) < py(jx);
    end

    function k = key(node, a, final)
        st = node.state;
        members = st.order(ctx.taskApp(st.order) == a);
        finish = max(st.finish(members));
        energy = vefc.FormulaLibrary.pythonSum(st.energy(members));
        ef = vefc.FormulaLibrary.paperEfficiency(ctx.alpha(a), ctx.beta(a), ctx.referenceTime(a), ctx.localEnergy(a), finish, energy);
        if final
            k = [ef node.utility -finish -energy];
        else
            k = [node.utility ef -finish -energy];
        end
    end

end
