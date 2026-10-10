function [bestSolution, evaluation, history] = gpc(ctx, cfg)
    % Discrete GPC: worker/block movement, Pharaoh selection and restarts.
    % Parameters: greedy=.70, gravity=9.8, ramp angle=14 degrees, friction=[1,10].
    % Mutation is adaptive; service-memory/problem-guidance are disabled here.

    %% 1. Settings and shared evaluation budget
    % Exact uploaded joint benchmark: problem_guidance=false, service_memory=false.
    populationSize = max(2, cfg.populationSize);
    searchIterations = max(0, cfg.tmax - 1);
    rng = optim.PythonRandom(ctx.seed);
    b = optim.EvaluationBudget(ctx, cfg.maxFunctionEvaluations, populationSize);
    %% 2. Initial population
    population = optim.OptimizerCommon.initialPopulation(ctx, populationSize, .7, rng, b, 'gpc');
    [population, populationScores] = optim.OptimizerCommon.evaluatePopulation(population, b);
    [population, populationScores] = optim.OptimizerCommon.sortUnique(population, populationScores);
    population = population(1:populationSize, :);
    populationScores = populationScores(1:populationSize);
    bestSolution = population(1, :);
    score = populationScores(1);
    stagnation = 0;
    accepted = 0;
    abandoned = 0;
    replacements = 0;
    history = record(0, 0, [], 0);
    %% 3. Population search
    for gen = 1:searchIterations
        progress = gen / max(1, searchIterations);
        oldScore = score;
        div = optim.OptimizerCommon.diversity(population);
        mp = max(.03, min(.45, .22 * (1 - progress) + .04 + min(.18, .03 * stagnation) + max(0, .08 - .2 * div)));
        ap = min(.4, .05 + .04 * stagnation);
        cp = bestSolution;
        cs = score;
        exhausted = false;
        movement = [];
        for i = 2:populationSize
            if exhausted
                cp(end + 1, :) = population(i, :);
                cs(end + 1, 1) = populationScores(i);
                continue
            end
            [child, changed] = physical(population(i, :), bestSolution, progress);
            movement(end + 1) = changed;
            child = mutate(child, mp);
            child = escape(child, stagnation, min(.45, .12 + .04 * stagnation));
            [e, ~] = b.evaluate(child);
            if isempty(e)
                exhausted = true;
                cp(end + 1, :) = population(i, :);
                cs(end + 1, 1) = populationScores(i);
                continue
            end
            if e.score >= populationScores(i)
                accepted = accepted + 1;
                cp(end + 1, :) = child;
                cs(end + 1, 1) = e.score;
            elseif rng.random() < ap
                child = restart();
                [e, ~] = b.evaluate(child);
                if isempty(e)
                    exhausted = true;
                    cp(end + 1, :) = population(i, :);
                    cs(end + 1, 1) = populationScores(i);
                else
                    abandoned = abandoned + 1;
                    replacements = replacements + 1;
                    cp(end + 1, :) = child;
                    cs(end + 1, 1) = e.score;
                end
            else
                cp(end + 1, :) = population(i, :);
                cs(end + 1, 1) = populationScores(i);
            end
        end
        trials = max(1, optim.PythonRandom.roundEven(populationSize * (.2 + .1 * min(1, stagnation / 5))));
        completed = 0;
        if ~exhausted
            for i = 1:trials
                child = local(bestSolution);
                [e, ~] = b.evaluate(child);
                if isempty(e)
                    exhausted = true;
                    break
                end
                cp(end + 1, :) = child;
                cs(end + 1, 1) = e.score;
                completed = completed + 1;
            end
        end
        if exhausted
            n = populationSize;
        else
            n = max(1, min(populationSize, ceil(populationSize * .2)));
        end
        [pool, ss] = optim.OptimizerCommon.sortUnique([cp; population(1:n, :)], [cs; populationScores(1:n)]);
        if ~exhausted && stagnation >= 5
            n = max(1, populationSize - max(1, ceil(populationSize * .15)));
            pool = pool(1:min(n, size(pool, 1)), :);
            ss = ss(1:min(n, numel(ss)));
        end
        attempts = 0;
        while size(pool, 1) < populationSize && attempts < populationSize * 50
            attempts = attempts + 1;
            child = restart();
            if any(all(bsxfun(@eq, pool, child), 2))
                continue
            end
            [e, ~] = b.evaluate(child);
            if isempty(e)
                exhausted = true;
                break
            end
            pool(end + 1, :) = child;
            ss(end + 1, 1) = e.score;
            replacements = replacements + 1;
        end
        if size(pool, 1) < populationSize && exhausted
            [pool, ss] = optim.OptimizerCommon.sortUnique([pool; population], [ss; populationScores]);
        end
        assert(size(pool, 1) >= populationSize);
        [population, populationScores] = optim.OptimizerCommon.sortUnique(pool, ss);
        population = population(1:populationSize, :);
        populationScores = populationScores(1:populationSize);
        if populationScores(1) > score
            bestSolution = population(1, :);
            score = populationScores(1);
        end
        if score > oldScore + 1e-12
            stagnation = 0;
        else
            stagnation = stagnation + 1;
        end
        history(end + 1) = record(gen, mp, movement, completed);
        if exhausted
            break
        end
    end
    %% 4. Final schedule and objective
    evaluation = vefc.Evaluator.evaluate(ctx, bestSolution);

    function [x, changed] = physical(x, leader, progress)
        friction = rng.uniform(1, 10);
        v = rng.random();
        theta = 14 * pi / 180;
        sn = max(1e-12, sin(theta));
        co = max(0, cos(theta));
        wd = v^2 / (2 * 9.8 * sn);
        sd = v^2 / (2 * 9.8 * (sn + friction * co));
        physicalFactor = .5 * (wd / (1 / (2 * 9.8 * sn))) + .5 * (sd / max(1e-12, 1 / (2 * 9.8 * (sn + co))));
        n = max(1, min(ctx.dimension, ceil(sqrt(ctx.dimension) * .5 * (.5 + physicalFactor))));
        diff = rng.shuffle(find(x ~= leader));
        remaining = rng.shuffle(find(x == leader));
        selected = [diff remaining];
        selected = selected(1:n);
        changed = 0;
        for g = selected
            dom = ctx.domain{ctx.optimTaskIds(g)};
            alt = dom(dom ~= x(g));
            if isempty(alt)
                continue
            end
            if ismember(leader(g), alt) && rng.random() < .25 + .6 * progress
                x(g) = leader(g);
            else
                exp = alt(alt ~= leader(g));
                if isempty(exp)
                    exp = alt;
                end
                x(g) = rng.choice(exp);
            end
            changed = changed + 1;
        end
    end

    function x = mutate(x, prob)
        if rng.random() > prob
            return
        end
        mutable = mutableGenes(x);
        if isempty(mutable)
            return
        end
        n = max(1, ceil(.5 * sqrt(numel(mutable))));
        chosen = optim.OptimizerCommon.weighted(mutable, ones(size(mutable)) * .675, n, rng);
        for g = chosen
            dom = ctx.domain{ctx.optimTaskIds(g)};
            x(g) = rng.choice(dom(dom ~= x(g)));
        end
    end

    function x = escape(x, stag, prob)
        if stag < 5
            return
        end
        if isempty(x) || rng.random() > prob
            return
        end
        n = max(1, min(ctx.dimension, ceil(sqrt(ctx.dimension) * min(2, 1 + .15 * max(0, stag - 5)))));
        for g = rng.sample(1:ctx.dimension, n)
            dom = ctx.domain{ctx.optimTaskIds(g)};
            alt = dom(dom ~= x(g));
            if ~isempty(alt)
                x(g) = rng.choice(alt);
            end
        end
    end

    function x = local(x)
        mutable = mutableGenes(x);
        if isempty(mutable)
            return
        end
        g = rng.choice(mutable);
        dom = ctx.domain{ctx.optimTaskIds(g)};
        x(g) = rng.choice(dom(dom ~= x(g)));
    end

    function x = restart()
        x = escape(bestSolution, max(5, stagnation), 1);
        x = mutate(x, 1);
        if isequal(x, bestSolution)
            x = local(x);
        end
    end

    function v = mutableGenes(x)
        v = [];
        for g = 1:ctx.dimension
            if any(ctx.domain{ctx.optimTaskIds(g)} ~= x(g))
                v(end + 1) = g;
            end
        end
    end

    function h = record(i, mp, movement, trials)
        h = optim.OptimizerCommon.historyRow(i, b, score, populationScores);
        h.diagnostics = struct('current_pharaoh_score', populationScores(1), 'accepted_moves', accepted, 'abandoned_workers', abandoned, 'generated_replacements', replacements, 'stagnation_count', stagnation, 'mutation_probability', mp, 'mean_substituted_tasks', vefc.FormulaLibrary.sumOrdered(movement) / max(1, numel(movement)), 'local_refinement_trials', trials, 'population_unique_count', size(population, 1), 'population_mean_hamming', optim.OptimizerCommon.diversity(population));
    end

end
