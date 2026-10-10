function [bestSolution, evaluation, history] = cpo(ctx, cfg)

    %% 1. Settings and shared evaluation budget
    variant = 'cpo';
    if isfield(cfg, 'variant')
        variant = cfg.variant;
    end
    guide = buildGuidance(ctx, variant);
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
    if guide.memory
        memory = initializeSuccessMemory(ctx);
    end
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
        if ~isempty(memory)
            decaySuccessMemory();
        end
        current = population;
        currentScores = scores;
        elites = population(1:min(8, populationSize), :);
        indices = 1:min(activeCount, size(population, 1));
        if populationSize > activeCount
            tail = rng.shuffle(activeCount + 1:populationSize);
            n = max(1, floor(activeCount / 5));
            indices = [indices(1:end - n) tail(1:min(n, numel(tail)))];
        end
        candidates = zeros(0, ctx.dimension);
        candidateScores = [];
        improvements = struct([]);
        accepted = 0;
        attempts = 0;
        generated = 0;
        counts = zeros(1, 5);
        target = min(activeCount, budget.remaining());
        schedule = defenseSchedule(target, progress, stagnation, memory, rng);
        before = budget.Count;
        maxAttempts = max(activeCount * 10, target * 12);
        cursor = 0;
        while budget.Count - before < target && attempts < maxAttempts
            attempts = attempts + 1;
            ix = indices(mod(cursor, numel(indices)) + 1);
            cursor = cursor + 1;
            parent = current(ix, :);
            parentScore = currentScores(ix);
            peers = current(~all(bsxfun(@eq, current, parent), 2), :);
            if isempty(peers)
                peers = current;
            end
            escape = stagnation >= 3 && rng.random() < .15;
            if escape
                strategy = 1;
                counts(5) = counts(5) + 1;
            else
                completed = budget.Count - before;
                if completed < numel(schedule)
                    strategy = schedule(completed + 1);
                else
                    strategy = chooseDefense(progress, stagnation, memory, rng);
                end
            end
            counts(strategy) = counts(strategy) + 1;
            child = generateCandidate(strategy, parent, bestSolution, peers, ctx, guide, progress, rng, memory, elites);
            [childEv, isNew] = budget.evaluate(child);
            if isempty(childEv)
                break
            end
            if ~isNew
                continue
            end
            generated = generated + 1;
            score = childEv.score;
            if score > parentScore + 1e-12
                improvementRecord = struct('child', child, 'parent', parent, 'strategy', strategy, 'gain', score - parentScore);
                if isempty(improvements)
                    improvements = improvementRecord;
                else
                    improvements(end + 1) = improvementRecord;
                end
            end
            candidates(end + 1, :) = child;
            candidateScores(end + 1, 1) = score;
        end
        previous = bestScore;
        [population, scores] = optim.OptimizerCommon.sortUnique([current; candidates], [currentScores; candidateScores]);
        assert(size(population, 1) >= populationSize);
        population = population(1:populationSize, :);
        scores = scores(1:populationSize);
        for row = improvements
            if any(all(bsxfun(@eq, population, row.child), 2))
                accepted = accepted + 1;
                if ~isempty(memory)
                    rewardSuccessMemory(row.strategy, row.child, row.parent, row.gain);
                end
            end
        end
        if scores(1) > bestScore + 1e-12
            bestSolution = population(1, :);
            bestScore = scores(1);
        end
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
        h.diagnostics = struct('active_population_size', activeCount, 'generated_trials', generated, 'unique_trial_count', generated, 'accepted_candidates', accepted, 'candidate_attempts', attempts, 'duplicate_trial_count', max(0, attempts - generated), 'stagnation_generations', stagnation, 'search_progress', progress, 'best_improved', improved, 'cpo_variant', variant, 'criticality_guidance', guide.critical, 'cache_coupling', guide.cache, 'success_memory', guide.memory, 'model_guidance', guide.model, 'defense_trials', counts, 'cpo_strategy_credit', credit, 'cpo_accepted_by_strategy', acceptedBy, 'cpo_task_provider_memory_entries', taskEntries, 'cpo_service_provider_memory_entries', serviceEntries, 'population_unique_count', size(population, 1), 'population_mean_hamming', optim.OptimizerCommon.diversity(population));
    end

    function decaySuccessMemory()
        memory.strategy = max(.05, .9 * memory.strategy);
        memory.taskProvider = .9 * memory.taskProvider;
        memory.serviceProvider = .9 * memory.serviceProvider;
        memory.taskProvider(memory.taskProvider < 1e-10) = 0;
        memory.serviceProvider(memory.serviceProvider < 1e-10) = 0;
    end

    function rewardSuccessMemory(strategy, child, parent, gain)
        if gain <= 0
            return
        end
        s = min(2, .25 + log1p(gain));
        memory.strategy(strategy) = memory.strategy(strategy) + s;
        memory.accepted(strategy) = memory.accepted(strategy) + 1;
        changed = find(child ~= parent);
        if isempty(changed)
            return
        end
        for g = changed
            memory.taskProvider(g, child(g)) = memory.taskProvider(g, child(g)) + s / numel(changed);
            memory.serviceProvider(memory.types(g), child(g)) = memory.serviceProvider(memory.types(g), child(g)) + s / numel(changed);
        end
    end

