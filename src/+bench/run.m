function results = run(data, cfg)
    cfg = bench.validateConfig(cfg, data);
    if strcmp(cfg.figure, 'all')
        results = struct('figure', 'all', 'results', struct());
        for z = 6:10
            c = cfg;
            c.figure = sprintf('figure_%d', z);
            c.algorithms = {};
            results.results.(c.figure) = bench.run(data, c);
        end
        return
    end
    scenarios = bench.scenarios(cfg, numel(data.vehicles));
    raw = struct([]);
    appRows = struct([]);
    conv = struct([]);
    audit = struct([]);
    runs = struct([]);
    records = struct([]);
    for s = 1:numel(scenarios)
        for rep = 1:cfg.repetitions
            scenario = scenarios(s);
            scenario.seed = cfg.seedStart + rep - 1;
            ctx = vefc.ContextBuilder.build(data, cfg, scenario);
            scenarioId = sprintf('%s_seed_%d_%s_%.1f', cfg.figure, scenario.seed, scenario.sweepParameter, scenario.sweepValue);
            scenarioRecord = struct('scenario_id', scenarioId, 'seed', scenario.seed, 'mission_vehicle_count', ctx.applicationCount, 'road_vehicle_count', numel(ctx.roadVehicleIds), 'mission_vehicle_ids', ctx.missionVehicleId, 'road_vehicle_ids', ctx.roadVehicleIds, 'road_positions', ctx.roadPosition, 'road_speeds_kmh', ctx.roadSpeeds, 'access_rsu_ids', ctx.roadAccessRsuId, 'deadlines_s', ctx.deadline, 'dag_type_ids', ctx.applicationTypeId, 'ranked_task_ids', ctx.optimTaskIds);
            if isempty(records)
                records = scenarioRecord;
            else
                records(end + 1) = scenarioRecord;
            end

            for a = 1:numel(cfg.algorithms)
                name = cfg.algorithms{a};
                tic;
                [x, ev, h, algCtx] = bench.runAlgorithm(name, ctx, cfg);
                runtime = toc;
                nfe = h(end).functionEvaluations;
                if isempty(nfe)
                    nfe = 0;
                end
                cap = cfg.maxFunctionEvaluations;
                if strcmp(name, 'dtosc')
                    cap = [];
                end
                exhausted = ~isempty(cap) && nfe >= cap;
                row = struct('figure', cfg.figure, 'scenario_id', scenarioId, 'seed', scenario.seed, 'sweep_parameter', scenario.sweepParameter, 'sweep_value', scenario.sweepValue, 'mission_vehicle_count', ctx.applicationCount, 'road_vehicle_count', numel(ctx.roadVehicleIds), 'mean_vehicle_speed_kmh', mean(ctx.roadSpeeds), 'mean_mec_capacity_ghz', ctx.mecCapacityGHz, 'algorithm', name, 'avg_delay', ev.avgDelay, 'avg_efficiency', ev.avgEfficiency, 'total_efficiency', ev.totalEfficiency, 'completion_rate', ev.completionRate, 'function_evaluations', nfe, 'max_function_evaluations', cap, 'evaluation_budget_exhausted', exhausted, 'runtime_seconds', runtime, 'executed_iterations', numel(h) - 1);
                if strcmp(cfg.figure, 'figure_9')
                    row.speed_kmh = scenario.speedKmh;
                elseif strcmp(cfg.figure, 'figure_10')
                    row.mec_capacity_ghz = scenario.mecCapacityGHz;
                end
                modes = {ev.schedule.provider_mode};
                energy = vefc.FormulaLibrary.pythonSum(ev.applicationEnergy);
                ar = struct('figure', cfg.figure, 'scenario_id', scenarioId, 'seed', scenario.seed, 'algorithm', name, 'application_count', ctx.applicationCount, 'completed_application_count', sum(ev.completed), 'total_energy_j', energy, 'avg_delay_s', ev.avgDelay, 'avg_efficiency', ev.avgEfficiency, 'total_efficiency', ev.score, 'completion_rate', ev.completionRate, 'runtime_seconds', runtime, 'executed_iterations', numel(h) - 1, 'function_evaluations', nfe, 'max_function_evaluations', cap, 'evaluation_budget_exhausted', exhausted, 'scheduled_task_count', numel(ev.schedule), 'local_task_count', sum(strcmp(modes, 'local')), 'v2v_task_count', sum(strcmp(modes, 'v2v')), 'v2i_task_count', sum(strcmp(modes, 'v2i')), 'transfer_count', sum(arrayfun(@(v)numel(v.transfers), ev.schedule)), 'cache_update_count', sum([ev.schedule.cache_update_required]), 'cache_hit_count', sum([ev.schedule.cache_hit]), 'cache_miss_count', sum([ev.schedule.cache_miss]), 'cache_insertion_count', sum([ev.schedule.cache_inserted_count]), 'cache_eviction_count', sum([ev.schedule.cache_evicted_count]));
                if isempty(audit)
                    audit = ar;
                else
                    audit(end + 1) = ar;
                end

                for j = 1:numel(ev.applications)
                    v = ev.applications(j);
                    prefix = struct('figure', cfg.figure, 'scenario_id', scenarioId, 'seed', scenario.seed, 'sweep_parameter', scenario.sweepParameter, 'sweep_value', scenario.sweepValue, 'algorithm', name);
                    fields = fieldnames(v);
                    for k = 1:numel(fields)
                        prefix.(fields{k}) = v.(fields{k});
                    end
                    if isempty(appRows)
                        appRows = prefix;
                    else
                        appRows(end + 1) = prefix;
                    end
                end
                for j = 1:numel(h)
                    nh = h(j).functionEvaluations;
                    if isempty(nh)
                        nh = 0;
                    end
                    for k = 1:numel(h(j).populationTotalEfficiencies)
                        convergenceRow = convergence('population', k - 1, h(j).populationTotalEfficiencies(k));
                        if isempty(conv)
                            conv = convergenceRow;
                        else
                            conv(end + 1) = convergenceRow;
                        end
                    end
                    convergenceRow = convergence('best', [], h(j).bestTotalEfficiency);
                    if isempty(conv)
                        conv = convergenceRow;
                    else
                        conv(end + 1) = convergenceRow;
                    end

                end
                if strcmp(cfg.figure, 'figure_6')
                    scenarioRaw = conv(strcmp({conv.scenario_id}, scenarioId) & strcmp({conv.algorithm}, name));
                    if isempty(raw)
                        raw = scenarioRaw;
                    else
                        raw = [raw scenarioRaw];
                    end

                elseif strcmp(cfg.figure, 'figure_8')
                    for ddl = sort(unique(ctx.deadline))'
                        mask = ctx.deadline == ddl;
                        rawRow = struct('figure', cfg.figure, 'scenario_id', scenarioId, 'seed', scenario.seed, 'algorithm', name, 'deadline_s', ddl, 'deadline_ms', ddl * 1000, 'avg_delay', mean(ev.applicationDelay(mask)), 'completion_rate', mean(ev.completed(mask)), 'application_count', sum(mask), 'runtime_seconds', runtime, 'executed_iterations', numel(h) - 1, 'function_evaluations', nfe, 'max_function_evaluations', cap, 'evaluation_budget_exhausted', exhausted);
                        if isempty(raw)
                            raw = rawRow;
                        else
                            raw(end + 1) = rawRow;
                        end
                    end
                else
                    if isempty(raw)
                        raw = row;
                    else
                        raw(end + 1) = row;
                    end
                end
                if ~cfg.summaryOnly
                    runRecord = struct('algorithm', name, 'scenario_id', scenarioId, 'seed', scenario.seed, 'best_nest', nest(algCtx, x, ev), 'evaluation', ev, 'iteration_history', h);
                    if isempty(runs)
                        runs = runRecord;
                    else
                        runs(end + 1) = runRecord;
                    end
                end
                fprintf('%s seed=%d %s Q=%.12g NFE=%d\n', cfg.figure, scenario.seed, name, ev.score, nfe);
            end
        end
    end
    if strcmp(cfg.experimentMode, 'fair_optimizer_comparison')
        bad = ~[audit.evaluation_budget_exhausted] & ~strcmp({audit.algorithm}, 'dtosc');
        assert(~any(bad), 'Common NFE budget was not consumed by every optimizer; increase tmax.');
    end
    switch cfg.figure
        case 'figure_6'
            summary = bench.summarize(raw, {'figure', 'algorithm', 'iteration', 'point_type'}, {'total_efficiency'});
        case 'figure_7'
            summary = bench.summarize(raw, {'figure', 'mission_vehicle_count', 'algorithm'}, {'avg_delay', 'avg_efficiency', 'total_efficiency', 'completion_rate'});
        case 'figure_8'
            summary = bench.summarize(raw, {'figure', 'deadline_s', 'deadline_ms', 'algorithm'}, {'avg_delay', 'completion_rate'});
        case 'figure_9'
            summary = bench.summarize(raw, {'figure', 'speed_kmh', 'algorithm'}, {'total_efficiency'});
        case 'figure_10'
            summary = bench.summarize(raw, {'figure', 'mec_capacity_ghz', 'algorithm'}, {'avg_efficiency', 'completion_rate'});
    end
    nfeReport = struct([]);
    if strcmp(cfg.figure, 'figure_6')
        nfeReport = bench.nfeSummary(conv);
    end
    results = struct('figure', cfg.figure, 'configuration', cfg, 'raw', raw, 'summary', summary, 'applications', appRows, 'convergence', conv, 'nfeSummary', nfeReport, 'executionAudit', audit, 'scenarioRecords', records, 'pairwiseStatistics', bench.pairedStatistics(audit, cfg.statisticsMode), 'runs', runs, 'scientificStatus', 'uploaded-Python-parity; article-aligned with declared limitations');

    function v = convergence(type, index, score)
        v = struct('figure', cfg.figure, 'scenario_id', scenarioId, 'algorithm', name, 'seed', scenario.seed, 'iteration', h(j).iteration, 'function_evaluations', nh, 'point_type', type, 'population_index', index, 'total_efficiency', score, 'runtime_seconds', runtime);
    end

end

function v = nest(ctx, x, ev)
    v = struct([]);
    for j = 1:ctx.dimension
        t = ctx.optimTaskIds(j);
        ix = find([ev.schedule.joint_task_id] == t, 1);
        geneRecord = struct('joint_task_id', t, 'provider_id', ctx.providerId(x(j)), 'rank', ev.schedule(ix).rank);
        if isempty(v)
            v = geneRecord;
        else
            v(end + 1) = geneRecord;
        end
    end
end
