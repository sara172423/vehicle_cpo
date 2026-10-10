classdef EvaluationBudget < handle
    % Shared NFE protocol: count paid full evaluations and reuse cached results.
    % All population optimizers use this class; final report evaluation is separate.
    properties (SetAccess = private)
        Context
        Maximum
        Count = 0
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
            o.Count = o.Count + 1;
            k = optim.OptimizerCommon.key(x);
            if ~isKey(o.Cache, k)
                o.Cache(k) = ev;
            end
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
                ev = o.Cache(k);
                return
            end
            if o.exhausted()
                ev = [];
                return
            end
            ev = vefc.Evaluator.evaluate(o.Context, x, false);
            o.Count = o.Count + 1;
            o.Cache(k) = ev;
            isNew = true;
        end

    end
end
