function result = run_snapshot(snapshot, algorithm, cfg, providerIds)
    % Run an explicit frozen road/application instance, or score a fixed assignment.
    % snapshot: struct or JSON filename. Actual provider IDs are used at the boundary.
    startup;
    if nargin < 2
        algorithm = 'cpo';
    end
    if nargin < 3
        cfg = defaultConfig();
    else
        base = defaultConfig();
        fields = fieldnames(cfg);
        for j = 1:numel(fields)
            assert(isfield(base, fields{j}), 'Unknown config field');
            base.(fields{j}) = cfg.(fields{j});
        end
        cfg = base;
    end
    if ischar(snapshot) || isstring(snapshot)
        snapshot = jsondecode(fileread(snapshot));
    end
    if isfield(snapshot, 'seed')
        cfg.seedStart = snapshot.seed;
    else
        snapshot.seed = cfg.seedStart;
    end
    assert(cfg.populationSize >= 1 && cfg.tmax >= 1);
    if ~isempty(cfg.maxFunctionEvaluations)
        assert(cfg.maxFunctionEvaluations >= cfg.populationSize);
    end
    d = dataio.loadDataset(cfg.dataDir);
    ctx = vefc.ContextBuilder.build(d, cfg, snapshot);
    if nargin >= 4
        providerIds = providerIds(:)';
        assert(numel(providerIds) == ctx.dimension, 'One provider per ranked non-entry task is required');
        [found, x] = ismember(providerIds, ctx.providerId);
        assert(all(found), 'Unknown provider');
        for j = 1:ctx.dimension
            assert(ismember(x(j), ctx.domain{ctx.optimTaskIds(j)}), 'Infeasible fixed assignment');
        end
        ev = vefc.Evaluator.evaluate(ctx, x);
        history = struct([]);
    else
        [x, ev, history, ctx] = bench.runAlgorithm(algorithm, ctx, cfg);
    end
    result = struct('algorithm', char(algorithm), 'context', ctx, 'jointTaskIds', ctx.optimTaskIds, 'providerIds', ctx.providerId(x)', 'evaluation', ev, 'history', history);
end
