classdef CacheManager
    methods (Static)

        function cache = update(ctx, cache, p, t, remaining)
            if ~ctx.useCaching
                cache{p} = [];
                return
            end
            kind = ctx.taskType(t);
            current = cache{p};
            if ismember(kind, current)
                return
            end
            items = sort(unique([current(:)' kind]));
            weights = ceil(ctx.serviceBits(items) / 8);
            values = zeros(size(items));
            cyc = ctx.cycles(remaining);
            types = ctx.taskType(remaining);
            denom = vefc.FormulaLibrary.sumOrdered(cyc(ismember(types, items)));
            for i = 1:numel(items)
                mu = 0;
                for q = 1:numel(cache)
                    if q ~= p && ismember(items(i), cache{q})
                        mu = mu + 1;
                    end
                end
                numerator = vefc.FormulaLibrary.sumOrdered(cyc(types == items(i)));
                d = (mu + 1) * denom;
                if d > 0
                    values(i) = numerator / d;
                end
            end
            cache{p} = vefc.CacheManager.knapsack(items, weights, values, fix(ctx.providerCache(p)));
        end

        function selected = knapsack(items, weights, values, capacity)
            % Same sparse DP, insertion ordering and tie rules as cache_knapsack_dp.
            if capacity <= 0
                selected = [];
                return
            end
            used = 0;
            scores = 0;
            sets = {[]};
            for k = 1:numel(items)
                if weights(k) > capacity
                    continue
                end
                oldUsed = used;
                oldScores = scores;
                oldSets = sets;
                for j = 1:numel(oldUsed)
                    nu = oldUsed(j) + fix(weights(k));
                    if nu > capacity
                        continue
                    end
                    ns = oldScores(j) + values(k);
                    candidate = [oldSets{j} items(k)];
                    ix = find(used == nu, 1);
                    if isempty(ix)
                        used(end + 1) = nu;
                        scores(end + 1) = ns;
                        sets{end + 1} = candidate;
                    elseif ns > scores(ix) || (ns == scores(ix) && numel(candidate) > numel(sets{ix}))
                        scores(ix) = ns;
                        sets{ix} = candidate;
                    end
                end
            end
            ix = 1;
            for j = 2:numel(used)
                if scores(j) > scores(ix) || (scores(j) == scores(ix) && (numel(sets{j}) > numel(sets{ix}) || (numel(sets{j}) == numel(sets{ix}) && used(j) < used(ix))))
                    ix = j;
                end
            end
            selected = sets{ix};
        end

    end
end
