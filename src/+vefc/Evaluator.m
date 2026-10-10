classdef Evaluator
    methods (Static)

        function state = initial(ctx, record)
            if nargin < 2
                record = true;
            end
            state = struct('providerReady', max(0, ctx.initialProviderFinish), 'linkReady', max(0, ctx.initialLinkFinish), 'start', zeros(ctx.taskCount, 1), 'finish', zeros(ctx.taskCount, 1), 'energy', zeros(ctx.taskCount, 1), 'assignment', zeros(ctx.taskCount, 1), 'rank', zeros(ctx.taskCount, 1), 'providerRank', zeros(ctx.providerCount, 1), 'cache', {ctx.initialCache}, 'transfers', {cell(ctx.taskCount, 1)}, 'cacheBefore', {cell(ctx.taskCount, 1)}, 'cacheAfter', {cell(ctx.taskCount, 1)}, 'assigned', false(ctx.taskCount, 1), 'order', [], 'record', record);
            if ~ctx.useCaching
                state.cache = cell(ctx.providerCount, 1);
            end
            for t = ctx.entryTaskIds
                p = ctx.localProvider(ctx.taskApp(t));
                state = vefc.Evaluator.assign(ctx, state, t, p, [], true);
            end
        end

        function [time, energy] = compute(ctx, a, p, t, cache)
            f = ctx.allocatedCpu(a, p);
            assert(f > 0);
            c = ctx.cycles(t);
            local = p == ctx.localProvider(a);
            miss = ~ctx.useCaching || ~ismember(ctx.taskType(t), cache{p});
            W = ctx.compileCycles(ctx.taskType(t));
            if isfield(ctx, 'compileCyclesByApp')
                W = ctx.compileCyclesByApp(a, ctx.taskType(t));
            end
            compile = double(~local && miss) * W;
            if local
                time = c / f;
            elseif ctx.isRsu(p)
                time = compile / f + c / f;
            else
                time = max(0, compile / f) + max(0, c / f);
            end
            if ctx.isRsu(p)
                energy = 0;
            elseif local
                energy = ctx.params.k * f^2 * c;
            else
                energy = ctx.params.k * f^2 * compile + ctx.params.k * f^2 * c;
            end
        end

        function [q, st, fi, en, link, trans] = candidate(ctx, state, t, p)
            a = ctx.taskApp(t);
            assert(ismember(p, ctx.domain{t}), 'Provider outside task domain');
            pred = ctx.predecessor{t};
            ready = 0;
            txenergy = 0;
            link = state.linkReady;
            trans = struct([]);
            if ~isempty(pred)
                [~, ix] = sortrows([state.finish(pred), (1:numel(pred))'], [1 2]);
                pred = pred(ix);
            end
            for par = pred
                assert(state.assigned(par), 'Unscheduled predecessor');
                src = state.assignment(par);
                sourceFinish = state.finish(par);
                if src == p
                    ready = max(ready, sourceFinish);
                    continue
                end
                bits = ctx.edgeBits(par, t);
                physical = vefc.Evaluator.radioKey(ctx, a, src, p);
                if isempty(physical)
                    duration = 0;
                    energy = 0;
                    begin = sourceFinish;
                else
                    rs = physical(1);
                    rd = physical(2);
                    duration = bits / ctx.linkRate(a, src, p);
                    if ~ctx.isRsu(rs)
                        energy = ctx.linkPower(a, src, p) * duration;
                    else
                        energy = 0;
                    end
                    begin = max(sourceFinish, link(rs, rd));
                    link(rs, rd) = begin + duration;
                end
                arrival = begin + duration;
                ready = max(ready, arrival);
                txenergy = txenergy + energy;
                if state.record
                    transferRecord = struct('predecessor_task_id', ctx.taskBaseId(par), 'source_provider_id', ctx.providerId(src), 'destination_provider_id', ctx.providerId(p), 'data_bits', bits, 'transfer_start_s', begin, 'transfer_time_s', duration, 'arrival_time_s', arrival, 'transfer_energy_j', energy);
                    if isempty(trans)
                        trans = transferRecord;
                    else
                        trans(end + 1) = transferRecord;
                    end
                end
            end
            [time, energy] = vefc.Evaluator.compute(ctx, a, p, t, state.cache);
            st = max(ready, state.providerReady(p));
            fi = st + time;
            service = 0;
            if p ~= ctx.localProvider(a) && (~ctx.useCaching || ~ismember(ctx.taskType(t), state.cache{p}))
                service = ctx.serviceProgramEnergy(a, p, ctx.taskType(t));
            end
            en = energy + txenergy + service;
            q = vefc.FormulaLibrary.offloadingEfficiency(ctx.alpha(a), ctx.beta(a), ctx.modelTref(a), ctx.modelElocal(a), fi, en);
        end

        function key = radioKey(ctx, a, p, q)
            if p == q || (ctx.isRsu(p) && ctx.isRsu(q))
                key = [];
                return
            end
            key = ctx.radioEndpoint(a, [p q]);
            if key(1) == key(2)
                key = [];
            end
        end

        function state = assign(ctx, state, t, p, remaining, entry)
            if nargin < 6
                entry = false;
            end
            assert(~state.assigned(t), 'Duplicate task');
            before = state.cache{p};
            [~, st, fi, en, link, trans] = vefc.Evaluator.candidate(ctx, state, t, p);
            state.providerReady(p) = fi;
            state.linkReady = link;
            state.start(t) = st;
            state.finish(t) = fi;
            state.energy(t) = en;
            state.assignment(t) = p;
            state.assigned(t) = true;
            state.providerRank(p) = state.providerRank(p) + 1;
            state.rank(t) = state.providerRank(p);
            if state.record
                state.transfers{t} = trans;
            end
            state.order(end + 1) = t;
            if ~entry && p ~= ctx.localProvider(ctx.taskApp(t)) && ctx.useCaching
                state.cache = vefc.CacheManager.update(ctx, state.cache, p, t, remaining);
            end
            if state.record
                state.cacheBefore{t} = before;
                state.cacheAfter{t} = state.cache{p};
            end
        end

        function result = evaluate(ctx, solution, record)
            if nargin < 3
                record = true;
            end
            solution = optim.OptimizerCommon.repair(solution, ctx);
            state = vefc.Evaluator.initial(ctx, record);
            for i = 1:ctx.dimension
                t = ctx.optimTaskIds(i);
                state = vefc.Evaluator.assign(ctx, state, t, solution(i), ctx.optimTaskIds(i + 1:end), false);
            end
            result = vefc.Evaluator.finish(ctx, state, solution);
        end

        function result = finish(ctx, state, solution)
            A = ctx.applicationCount;
            delay = zeros(A, 1);
            energy = zeros(A, 1);
            eff = zeros(A, 1);
            complete = false(A, 1);
            schedule = struct([]);
            apps = struct([]);
            for a = 1:A
                members = state.order(ctx.taskApp(state.order) == a);
                delay(a) = max(state.finish(members));
                energy(a) = vefc.FormulaLibrary.pythonSum(state.energy(members));
                eff(a) = vefc.FormulaLibrary.paperEfficiency(ctx.alpha(a), ctx.beta(a), ctx.referenceTime(a), ctx.localEnergy(a), delay(a), energy(a));
                complete(a) = all(state.assigned(ctx.taskApp == a)) && delay(a) <= ctx.deadline(a);
                if state.record
                    t = ctx.entryTaskIds(a);
                    applicationRecord = struct('application_id', ctx.applicationId(a), 'vehicle_id', ctx.missionVehicleId(a), 'deadline_s', ctx.deadline(a), 'alpha_n', ctx.alpha(a), 'beta_n', ctx.beta(a), 'delay_s', delay(a), 'energy_j', energy(a), 'efficiency', eff(a), 'completed', complete(a), 'task_count', sum(ctx.taskApp == a), 'optimized_task_count', sum(ctx.taskApp == a) - 1, 'scheduled_task_count', numel(members), 'entry_task_id', ctx.taskBaseId(t), 'entry_provider_id', ctx.providerId(ctx.localProvider(a)), 'providers_used', sort(unique(ctx.providerId(state.assignment(members))))');
                    if isempty(apps)
                        apps = applicationRecord;
                    else
                        apps(a) = applicationRecord;
                    end
                end
            end
            if state.record
                for t = state.order
                    a = ctx.taskApp(t);
                    p = state.assignment(t);
                    mode = 'v2v';
                    if p == ctx.localProvider(a)
                        mode = 'local';
                    elseif ctx.isRsu(p)
                        mode = 'v2i';
                    end
                    before = sort(state.cacheBefore{t});
                    after = sort(state.cacheAfter{t});
                    hit = [];
                    if ~ctx.entryTask(t) && ~strcmp(mode, 'local')
                        hit = ismember(ctx.taskType(t), before);
                    end
                    taskRecord = struct('joint_task_id', t, 'application_id', ctx.applicationId(a), 'task_id', ctx.taskBaseId(t), 'task_type_id', ctx.taskType(t), 'provider_id', ctx.providerId(p), 'provider_mode', mode, 'rank', state.rank(t), 'start_s', state.start(t), 'finish_s', state.finish(t), 'energy_j', state.energy(t), 'transfers', state.transfers{t}, 'cpu_frequency_hz', ctx.allocatedCpu(a, p), 'cpu_fmax_hz', ctx.providerCpu(p), 'is_entry', ctx.entryTask(t), 'cache_before', before, 'cache_after', after, 'cache_hit', hit, 'cache_miss', ~hit, 'cache_inserted_count', numel(setdiff(after, before)), 'cache_evicted_count', numel(setdiff(before, after)), 'cache_update_required', ~isequal(before, after));
                    if isempty(schedule)
                        schedule = taskRecord;
                    else
                        schedule(end + 1) = taskRecord;
                    end

                end
            end
            score = vefc.FormulaLibrary.pythonSum(eff);
            result = struct('score', score, 'totalEfficiency', score, 'avgEfficiency', mean(eff), 'avgDelay', mean(delay), 'avgEnergy', mean(energy), 'totalEnergy', vefc.FormulaLibrary.pythonSum(energy), 'completionRate', mean(complete), 'applicationDelay', delay, 'applicationEnergy', energy, 'applicationEfficiency', eff, 'completed', complete, 'solution', solution, 'assignment', state.assignment', 'taskStart', state.start, 'taskFinish', state.finish, 'taskEnergy', state.energy, 'cache', {state.cache}, 'schedule', schedule, 'applications', apps);
        end

    end
end
