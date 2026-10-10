function [bestSolution, evaluation, history] = gwo(ctx, cfg)
    % Discrete GWO: alpha/beta/delta leaders, adaptive a and local/escape moves.
    % Parameters: greedy=.90, local fraction=.20, escape fraction=.15,
    % stagnation threshold=5. Pheromone/rank/cache proposal guidance is disabled.

    %% 1. Settings and shared evaluation budget
    % Uploaded joint GWO defaults: pheromone/rank/cache proposal guidance disabled.
    populationSize = max(3, cfg.populationSize);
    searchIterations = max(0, cfg.tmax - 1);
    rng = optim.PythonRandom(ctx.seed);
    b = optim.EvaluationBudget(ctx, cfg.maxFunctionEvaluations, populationSize);
    %% 2. Initial population
    population = optim.OptimizerCommon.initialPopulation(ctx, populationSize, .9, rng, b, 'gwo');
    [population, populationScores] = optim.OptimizerCommon.evaluatePopulation(population, b);
    [population, populationScores] = optim.OptimizerCommon.sortUnique(population, populationScores);
    assert(size(population, 1) >= populationSize);
    population = population(1:populationSize, :);
    populationScores = populationScores(1:populationSize);
    bestSolution = population(1, :);
    score = populationScores(1);
    stagnation = 0;
    history = record(0, b, score, populationScores, population);
    %% 3. Population search
    for i = 1:searchIterations
        a = max(0, min(2, 2 * (1 - (i - 1) / max(1, searchIterations)) + .35 * max(0, min(1, .35 - optim.OptimizerCommon.diversity(population, false))) + .25 * min(1, max(0, stagnation) / 10)));
        leaders = population(1:3, :);
        trigger = stagnation >= 5;
        esc = 0;
        if trigger
            esc = max(1, optim.PythonRandom.roundEven(populationSize * .15));
        end
        loc = max(1, optim.PythonRandom.roundEven(populationSize * .2));
        ord = max(0, populationSize - esc - loc);
        children = zeros(0, ctx.dimension);
        if ord > 0
            sources = rng.shuffle(1:populationSize);
            for j = 1:ord
                children(end + 1, :) = move(population(sources(mod(j - 1, populationSize) + 1), :), leaders, a, ctx, rng);
            end
        end
        children = [children; localChildren(leaders, a, loc, ctx, rng)];
        for j = 1:esc
            x = population(rng.choice(1:populationSize), :);
            n = max(1, min(ctx.dimension, ceil(sqrt(ctx.dimension) * (1 + phase(a)))));
            for g = rng.sample(1:ctx.dimension, n)
                dom = ctx.domain{ctx.optimTaskIds(g)};
                alt = dom(dom ~= x(g));
                if ~isempty(alt)
                    x(g) = rng.choice(alt);
                end
            end
            children(end + 1, :) = x;
        end
        attempts = 0;
        while size(children, 1) < populationSize && attempts < populationSize * 4
            attempts = attempts + 1;
            x = population(rng.choice(1:populationSize), :);
            rng.shuffle(1);
            children(end + 1, :) = move(x, leaders, a, ctx, rng);
        end
        assert(size(children, 1) >= populationSize);
        [cp, cs] = optim.OptimizerCommon.evaluatePopulation(children(1:populationSize, :), b);
        [population, populationScores] = optim.OptimizerCommon.sortUnique([population; cp], [populationScores; cs]);
        population = population(1:populationSize, :);
        populationScores = populationScores(1:populationSize);
        old = score;
        bestSolution = population(1, :);
        score = populationScores(1);
        if score > old + .0001
            stagnation = 0;
        elseif trigger
            stagnation = 0;
        else
            stagnation = stagnation + 1;
        end
        history(end + 1) = record(i, b, score, populationScores, population);
        if b.exhausted()
            break
        end
    end
    %% 4. Final schedule and objective
    evaluation = vefc.Evaluator.evaluate(ctx, bestSolution);
end

function ph = phase(a)
    ph = max(0, min(1, a / 2));
end

