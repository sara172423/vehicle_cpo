function [bestSolution, evaluation, history] = cpo(ctx, cfg)

    %% 1. Settings and shared evaluation budget
    % CPO equations + one-hot projection; parent-wise acceptance per Algorithm 1.
    % Four original CPO equations + categorical one-hot projection.
    % Shared time-varying defense selection uses the search NFE clock.
    variant = 'cpo';
    guide = struct('critical', false, 'cache', false, 'memory', false, 'model', false);
    offsets = articleOffsets(ctx);
    populationSize = cfg.populationSize;
    searchIterations = max(0, cfg.tmax - 1);
    rng = optim.PythonRandom(ctx.seed);
    budget = optim.EvaluationBudget(ctx, cfg.maxFunctionEvaluations, populationSize);
    %% 2. Initial population: greedy + balanced provider coverage
    population = optim.OptimizerCommon.initialPopulation(ctx, populationSize, .75, rng, budget, 'cpo');
    [population, scores] = optim.OptimizerCommon.evaluatePopulation(population, budget);
    [population, scores] = optim.OptimizerCommon.sortUnique(population, scores);
    assert(size(population, 1) >= populationSize);
    population = population(1:populationSize, :);
    scores = scores(1:populationSize);
    initialEvaluations = budget.Count;
    bestSolution = population(1, :);
    bestScore = scores(1);
    memory = [];
    stagnation = 0;
    history = record(0, populationSize, 0, 0, 0, zeros(1, 5), 0, false);
    %% 3. Search: cyclic active population and four defenses
    for iteration = 1:searchIterations
        if budget.exhausted()
            break
        end
        progress = optim.OptimizerCommon.progress(budget.Count, initialEvaluations, budget.Maximum, iteration - 1, searchIterations);
        minimum = max(2, min(populationSize, optim.PythonRandom.roundEven(populationSize * .8)));
        phase = mod(progress * 2, 1);
        activeCount = max(minimum, min(populationSize, ceil(populationSize - (populationSize - minimum) * phase)));
        current = population;
        currentScores = scores;
        articleX = articleEncodePopulation(current, ctx, offsets);
        bestKeys = articleEncode(bestSolution, ctx, offsets);
        indices = 1:min(activeCount, size(population, 1));
        if populationSize > activeCount
            tail = rng.shuffle(activeCount + 1:populationSize);
            n = max(1, floor(activeCount / 5));
            indices = [indices(1:end - n) tail(1:min(n, numel(tail)))];
        end
        accepted = 0;
        previous = bestScore;
        attempts = 0;
        generated = 0;
        counts = zeros(1, 5);
        target = min(activeCount, budget.remaining());
        % Custom linear defense schedule follows SEARCH NFE (initialization excluded).
        % All other VEFC search operators keep their existing progress schedule.
        before = budget.Count;
        maxAttempts = max(activeCount * 10, target * 12);
        cursor = 0;
        while budget.Count - before < target && attempts < maxAttempts
            attempts = attempts + 1;
            ix = indices(mod(cursor, numel(indices)) + 1);
            cursor = cursor + 1;
            parent = current(ix, :);
            parentScore = currentScores(ix);
            % Update linear defense probabilities before each defense choice using actual NFE.
            defenseProgress = optim.OptimizerCommon.progress( ...
                budget.Count, initialEvaluations, budget.Maximum, ...
                iteration - 1, searchIterations);
            % No stagnation override, strategy-memory bias, or forced quotas.
            strategy = optim.cpoDefenseSchedule(defenseProgress, rng);
            counts(strategy) = counts(strategy) + 1;
            % The defense equations are applied before discrete projection.
            % No additional full fitness evaluations are performed here.
            child = articleCandidate(strategy, ix, current, currentScores, ...
                articleX, bestKeys, bestSolution, ctx, offsets, rng, budget.Cache, ...
                defenseProgress);
            [childEv, isNew] = budget.evaluate(child);
            if isempty(childEv)
                break
            end
            if ~isNew
                continue
            end
            generated = generated + 1;
            score = childEv.score;
            % Parent-wise GREEDY replacement, immediately after evaluation.
            % A child may replace ONLY the parent at index ix, never a weaker stranger.
            [current, currentScores, didAccept] = optim.cpoParentAccept( ...
                current, currentScores, ix, child, score);
            if didAccept
                accepted = accepted + 1;
                articleX(ix, :) = articleEncode(child, ctx, offsets);
                if score > bestScore + 1e-12
                    bestSolution = child;
                    bestScore = score;
                    bestKeys = articleEncode(bestSolution, ctx, offsets);
                end
            end
        end
        % Sort ONLY the surviving parent slots for the next generation.
        % No merging/truncation of parent+child candidates is performed.
        [scores, order] = sort(currentScores, 'descend');
        population = current(order, :);
        assert(size(population, 1) == populationSize);
        if bestScore > previous + 1e-12
            stagnation = 0;
        else
            stagnation = stagnation + 1;
        end
        progress = optim.OptimizerCommon.progress(budget.Count, initialEvaluations, budget.Maximum, iteration, searchIterations);
        history(end + 1) = record(iteration, activeCount, generated, accepted, attempts, counts, progress, bestScore > previous + 1e-12);
        if generated == 0
            break
        end
    end
    %% 4. Materialize the final schedule (not a new paid search evaluation)
    evaluation = vefc.Evaluator.evaluate(ctx, bestSolution);

    function h = record(iter, activeCount, generated, accepted, attempts, counts, progress, improved)
        h = optim.OptimizerCommon.historyRow(iter, budget, bestScore, scores);
        credit = zeros(1, 4);
        acceptedBy = zeros(1, 4);
        taskEntries = 0;
        serviceEntries = 0;
        if ~isempty(memory)
            credit = memory.strategy;
            acceptedBy = memory.accepted;
            taskEntries = nnz(memory.taskProvider);
            serviceEntries = nnz(memory.serviceProvider);
        end
        algorithmDiagnostics = struct('active_population_size', activeCount, 'generated_trials', generated, 'unique_trial_count', generated, 'accepted_candidates', accepted, 'candidate_attempts', attempts, 'duplicate_trial_count', max(0, attempts - generated), 'stagnation_generations', stagnation, 'search_progress', progress, 'best_improved', improved, 'cpo_variant', variant, 'criticality_guidance', guide.critical, 'cache_coupling', guide.cache, 'success_memory', guide.memory, 'model_guidance', guide.model, 'defense_trials', counts, 'cpo_strategy_credit', credit, 'cpo_accepted_by_strategy', acceptedBy, 'cpo_task_provider_memory_entries', taskEntries, 'cpo_service_provider_memory_entries', serviceEntries, 'population_unique_count', size(population, 1), 'population_mean_hamming', optim.OptimizerCommon.diversity(population));
        % Preserve budget NFE diagnostics alongside original optimizer diagnostics.
        extraNames = fieldnames(algorithmDiagnostics);
        for diagnosticIndex = 1:numel(extraNames)
            keyName = extraNames{diagnosticIndex};
            h.diagnostics.(keyName) = algorithmDiagnostics.(keyName);
        end
    end