end

%% DAG, deadline, cache and computation guidance (proposal only)

function guide = buildGuidance(ctx, variant)
    D = ctx.dimension;
    P = ctx.providerCount;
    tasks = ctx.optimTaskIds;
    guide = struct('critical', true, 'cache', true, 'memory', true, 'model', true, 'deadline', true, 'prior', zeros(D, P), 'energy', zeros(1, D), 'affinity', zeros(D, P), 'structural', zeros(1, D));
    if strcmp(variant, 'dcpo_base')
        guide.critical = false;
        guide.cache = false;
        guide.memory = false;
        guide.model = false;
        guide.deadline = false;
    elseif strcmp(variant, 'dcpo_criticality')
        guide.cache = false;
        guide.memory = false;
        guide.model = false;
        guide.deadline = false;
    elseif strcmp(variant, 'dcpo_cache')
        guide.critical = false;
        guide.memory = false;
        guide.model = false;
        guide.deadline = false;
    else
        assert(strcmp(variant, 'cpo'));
    end
    reach = zeros(1, D);
    for g = 1:D
        t = tasks(g);
        a = ctx.taskApp(t);
        dom = ctx.domain{t};
        time = zeros(size(dom));
        energy = time;
        for j = 1:numel(dom)
            [time(j), energy(j)] = vefc.Evaluator.compute(ctx, a, dom(j), t, ctx.initialCache);
        end
        cost = ctx.alpha(a) * time / ctx.modelTref(a) + ctx.beta(a) * energy / ctx.modelElocal(a);
        lo = min(cost);
        hi = max(cost);
        span = hi - lo;
        if hi <= lo + 1e-18
            prior = .5 * ones(size(cost));
        else
            prior = (hi - cost) / span;
        end
        guide.prior(g, dom) = prior;
        guide.energy(g) = min(1, ctx.beta(a) * (max(energy) - min(energy)) / max(ctx.modelElocal(a), 1e-18));
        seen = [];
        todo = ctx.children{t};
        while ~isempty(todo)
            ch = todo(1);
            todo(1) = [];
            if ismember(ch, seen)
                continue
            end
            seen(end + 1) = ch;
            todo = [todo ctx.children{ch}];
        end
        reach(g) = numel(seen);
        future = tasks(g + 1:end);
        future = future(ctx.taskType(future) == ctx.taskType(t));
        bytes = ceil(ctx.serviceBits(ctx.taskType(t)) / 8);
        for p = dom
            if bytes > 0 && ctx.providerCache(p) >= bytes && ~isempty(future)
                guide.affinity(g, p) = sum(cellfun(@(v)ismember(p, v), ctx.domain(future))) / numel(future);
            end
        end
    end
    guide.structural = .65 * normalizeGuidance(ctx.globalRank(tasks)', .5) + .35 * normalizeGuidance(reach, .5);
end

function v = normalizeGuidance(v, neutral)
    lo = min(v);
    hi = max(v);
    if hi <= lo
        v = ones(size(v)) * neutral;
    else
        v = (v - lo) / (hi - lo);
    end
end

function rank = taskCriticality(guide, ctx, indices)
    if ~guide.critical
        rank = ones(size(indices));
        return
    end
    v = guide.structural(indices);
    lo = min(v);
    hi = max(v);
    if hi <= lo
        rank = ones(size(v));
    else
        rank = .25 + .75 * (v - lo) / (hi - lo);
    end
    if guide.deadline
        d = 1 ./ ctx.deadline(ctx.taskApp(ctx.optimTaskIds(indices)))';
        d = normalizeGuidance(d, 1);
        rank = .7 * rank + .3 * d;
    end
end

%% The four discrete CPO defenses

function child = generateCandidate(strategy, current, bestSolution, peers, ctx, guide, progress, rng, memory, elites)
    peerA = peers(rng.randbelow(size(peers, 1)) + 1, :);
    peerB = peers(rng.randbelow(size(peers, 1)) + 1, :);
    D = numel(current);
    indices = 1:D;
    child = current;
    rank = taskCriticality(guide, ctx, indices);
    % Sight/sound: explore disagreements with peers and the best solution.
    if strategy <= 2
        if strategy == 1
            peerB = peerA;
        end
        disagreement = (bestSolution ~= current) + (peerA ~= current) + (peerB ~= current);
        structural = ones(1, D);
        if guide.critical
            structural = 1.25 - rank;
        end
        count = max(1, min(D, ceil(2 + (max(2, ceil(log2(D + 1))) - 2) * (1 - progress))));
        chosen = optim.OptimizerCommon.weighted(indices, 1 + 1.15 * disagreement + .85 * structural, count, rng);
        for g = chosen
            dom = ctx.domain{ctx.optimTaskIds(g)};
            alternatives = dom(dom ~= current(g));
            if strategy == 1
                suggested = [peerA(g) bestSolution(g)];
                suggested = suggested(ismember(suggested, dom) & suggested ~= current(g));
                if ~isempty(suggested) && rng.random() < .65
                    p = rng.choice(suggested);
                else
                    p = sampleProvider(g, alternatives, memory, rng, .60);
                end
            else
                candidates = [peerA(g) peerB(g) bestSolution(g)];
                candidates = candidates(ismember(candidates, dom) & candidates ~= current(g));
                if ~isempty(candidates) && rng.random() < .80
                    ids = optim.PythonRandom.intSetOrder(ctx.providerId(candidates)');
                    [~, providers] = ismember(ids, ctx.providerId);
                    weights = arrayfun(@(p)sum(candidates == p), providers);
                    p = optim.OptimizerCommon.weighted(providers, weights, 1, rng);
                else
                    p = sampleProvider(g, alternatives, memory, rng, .45);
                end
            end
            if ~isempty(p)
                child(g) = p;
            end
        end
        % Odor: use later same-service tasks and capacity-feasible cache affinity.
    elseif strategy == 3
        count = max(1, min(D, ceil(1 + 3 * (1 - progress))));
        energy = guide.energy;
        if ~guide.model
            energy(:) = 0;
        end
        weights = rank .* (.35 + 1.65 * (bestSolution ~= current)) .* (1 + .35 * energy);
        anchor = optim.OptimizerCommon.weighted(indices, weights, 1, rng);
        types = ctx.taskType(ctx.optimTaskIds);
        same = [];
        if guide.cache
            same = find(indices > anchor & types' == types(anchor));
        end
        extra = max(0, count - 1);
        if ~isempty(same)
            extra = max(1, extra);
        end
        chosen = [anchor optim.OptimizerCommon.weighted(same, .40 + rank(same), extra, rng)];
        selectedAnchor = [];
        for g = chosen
            dom = ctx.domain{ctx.optimTaskIds(g)};
            alternatives = dom(dom ~= current(g));
            elite = bestSolution(g);
            shared = bestSolution(anchor);
            if g ~= anchor && ~isempty(selectedAnchor)
                shared = selectedAnchor;
            end
            if ~ismember(shared, dom)
                shared = [];
            end
            affinity = [];
            if guide.cache && ~isempty(alternatives)
                scores = guide.affinity(g, alternatives);
                mx = max(scores);
                if mx > 0
                    affinity = rng.choice(alternatives(abs(scores - mx) <= 1e-12));
                end
            end
            if g ~= anchor && ~isempty(selectedAnchor) && ismember(selectedAnchor, dom)
                p = selectedAnchor;
            elseif ~isempty(affinity) && rng.random() < .45
                p = affinity;
            elseif ~isempty(shared) && shared ~= current(g) && rng.random() < .55
                p = shared;
            elseif ismember(elite, dom) && elite ~= current(g) && rng.random() < .80
                p = elite;
            else
                [providers, votes] = eliteProviderVotes(elites, g, alternatives);
                if ~isempty(votes) && rng.random() < .70
                    p = optim.OptimizerCommon.weighted(providers, votes, 1, rng);
                else
                    p = guidedProvider(g, alternatives, guide, memory, rng, progress, .20);
                end
            end
            if ~isempty(p)
                child(g) = p;
                if g == anchor
                    selectedAnchor = p;
                end
            elseif g == anchor
                selectedAnchor = current(g);
            end
        end
        % Physical attack: refine one task around the best/elite solutions.
    elseif strategy == 4
        if rng.random() < .88
            child = bestSolution;
        end
        weights = zeros(1, D);
        mutable = [];
        energy = guide.energy;
        if ~guide.model
            energy(:) = 0;
        end
        for g = indices
            dom = ctx.domain{ctx.optimTaskIds(g)};
            alt = dom(dom ~= child(g));
            if isempty(alt)
                continue
            end
            mutable(end + 1) = g;
            [providers, votes] = eliteProviderVotes(elites, g, dom);
            disagreement = 0;
            if ~isempty(votes)
                total = vefc.FormulaLibrary.pythonSum(votes);
                same = vefc.FormulaLibrary.pythonSum(votes(providers == child(g)));
                disagreement = max(0, 1 - same / max(1e-12, total));
            end
            weights(g) = .25 + rank(g) + 2.25 * disagreement + .75 * energy(g);
        end
        if isempty(mutable)
            return
        end
        g = optim.OptimizerCommon.weighted(mutable, weights(mutable), 1, rng);
        dom = ctx.domain{ctx.optimTaskIds(g)};
        alt = dom(dom ~= child(g));
        [providers, votes] = eliteProviderVotes(elites, g, alt);
        if ~isempty(votes) && rng.random() < .68
            p = optim.OptimizerCommon.weighted(providers, votes, 1, rng);
        else
            p = guidedProvider(g, alt, guide, memory, rng, progress, .10 + .12 * (1 - progress));
        end
        child(g) = p;
    else
        error('Unknown defense');
    end
    if isequal(child, current)
        mutable = [];
        for g = indices
            if any(ctx.domain{ctx.optimTaskIds(g)} ~= current(g))
                mutable(end + 1) = g;
            end
        end
        if ~isempty(mutable)
            g = rng.choice(mutable);
            dom = ctx.domain{ctx.optimTaskIds(g)};
            child(g) = sampleProvider(g, dom(dom ~= current(g)), memory, rng, .35);
        end
    end
end

%% Provider selection using the same success memory

function p = sampleProvider(g, alternatives, memory, rng, floor)
    p = [];
    if isempty(alternatives)
        return
    end
    if isempty(memory) || rng.random() < floor
        p = rng.choice(alternatives);
    else
        weights = .05 + providerMemoryScores(memory, g, alternatives);
        p = optim.OptimizerCommon.weighted(alternatives, weights, 1, rng);
    end
end

function p = guidedProvider(g, alt, guide, memory, rng, progress, floor)
    p = [];
    if isempty(alt)
        return
    end
    if guide.model && any(guide.prior(g, alt) > 0) && rng.random() < .35 * (.55 + .45 * progress)
        p = optim.OptimizerCommon.weighted(alt, .05 + guide.prior(g, alt), 1, rng);
    else
        p = sampleProvider(g, alt, memory, rng, floor);
    end
end

function [providers, votes] = eliteProviderVotes(elites, g, dom)
    providers = [];
    votes = [];
    for i = 1:min(8, size(elites, 1))
        p = elites(i, g);
        if ~ismember(p, dom)
            continue
        end
        j = find(providers == p, 1);
        if isempty(j)
            providers(end + 1) = p;
            votes(end + 1) = 1 / i;
        else
            votes(j) = votes(j) + 1 / i;
        end
    end
end

%% Defense selection and its minimum representation

function strategy = chooseDefense(progress, stagnation, memory, rng)
    base = [.24 * (1 - progress) + .06, .19 * (1 - progress) + .06, .18 + .08 * progress, .27 + .30 * progress];
    escape = min(.12, .025 * max(0, stagnation));
    base(1) = base(1) + escape;
    base(4) = base(4) + .5 * escape;
    learned = ones(1, 4) * .25;
    if ~isempty(memory)
        learned = max(.05, memory.strategy);
        learned = learned / vefc.FormulaLibrary.pythonSum(learned);
    end
    strategy = optim.OptimizerCommon.weighted(1:4, max(.04, .78 * base + .22 * learned), 1, rng);
end

function schedule = defenseSchedule(count, progress, stagnation, memory, rng)
    schedule = zeros(1, count);
    for j = 1:count
        schedule(j) = chooseDefense(progress, stagnation, memory, rng);
    end
    required = min(count, floor(count * [.10 .10 .16 .28]));
    for strategy = 1:4
        deficit = max(0, required(strategy) - sum(schedule == strategy));
        for j = 1:deficit
            counts = arrayfun(@(v)sum(schedule == v), 1:4);
            donors = find(counts > required);
            if isempty(donors)
                break
            end
            [~, ix] = max(counts(donors) - required(donors));
            donor = donors(ix);
            schedule(find(schedule == donor, 1)) = strategy;
        end
    end
    schedule = rng.shuffle(schedule);
end

%% Success-memory state; local to this CPO run

function memory = initializeSuccessMemory(ctx)
    memory = struct('strategy', ones(1, 4), 'accepted', zeros(1, 4), ...
                    'taskProvider', zeros(ctx.dimension, ctx.providerCount), ...
                    'serviceProvider', zeros(numel(ctx.serviceBits), ctx.providerCount), ...
                    'types', ctx.taskType(ctx.optimTaskIds));
end

function v = providerMemoryScores(memory, g, providers)
    v = .65 * normalizeMemoryScores(memory.taskProvider(g, providers)) + (1 - .65) * normalizeMemoryScores(memory.serviceProvider(memory.types(g), providers));
end

function v = normalizeMemoryScores(v)
    lo = min(v);
    hi = max(v);
    if hi <= lo
        v = ones(size(v)) * (hi > 0);
    else
        v = (v - lo) / (hi - lo);
    end
end