function x = move(x, leaders, a, ctx, rng)
    D = ctx.dimension;
    md = (sum(x ~= leaders(1, :)) + sum(x ~= leaders(2, :)) + sum(x ~= leaders(3, :))) / 3;
    ph = phase(a);
    n = ceil(max(1, md) * (.15 + .85 * ph));
    trust = max(1, ceil(sqrt(D) * (.5 + ph)));
    n = min(n, trust);
    if ph > .5 && rng.random() < .1
        n = n + 1;
    end
    n = max(1, min(D, n));
    w = zeros(1, D);
    for g = 1:D
        l = leaders(:, g);
        w(g) = 1 + 1.2 * sum(l ~= x(g)) + .8 * max(0, numel(unique(l)) - 1);
    end
    selected = optim.OptimizerCommon.weighted(1:D, w, n, rng);
    for g = 1:D
        if ismember(g, selected)
            x(g) = provider(g, x(g), leaders, a, ctx, rng);
        end
    end
end

function p = provider(g, current, leaders, a, ctx, rng)
    dom = ctx.domain{ctx.optimTaskIds(g)};
    l = leaders(:, g)';
    initial = [current l];
    initial = initial(ismember(initial, dom));
    initial = unique(initial, 'stable');
    alt = dom(~ismember(dom, initial));
    alt = rng.shuffle(alt);
    n = 2 + optim.PythonRandom.roundEven(2 * phase(a));
    vals = [initial alt(1:min(n, numel(alt)))];
    ids = optim.PythonRandom.intSetOrder(ctx.providerId(vals)');
    [~, cand] = ismember(ids, ctx.providerId);
    cand = cand(:)';
    ph = phase(a);
    w = zeros(size(cand));
    for j = 1:numel(cand)
        v = cand(j);
        inertia = 0;
        if v == current
            inertia = .12 + .22 * (1 - ph);
        end
        novelty = 0;
        if ~ismember(v, l)
            novelty = .18 * ph;
        end
        w(j) = .05 + inertia + novelty;
    end
    base = [1 + 1.2 * (1 - ph), .9 - .3 * (1 - ph), .8 - .35 * (1 - ph)];
    for j = 1:3
        ix = find(cand == l(j), 1);
        if isempty(ix)
            continue
        end
        u = rng.random();
        v = rng.random();
        A = 2 * a * u - a;
        C = 2 * v;
        follow = max(0, 1 - min(abs(A), 2) / 2);
        scale = .75 + .25 * C;
        w(ix) = w(ix) + base(j) * follow * scale;
    end
    p = optim.OptimizerCommon.weighted(cand, w, 1, rng);
end

function children = localChildren(leaders, a, n, ctx, rng)
    alpha = leaders(1, :);
    mutable = [];
    weights = [];
    for g = 1:ctx.dimension
        dom = ctx.domain{ctx.optimTaskIds(g)};
        if any(dom ~= alpha(g))
            mutable(end + 1) = g;
            weights(end + 1) = .3 + .55 * (1 - .5) + .45 * (double(leaders(2, g) ~= alpha(g)) + double(leaders(3, g) ~= alpha(g)));
        end
    end
    children = zeros(0, ctx.dimension);
    if isempty(mutable)
        return
    end
    for j = 1:n
        x = alpha;
        g = optim.OptimizerCommon.weighted(mutable, weights, 1, rng);
        dom = ctx.domain{ctx.optimTaskIds(g)};
        alt = dom(dom ~= x(g));
        p = x(g);
        if rng.random() < .15 + .2 * phase(a)
            p = rng.choice(alt);
        else
            for k = 1:3
                p = provider(g, x(g), leaders, max(.1, min(.75, a)), ctx, rng);
                if p ~= x(g)
                    break
                end
            end
        end
        if p == x(g)
            p = rng.choice(alt);
        end
        x(g) = p;
        children(end + 1, :) = x;
    end
end

function h = record(i, b, score, populationScores, population)
    h = optim.OptimizerCommon.historyRow(i, b, score, populationScores);
    h.diagnostics = struct('population_diversity_mean', optim.OptimizerCommon.diversity(population, false));
end