end

%% Categorical embedding: one one-hot block for each VEFC task.
% This is a VEFC adaptation, not a formula from Abdel-Basset et al.
function offsets = articleOffsets(ctx)
    offsets = zeros(1, ctx.dimension + 1);
    for g = 1:ctx.dimension
        offsets(g+1) = offsets(g) + numel(ctx.domain{ctx.optimTaskIds(g)});
    end
end

function keys = articleEncode(plan, ctx, offsets)
    keys = zeros(1, offsets(end));
    for g = 1:ctx.dimension
        dom = ctx.domain{ctx.optimTaskIds(g)};
        j = find(dom == plan(g), 1);
        assert(~isempty(j), 'CPO article: provider outside task domain');
        keys(offsets(g)+j) = 1;
    end
end

function X = articleEncodePopulation(population, ctx, offsets)
    X = zeros(size(population, 1), offsets(end));
    for i = 1:size(population, 1)
        X(i, :) = articleEncode(population(i, :), ctx, offsets);
    end
end

function child = articleCandidate(which, parentIndex, population, scores, X, best, bestPlan, ctx, offsets, rng, cache, progress)
    % Abdel-Basset et al., Knowledge-Based Systems 284 (2024) 111257.
    % Equations (4),(5),(6),(7)-(10),(11),(13) are applied in one-hot space.
    % The article is continuous; the subsequent categorical projection is
    % an explicitly added, problem-specific discretization of the trial.
    N = size(X, 1);
    K = size(X, 2);
    x = X(parentIndex, :);
    choose = @() rng.randbelow(N) + 1;

    if which == 1  % Sight: Eqs. (4)-(5)
        j = choose();
        y = (x + X(j, :)) / 2;
        trial = x + rng.gauss(0, 1) .* abs(2 * rng.random() * best - y);

    elseif which == 2  % Sound: Eqs. (5)-(6)
        u = double(articleRandomVector(rng, K) > rng.random());
        j = choose(); r1 = choose(); r2 = choose();
        y = (x + X(j, :)) / 2;
        trial = (1 - u) .* x + u .* (y + rng.random() * (X(r1, :) - X(r2, :)));

    elseif which == 3 || which == 4  % Odor or physical attack
        delta = 2 * double(articleRandomVector(rng, K) <= .5) - 1; % Eq. (8)
        % NFE is the effective time horizon: the search stops at its NFE
        % budget long before cfg.tmax in the VEFC benchmark.
        time = min(1, max(0, progress));
        gamma = 2 * rng.random() * (1 - time)^time;                % Eq. (9), NFE clock
        % Original CPO uses a minimization objective; VEFC maximizes Score.
        % f=-Score reverses the ordering without recomputing fitness.
        f = -double(scores(:));
        denominator = sum(f);
        assert(isfinite(denominator) && ...
            abs(denominator) > 1e-12 * max(1, sum(abs(f))), ...
            'CPO paper odor coefficient undefined for near-zero fitness sum');
        odor = exp(f(parentIndex) / (denominator + eps));           % Eq. (10)
        assert(isfinite(odor), 'CPO paper odor coefficient overflow');

        if which == 3 % Odor: Eq. (7)
            u = double(articleRandomVector(rng, K) > rng.random());
            r1 = choose(); r2 = choose(); r3 = choose();
            trial = (1 - u) .* x + u .* (X(r1, :) + odor * ...
                (X(r2, :) - X(r3, :)) - rng.random() * delta * gamma * odor);
        else % Physical attack: Eqs. (11),(13)
            j = choose();
            force = articleRandomVector(rng, K) .* (odor * (X(j, :) - x));
            tau4 = rng.random(); tau5 = rng.random();
            alpha = .1; % CPO original, Table 2; not ctx.alpha (VEFC weight).
            trial = best + (alpha * (1 - tau4) + tau4) .* ...
                (delta .* best - x) - tau5 * delta .* gamma .* force;
        end
    else
        error('Unsupported CPO paper defense');
    end
    assert(all(isfinite(trial)), 'CPO paper generated non-finite trial');

    % Continuous CPO bounds handling: re-enter [0,1] uniformly.
    outside = trial < 0 | trial > 1;
    if any(outside)
        replacement = articleRandomVector(rng, nnz(outside));
        trial(outside) = replacement;
    end
    child = articleProject(trial, population(parentIndex, :), bestPlan, which, progress, ctx, offsets, cache, rng);
