classdef FitnessLibrary
    % Central registry for optimization fitness functions.
    %
    % Active fitnesses after cleanup:
    %   fitness_1          : exact paper objective (immutable baseline)
    %   fitness_load_aware : PaperQ + MEC Jain load-balance reward, lambda=0.05 default
    %
    % Optimizers do not contain fitness-specific logic. New/temporary fitness
    % functions should be added only here, then whitelisted in validateConfig.

    methods (Static)

        function out = evaluate(ctx, paperEff, delay, energy, state) %#ok<INUSD>
            paperScore = vefc.FormulaLibrary.pythonSum(paperEff);
            A = numel(paperEff);
            [jain, imbalance, busy, taskCount, providerIds] = ...
                vefc.FitnessLibrary.mecLoadMetrics(ctx, state);

            fitnessId = 'fitness_1';
            if isfield(ctx, 'fitnessId') && ~isempty(ctx.fitnessId)
                fitnessId = lower(char(ctx.fitnessId));
            end

            values = [NaN NaN imbalance];
            weights = [NaN NaN NaN];
            terms = [NaN NaN NaN];
            cost = NaN;

            switch fitnessId
                case 'fitness_1'
                    % === PAPER BASELINE -- DO NOT MODIFY ===================
                    % Q = sum_n [ alpha_n*(Tref_n-T_n)/Tref_n
                    %           + beta_n *(Elocal_n-E_n)/Elocal_n ]
                    score = paperScore;
                    label = 'Fitness 1 - Paper Baseline';
                    description = 'Exact article total offloading-efficiency objective';

                case 'fitness_load_aware'
                    % === LOAD-AWARE WEIGHTED-SUM FITNESS ===================
                    % S = (1-lambda)*PaperQ + lambda*A*Jain(MEC busy time)
                    %   = (1-lambda)*PaperQ + lambda*A*(1-loadImbalance)
                    % Default lambda = 0.05 (cfg.loadAwareWeight).
                    lambda = ctx.loadAwareWeight;
                    loadReward = A * jain;
                    score = (1 - lambda) * paperScore + lambda * loadReward;
                    weights = [1 - lambda, lambda, NaN];
                    terms = [(1 - lambda) * paperScore, lambda * loadReward, NaN];
                    values = [paperScore, loadReward, imbalance];
                    label = sprintf('Load-Aware WS (lambda=%.3g)', lambda);
                    description = 'Paper efficiency plus MEC Jain load-balance reward';

                % === TEMPORARY EXPERIMENTAL FITNESS SLOT ===================
                % To test a NEW temporary fitness later:
                % 1) add its config parameter(s) in config/defaultConfig.m;
                % 2) add its ID to allowedFitnesses in bench.validateConfig.m;
                % 3) add a new case here, e.g.:
                %
                % case 'fitness_experimental'
                %     score = ...;        % scalar value to MAXIMIZE
                %     label = 'Experimental Fitness';
                %     description = 'Temporary research fitness';
                %     values = [...];
                %     weights = [...];
                %     terms = [...];
                %
                % Keep fitness_1 unchanged.

                otherwise
                    error('Unknown fitness ID: %s', fitnessId);
            end

            out = struct( ...
                'id', fitnessId, ...
                'label', label, ...
                'description', description, ...
                'score', score, ...
                'paperScore', paperScore, ...
                'loadJain', jain, ...
                'loadImbalance', imbalance, ...
                'mecBusyTime', busy, ...
                'mecTaskCount', taskCount, ...
                'mecProviderIds', providerIds, ...
                'objectiveValues', values, ...
                'weights', weights, ...
                'terms', terms, ...
                'cost', cost);
        end

        function [jain, imbalance, busy, taskCount, providerIds] = mecLoadMetrics(ctx, state)
            mec = find(ctx.isRsu);
            busy = zeros(1, numel(mec));
            taskCount = zeros(1, numel(mec));
            providerIds = ctx.providerId(mec);

            for i = 1:numel(mec)
                p = mec(i);
                tasks = find(state.assigned & state.assignment == p);
                taskCount(i) = numel(tasks);
                if ~isempty(tasks)
                    busy(i) = vefc.FormulaLibrary.pythonSum( ...
                        state.finish(tasks) - state.start(tasks));
                end
            end

            total = vefc.FormulaLibrary.pythonSum(busy);
            if total <= 1e-18
                % No MEC use is reported explicitly by mecTaskCount/mecBusyTime.
                % Mathematically all MEC loads are equal (zero), hence Jain=1.
                % Do not interpret this case as evidence of useful utilization.
                jain = 1;
                imbalance = 0;
                return
            end

            denom = numel(busy) * vefc.FormulaLibrary.pythonSum(busy .^ 2);
            if denom <= 1e-30
                jain = 1;
            else
                jain = min(1, max(0, total^2 / denom));
            end
            imbalance = 1 - jain;
        end

        function label = label(id)
            switch lower(char(id))
                case 'fitness_1'
                    label = 'Fitness 1 - Paper Baseline';
                case 'fitness_load_aware'
                    label = 'Load-Aware Weighted-Sum';
                otherwise
                    label = char(id);
            end
        end

    end
end
