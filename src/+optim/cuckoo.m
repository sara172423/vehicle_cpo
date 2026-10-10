function [bestSolution, evaluation, history] = cuckoo(ctx, cfg)
    % Cuckoo/DCSGA: greedy nests, Levy moves, random walks and abandonment.
    % Parameters: population/iterations/budget in cfg; Levy lambda and initial
    % discard probability come from ctx.params (the dataset parameter table).

    %% 1. Settings and shared evaluation budget
    % Direct port of shared Algorithm 2 / Procedure 3 generation kernel.
    populationSize = cfg.populationSize;
    assert(populationSize >= 2);
    rng = optim.PythonRandom(ctx.seed);
    budget = optim.EvaluationBudget(ctx, cfg.maxFunctionEvaluations, populationSize);
    %% 2. Initial population
    [population, ~] = optim.OptimizerCommon.greedyPopulation(ctx, populationSize, rng, budget);
    [population, scores] = optim.OptimizerCommon.evaluatePopulation(population, budget);
    bestSolution = population(1, :);
    history = optim.OptimizerCommon.historyRow(0, budget, scores(1), scores);
    discardProbability = ctx.params.p_discard_init;
    %% 3. Population search
    for t = 1:max(1, cfg.tmax) - 1
        previous = population;
        previousScores = scores;
        new = bestSolution;
        for i = 2:populationSize
            new(end + 1, :) = mutate(population(i, :), bestSolution, ctx, rng);
        end
        source = new(rng.randbelow(size(new, 1)) + 1, :);
        walk = zeros(populationSize, ctx.dimension);
        for i = 1:populationSize
            walk(i, :) = mutate(source, [], ctx, rng);
        end
        [p, s] = optim.OptimizerCommon.evaluatePopulation([new; walk], budget);
        if isfinite(budget.Maximum) && budget.exhausted()
            if size(p, 1) < populationSize
                p = [p; previous];
                s = [s; previousScores];
            end
            [s, ix] = sort(s, 'descend');
            p = p(ix, :);
            population = p(1:populationSize, :);
            scores = s(1:populationSize);
            bestSolution = population(1, :);
            history(end + 1) = optim.OptimizerCommon.historyRow(t, budget, scores(1), scores);
            break
        end
        discardProbability = min(1, 2 * discardProbability / max(t, 1));
        if rng.random() <= discardProbability
            worst = p(end, :);
            walk = zeros(populationSize, ctx.dimension);
            for i = 1:populationSize
                walk(i, :) = mutate(worst, [], ctx, rng);
            end
            before = p;
            beforeScores = s;
            [p, s] = optim.OptimizerCommon.evaluatePopulation([p(1:end - 1, :); walk], budget);
            if isfinite(budget.Maximum) && budget.exhausted()
                if size(p, 1) < populationSize
                    p = [p; before];
                    s = [s; beforeScores];
                end
                [s, ix] = sort(s, 'descend');
                p = p(ix, :);
                population = p(1:populationSize, :);
                scores = s(1:populationSize);
                bestSolution = population(1, :);
                history(end + 1) = optim.OptimizerCommon.historyRow(t, budget, scores(1), scores);
                break
            end
        end
        population = p(1:populationSize, :);
        scores = s(1:populationSize);
        bestSolution = population(1, :);
        history(end + 1) = optim.OptimizerCommon.historyRow(t, budget, scores(1), scores);
    end
    %% 4. Final schedule and objective
    evaluation = vefc.Evaluator.evaluate(ctx, bestSolution);
end

function x = mutate(source, bestSolution, ctx, rng)
    x = source;
    D = ctx.dimension;
    H = D;
    if ~isempty(bestSolution)
        H = sum(source ~= bestSolution);
    end
    L = 0;
    if H > 0
        L = max(0, min(2 * D, optim.PythonRandom.roundEven(2 * H * vefc.FormulaLibrary.levyNormalized(ctx.params.levy_lambda, rng))));
    end
    q = floor(L / 2);
    rem = mod(L, 2);
    transformed = [];
    if ~isempty(bestSolution) && H ~= D
        diff = find(source ~= bestSolution);
        if q > 0 && ~isempty(diff)
            transformed = rng.sample(diff, min(q, numel(diff)));
            x(transformed) = bestSolution(transformed);
        end
        if rem
            remaining = diff(~ismember(diff, transformed) & x(diff) ~= bestSolution(diff));
            if ~isempty(remaining)
                g = rng.choice(remaining);
                x(g) = sameMode(ctx, g, x(g), mode(ctx, g, bestSolution(g)), rng);
            end
        end
    else
        if q
            transformed = rng.sample(1:D, min(q, D));
            for g = transformed
                x(g) = rng.choice(ctx.domain{ctx.optimTaskIds(g)});
            end
        end
        if rem
            remaining = setdiff(1:D, transformed, 'stable');
            if ~isempty(remaining)
                g = rng.choice(remaining);
                x(g) = sameMode(ctx, g, x(g), mode(ctx, g, x(g)), rng);
            end
        end
    end
end

function m = mode(ctx, g, p)
    if p == ctx.localProvider(ctx.taskApp(ctx.optimTaskIds(g)))
        m = 1;
    elseif ctx.isRsu(p)
        m = 3;
    else
        m = 2;
    end
end

function p = sameMode(ctx, g, current, target, rng)
    dom = ctx.domain{ctx.optimTaskIds(g)};
    m = arrayfun(@(p)mode(ctx, g, p), dom);
    c = dom(dom ~= current & m == target);
    if isempty(c)
        c = dom(m == target);
    end
    if isempty(c)
        c = dom(dom ~= current);
    end
    p = current;
    if ~isempty(c)
        p = rng.choice(c);
    end
end