end

function values = articleRandomVector(rng, n)
    values = zeros(1, n);
    for j = 1:n
        values(j) = rng.random();
    end
end

function plan = articleProject(trial, parent, bestPlan, which, progress, ctx, offsets, cache, rng)
    % VEFC-specific categorical projection of the ORIGINAL continuous CPO
    % trial.  The CPO defense formulas are unchanged before this point.
    %
    % A full per-task argmax changes too many DAG-coupled assignments at
    % once and can destroy a good greedy schedule.  Project to a bounded
    % number of provider edits (trust-region/Hamming projection) instead.
    % The radius is a projection parameter, NOT a CPO/ACCPO equation.
    D = ctx.dimension;
    if which <= 2
        anchor = parent;       % Exploration near the current individual.
    else
        anchor = bestPlan;     % Exploitation around the best known plan.
    end
    plan = anchor;
    alternative = anchor;
    margin = -inf(1, D);
    mutable = zeros(1, D);
    nMutable = 0;
    for g = 1:D
        dom = ctx.domain{ctx.optimTaskIds(g)};
        if numel(dom) <= 1
            continue
        end
        currentIdx = find(dom == anchor(g), 1);
        assert(~isempty(currentIdx), 'CPO article: anchor outside task domain');
        q = trial(offsets(g)+1:offsets(g+1));
        anchorScore = q(currentIdx);
        q(currentIdx) = -inf;
        [altScore, altIdx] = max(q);
        alternative(g) = dom(altIdx);
        margin(g) = altScore - anchorScore;
        nMutable = nMutable + 1;
        mutable(nMutable) = g;
    end
    mutable = mutable(1:nMutable);
    if nMutable == 0
        return
    end

    progress = max(0, min(1, progress));
    scale = max(2, min(6, ceil(log2(D + 1))));
    if which == 1                  % Sight: wider exploratory neighborhoods.
        maxEdits = 1 + round((scale - 1) * (1 - progress));
    elseif which == 2              % Sound: moderate exploration.
        maxEdits = 1 + round((min(5, scale) - 1) * (1 - progress));
    elseif which == 3              % Odor: gradually localize around best.
        maxEdits = 1 + round(2 * (1 - progress));
    else                           % Physical attack: one-task refinement.
        maxEdits = 1;
    end
    maxEdits = max(1, min(nMutable, maxEdits));
    editCount = 1 + rng.randbelow(maxEdits);

    % Prefer task/provider changes with stronger CPO-derived evidence,
    % while retaining a nonzero chance of exploring every mutable task.
    evidence = margin(mutable);
    evidence = max(-2, min(2, evidence));
    weights = .1 + exp(2.5 * (evidence - max(evidence)));
    sampleCount = min(nMutable, maxEdits);
    order = optim.OptimizerCommon.weighted(mutable, weights, sampleCount, rng);
    candidate = anchor;
    for k = 1:numel(order)
        g = order(k);
        candidate(g) = alternative(g);
        if k >= editCount && ~isKey(cache, optim.OptimizerCommon.key(candidate))
            plan = candidate;
            return
        end
    end

    % Only if local proposals are already in the evaluation cache, try
    % uncached single-task alternatives. No extra fitness calls are made.
    for k = 1:nMutable
        g = mutable(k);
        dom = ctx.domain{ctx.optimTaskIds(g)};
        q = trial(offsets(g)+1:offsets(g+1));
        [~, rank] = sort(q, 'descend');
        for j = reshape(rank, 1, [])
            if dom(j) == anchor(g)
                continue
            end
            candidate = anchor;
            candidate(g) = dom(j);
            if ~isKey(cache, optim.OptimizerCommon.key(candidate))
                plan = candidate;
                return
            end
        end
    end
    % All considered assignments have already been evaluated.
    plan = anchor;
end

