classdef OptimizerCommon
    % Shared initialization, feasible assignments, Hamming distance and history.
    % initialPopulation keeps each optimizer's own greedy ratio/coverage order.
    methods (Static)

        function x = repair(x, ctx)
            x = fix(double(x(:)'));
            assert(numel(x) == ctx.dimension, 'Wrong solution dimension');
            for g = 1:ctx.dimension
                d = ctx.domain{ctx.optimTaskIds(g)};
                if ~ismember(x(g), d)
                    x(g) = d(1);
                end
            end
        end

        function k = key(x)
            k = sprintf('%d,', x);
        end

        function d = hamming(x, y)
            d = sum(x ~= y);
        end

        function x = randomSolution(ctx, r)
            x = zeros(1, ctx.dimension);
            for g = 1:ctx.dimension
                x(g) = r.choice(ctx.domain{ctx.optimTaskIds(g)});
            end
        end

        function [pop, scores] = greedyPopulation(ctx, size, r, budget)
            pop = zeros(size, ctx.dimension);
            scores = zeros(size, 1);
            for s = 1:size
                state = vefc.Evaluator.initial(ctx, false);
                mutation = r.randbelow(ctx.dimension) + 1;
                for g = 1:ctx.dimension
                    t = ctx.optimTaskIds(g);
                    dom = ctx.domain{t};
                    q = zeros(numel(dom), 1);
                    for j = 1:numel(dom)
                        q(j) = vefc.Evaluator.candidate(ctx, state, t, dom(j));
                    end
                    [~, ix] = sortrows([-q, ctx.providerId(dom)], [1 2]);
                    chosen = ix(1);
                    if s > 1 && g == mutation && numel(ix) > 1
                        chosen = ix(2);
                    end
                    p = dom(chosen);
                    pop(s, g) = p;
                    state = vefc.Evaluator.assign(ctx, state, t, p, ctx.optimTaskIds(g + 1:end), false);
                end
                ev = vefc.Evaluator.finish(ctx, state, pop(s, :));
                scores(s) = ev.score;
                if nargin >= 4 && ~isempty(budget)
                    budget.seed(pop(s, :), ev);
                end
            end
            [scores, ix] = sort(scores, 'descend');
            pop = pop(ix, :);
        end

        function pop = initialPopulation(ctx, size, ratio, r, budget, name)
            count = min(size, max(1, optim.PythonRandom.roundEven(size * ratio)));
            [greedy, ~] = optim.OptimizerCommon.greedyPopulation(ctx, count, optim.PythonRandom(ctx.seed), budget);
            if strcmp(name, 'puma')
                greedy = optim.OptimizerCommon.uniqueRows(greedy);
            end
            D = ctx.dimension;
            if strcmp(name, 'puma')
                diverse = size - rowsCount(greedy);
            else
                diverse = size - count;
            end
            plans = zeros(diverse, D);
            for g = 1:D
                dom = ctx.domain{ctx.optimTaskIds(g)};
                cover = diverse;
                if strcmp(name, 'puma')
                    cover = max(1, diverse);
                end
                quot = floor(cover / numel(dom));
                rem = mod(cover, numel(dom));
                choices = [];
                for p = dom
                    choices = [choices repmat(p, 1, quot)];
                end
                extra = r.shuffle(dom);
                choices = [choices extra(1:rem)];
                choices = r.shuffle(choices);
                if diverse > 0
                    plans(:, g) = choices';
                end
            end
            pop = zeros(0, D);
            if strcmp(name, 'puma')
                pop = greedy;
                for i = 1:diverse
                    pop = optim.OptimizerCommon.appendUnique(pop, plans(i, :));
                end
            else
                for i = 1:max(sizeOf(greedy), diverse)
                    if i <= sizeOf(greedy)
                        pop = optim.OptimizerCommon.appendUnique(pop, greedy(i, :));
                    end
                    if i <= diverse
                        pop = optim.OptimizerCommon.appendUnique(pop, plans(i, :));
                    end
                end
            end
            limit = 100;
            if strcmp(name, 'puma')
                limit = 150;
            end
            attempts = 0;
            while sizeOf(pop) < size && attempts < size * limit
                attempts = attempts + 1;
                pop = optim.OptimizerCommon.appendUnique(pop, optim.OptimizerCommon.randomSolution(ctx, r));
            end
            assert(sizeOf(pop) == size, 'Insufficient unique feasible solutions');
        end

        function p = appendUnique(p, x)
            if isempty(p) || ~any(all(bsxfun(@eq, p, x), 2))
                p(end + 1, :) = x;
            end
        end

        function p = uniqueRows(p)
            ix = [];
            for i = 1:size(p, 1)
                if isempty(ix) || ~any(all(bsxfun(@eq, p(ix, :), p(i, :)), 2))
                    ix(end + 1) = i;
                end
            end
            p = p(ix, :);
        end

        function [p, s] = sortUnique(p, s)
            [s, ix] = sort(s, 'descend');
            p = p(ix, :);
            [~, ix] = unique(p, 'rows', 'stable');
            ix = sort(ix);
            p = p(ix, :);
            s = s(ix);
        end

        function [p, s] = evaluatePopulation(p, budget)
            s = zeros(size(p, 1), 1);
            n = 0;
            for i = 1:size(p, 1)
                [ev, ~] = budget.evaluate(p(i, :));
                if isempty(ev)
                    break
                end
                n = n + 1;
                s(i) = ev.score;
            end
            p = p(1:n, :);
            s = s(1:n);
            [s, ix] = sort(s, 'descend');
            p = p(ix, :);
        end

        function h = historyRow(iter, budget, s, p)
            h = struct('iteration', iter, 'functionEvaluations', budget.Count, 'bestTotalEfficiency', s, 'populationTotalEfficiencies', [], 'diagnostics', struct());
            if nargin > 3
                h.populationTotalEfficiencies = p(:)';
            end
        end

        function v = progress(count, initial, budget, iteration, iterations)
            if isfinite(budget) && budget > initial
                v = max(0, min(1, (count - initial) / (budget - initial)));
            else
                v = max(0, min(1, iteration / max(1, iterations)));
            end
        end

        function selected = weighted(items, weights, count, r)
            selected = [];
            weights = max(1e-12, weights);
            for k = 1:min(count, numel(items))
                threshold = r.random() * vefc.FormulaLibrary.pythonSum(weights);
                cum = 0;
                ix = numel(items);
                for j = 1:numel(items)
                    cum = cum + weights(j);
                    if threshold <= cum
                        ix = j;
                        break
                    end
                end
                selected(end + 1) = items(ix);
                items(ix) = [];
                weights(ix) = [];
            end
        end

        function value = diversity(p, compensated)
            if nargin < 2
                compensated = true;
            end
            distances = zeros(1, size(p, 1) * (size(p, 1) - 1) / 2);
            pairs = 0;
            for i = 1:size(p, 1)
                for j = i + 1:size(p, 1)
                    pairs = pairs + 1;
                    distances(pairs) = sum(p(i, :) ~= p(j, :)) / max(1, size(p, 2));
                end
            end
            if compensated
                value = vefc.FormulaLibrary.pythonSum(distances);
            else
                value = vefc.FormulaLibrary.sumOrdered(distances);
            end
            value = value / max(1, pairs);
        end

    end
end

function n = sizeOf(x)
    n = size(x, 1);
end

function n = rowsCount(x)
    n = size(x, 1);
end
