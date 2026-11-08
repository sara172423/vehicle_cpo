classdef EvaluationBudget < handle
    % NFE = Number of Fitness Evaluations actually computed (full solutions).
    % Each greedy seed is explicitly computed and counted, even if duplicated.
    % A cache lookup is NOT a new evaluation. Partial greedy-provider scoring
    % is measured separately, not mislabelled as a full fitness evaluation.
    % The final best-schedule report is outside the optimization NFE budget.
    properties (SetAccess = private)
        Context
        Maximum
        Count = 0
        SeedEvaluationCount = 0
        SearchEvaluationCount = 0
        CacheHitCount = 0
        SeedDuplicateCount = 0
        GreedyCandidateCount = 0
        Cache
    end
    methods

        function o = EvaluationBudget(ctx, maxNfe, populationSize)
            if nargin < 3
                populationSize = 2;
            end
            if isempty(maxNfe)
                maxNfe = Inf;
            end
            assert(isinf(maxNfe) || maxNfe >= populationSize, 'Budget smaller than population');
            o.Context = ctx;
            o.Maximum = maxNfe;
            o.Cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        function seed(o, x, ev)
            % This score was computed via a complete greedy schedule.
            % Repeated seed schedules are genuine repeated computations;
            % therefore both count toward actual NFE, not unique NFE.
            assert(~o.exhausted(), 'Full evaluation budget exhausted during initialization');
            assert(isstruct(ev) && isfield(ev, 'score') && isfinite(ev.score), ...
                'Invalid complete greedy-seed fitness evaluation');
            x = optim.OptimizerCommon.repair(x, o.Context);
            k = optim.OptimizerCommon.key(x);
            o.Count = o.Count + 1;
            o.SeedEvaluationCount = o.SeedEvaluationCount + 1;
            if isKey(o.Cache, k)
                o.SeedDuplicateCount = o.SeedDuplicateCount + 1;
            else
                o.Cache(k) = ev;
            end
        end

        function recordGreedyCandidates(o, n)
            % PARTIAL candidate scoring in greedy initialization is not
            % a complete solution fitness evaluation and not NFE.
            assert(isscalar(n) && n >= 0 && fix(n) == n);
            o.GreedyCandidateCount = o.GreedyCandidateCount + n;
        end

        function d = diagnostics(o)
            assert(o.Count == o.SeedEvaluationCount + o.SearchEvaluationCount, ...
                'Inconsistent number of full fitness evaluations');
            d = struct( ...
                'fullFitnessEvaluations', o.Count, ...
                'seedFullEvaluations', o.SeedEvaluationCount, ...
                'searchFullEvaluations', o.SearchEvaluationCount, ...
                'cachedLookupCount', o.CacheHitCount, ...
                'duplicateSeedComputations', o.SeedDuplicateCount, ...
                'greedyPartialCandidateScores', o.GreedyCandidateCount, ...
                'distinctStoredSolutions', o.Cache.Count);
        end

        function tf = exhausted(o)
            tf = o.Count >= o.Maximum;
        end

        function n = remaining(o)
            n = max(0, o.Maximum - o.Count);
        end

        function [ev, isNew] = evaluate(o, x)
            x = optim.OptimizerCommon.repair(x, o.Context);
            k = optim.OptimizerCommon.key(x);
            isNew = false;
            if isKey(o.Cache, k)
                o.CacheHitCount = o.CacheHitCount + 1;
                ev = o.Cache(k);
                return
            end
            if o.exhausted()
                ev = [];
                return
            end
            ev = vefc.Evaluator.evaluate(o.Context, x, false);
            o.Count = o.Count + 1;
            o.SearchEvaluationCount = o.SearchEvaluationCount + 1;
            o.Cache(k) = ev;
            isNew = true;
        end

    end
end
