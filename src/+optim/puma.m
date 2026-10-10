function [bestSolution, evaluation, history] = puma(ctx, cfg)
    % Discrete Puma: exploration, exploitation and adaptive phase selection.
    % Parameters: greedy=.30, initial PCR=.20, Qop=.67, PF=[.5,.5,.3],
    % idle decay=.99 and phase memory length=3. Both phases run initially.

    %% 1. Settings and shared evaluation budget
    populationSize = max(2, cfg.populationSize);
    searchIterations = max(0, cfg.tmax - 1);
    rng = optim.PythonRandom(ctx.seed);
    b = optim.EvaluationBudget(ctx, cfg.maxFunctionEvaluations, populationSize);
    %% 2. Initial population
    population = optim.OptimizerCommon.initialPopulation(ctx, populationSize, .3, rng, b, 'puma');
    [population, populationScores] = optim.OptimizerCommon.evaluatePopulation(population, b);
    [population, populationScores] = optim.OptimizerCommon.sortUnique(population, populationScores);
    assert(size(population, 1) >= populationSize);
    population = population(1:populationSize, :);
    populationScores = populationScores(1:populationSize);
    bestSolution = population(1, :);
    score = populationScores(1);
    initial = b.Count;
    pcr = .2;
    gains = {[], []};
    efficiencies = {[], []};
    idle = [0 0];
    history = record(0, 'initialization', 0, 0, []);
    %% 3. Population search
    for i = 1:searchIterations
        if b.exhausted()
            break
        end
        generated = 0;
        accepted = 0;
        phaseScore = phaseScores();
        if i <= 3
            remaining = 2 * populationSize;
            if isfinite(b.Maximum)
                remaining = b.remaining();
            end
            et = min(populationSize, floor((remaining + 1) / 2));
            xt = min(populationSize, max(0, remaining - et));
            [ep, es, paid, kept] = runPhase(1, population, populationScores, et, i);
            generated = generated + paid;
            accepted = accepted + kept;
            xp = population;
            xs = populationScores;
            if xt > 0
                [xp, xs, paid, kept] = runPhase(2, population, populationScores, xt, i);
                generated = generated + paid;
                accepted = accepted + kept;
                idle = [0 0];
            end
            [population, populationScores] = optim.OptimizerCommon.sortUnique([population; ep; xp], [populationScores; es; xs]);
            population = population(1:populationSize, :);
            populationScores = populationScores(1:populationSize);
            selected = 'both';
        else
            phaseScore = phaseScores();
            if abs(phaseScore(1) - phaseScore(2)) <= 1e-15
                if idle(1) >= idle(2)
                    which = 1;
                else
                    which = 2;
                end
            else
                [~, which] = max(phaseScore);
            end
            target = populationSize;
            if isfinite(b.Maximum)
                target = min(populationSize, b.remaining());
            end
            [population, populationScores, paid, kept] = runPhase(which, population, populationScores, target, i);
            generated = generated + paid;
            accepted = accepted + kept;
            names = {'exploration', 'exploitation'};
            selected = names{which};
        end
        [population, populationScores] = optim.OptimizerCommon.sortUnique(population, populationScores);
        population = population(1:populationSize, :);
        populationScores = populationScores(1:populationSize);
        if populationScores(1) > score + 1e-12
            bestSolution = population(1, :);
            score = populationScores(1);
        end
        if populationScores(1) >= score - 1e-12
            bestSolution = population(1, :);
            score = populationScores(1);
        end
        history(end + 1) = record(i, selected, generated, accepted, phaseScores());
    end
    %% 4. Final schedule and objective
    evaluation = vefc.Evaluator.evaluate(ctx, bestSolution);

    function v = progress(i)
        v = optim.OptimizerCommon.progress(b.Count, initial, b.Maximum, i, searchIterations);
    end

    function v = phaseScores()
        phaseGains = cellfun(@(x)vefc.FormulaLibrary.pythonSum(x), gains);
        phaseEfficiency = cellfun(@(x)vefc.FormulaLibrary.pythonSum(x), efficiencies);
        gt = vefc.FormulaLibrary.pythonSum(phaseGains);
        et = vefc.FormulaLibrary.pythonSum(phaseEfficiency);
        v = zeros(1, 2);
        for k = 1:2
            g = 0;
            e = 0;
            if gt > 0
                g = phaseGains(k) / gt;
            end
            if et > 0
                e = phaseEfficiency(k) / et;
            end
            v(k) = .5 * g + .5 * e + .3 * (1 - .99^max(0, idle(k)));
        end
    end

    function [rows, ss, paid, kept] = runPhase(which, rows, ss, target, i)
        before = b.Count;
        old = max(ss);
        kept = 0;
        attempts = 0;
        cursor = 0;
        while b.Count - before < target && attempts < max(50, target * 30)
            if b.exhausted()
                break
            end
            attempts = attempts + 1;
            ix = mod(cursor, size(rows, 1)) + 1;
            cursor = cursor + 1;
            parent = rows(ix, :);
            ps = ss(ix);
            if which == 1
                child = explore(parent, rows);
            else
                child = exploit(parent, rows, progress(i));
            end
            if any(all(bsxfun(@eq, rows, child), 2))
                continue
            end
            [e, ~] = b.evaluate(child);
            if isempty(e)
                break
            end
            if e.score > ps + 1e-12
                rows(ix, :) = child;
                ss(ix) = e.score;
                kept = kept + 1;
            elseif which == 1
                pcr = min(.95, pcr + .8 / max(1, populationSize));
            end
        end
        [rows, ss] = optim.OptimizerCommon.sortUnique(rows, ss);
        gain = max(0, max(ss) - old);
        paid = max(0, b.Count - before);
        gains{which} = [gains{which} gain];
        efficiencies{which} = [efficiencies{which} gain / max(1, paid)];
        gains{which} = gains{which}(max(1, end - 2):end);
        efficiencies{which} = efficiencies{which}(max(1, end - 2):end);
        idle(which) = 0;
        idle(3 - which) = idle(3 - which) + 1;
    end

    function x = explore(parent, rows)
        D = ctx.dimension;
        x = parent;
        n = max(1, min(D, optim.PythonRandom.roundEven(max(1, pcr * sqrt(max(1, D)) * 2))));
        selected = optim.OptimizerCommon.weighted(1:D, ones(1, D), n, rng);
        peers = zeros(6, D);
        for j = 1:6
            peers(j, :) = rows(rng.choice(1:size(rows, 1)), :);
        end
        globalMove = rng.random() < .5;
        for g = selected
            dom = ctx.domain{ctx.optimTaskIds(g)};
            cur = parent(g);
            if globalMove
                proposals = dom(dom ~= cur);
            else
                proposals = [];
                for j = 1:2:5
                    pos = peers(j, g);
                    neg = peers(j + 1, g);
                    if pos ~= neg && ismember(pos, dom) && pos ~= cur
                        proposals(end + 1) = pos;
                    end
                end
                if isempty(proposals)
                    proposals = dom(dom ~= cur);
                end
            end
            if ~isempty(proposals)
                x(g) = rng.choice(proposals);
            end
        end
    end

    function x = exploit(parent, rows, prog)
        D = ctx.dimension;
        x = parent;
        n = max(1, ceil(1 + sqrt(max(1, D)) * (1 - prog)^2));
        selected = optim.OptimizerCommon.weighted(1:D, ones(1, D), min(D, n), rng);
        mode = rng.random();
        for g = selected
            dom = ctx.domain{ctx.optimTaskIds(g)};
            leader = bestSolution(g);
            peer = rows(rng.choice(1:size(rows, 1)), g);
            counts = arrayfun(@(p)sum(rows(:, g) == p), dom);
            mx = max(counts);
            ties = dom(counts == mx);
            [~, ix] = max(ctx.providerId(ties));
            consensus = ties(ix);
            if mode < .67
                proposals = [leader leader peer];
            elseif mode < .67 + (1 - .67) * .5
                proposals = [leader consensus peer];
            else
                proposals = [dom(dom ~= leader) leader consensus];
            end
            proposals = proposals(ismember(proposals, dom));
            if ~isempty(proposals)
                x(g) = rng.choice(proposals);
            end
        end
    end

    function h = record(i, phase, generated, accepted, scores)
        h = optim.OptimizerCommon.historyRow(i, b, score, populationScores);
        h.diagnostics = struct('population_unique_count', size(population, 1), 'population_mean_hamming', optim.OptimizerCommon.diversity(population), 'selected_phase', phase, 'phase_scores', scores, 'pcr', pcr, 'generated_trials', generated, 'accepted_candidates', accepted, 'search_progress', progress(i));
    end

end
