function cfg = validateConfig(cfg, d)
    base = defaultConfig();
    keys = fieldnames(cfg);
    for j = 1:numel(keys)
        assert(isfield(base, keys{j}), 'Unknown configuration field: %s', keys{j});
        base.(keys{j}) = cfg.(keys{j});
    end
    cfg = base;
    f = lower(strrep(strrep(char(cfg.figure), '-', '_'), ' ', '_'));
    aliases = {'6', '7', '8', '9', '10', 'fig6', 'fig7', 'fig8', 'fig9', 'fig10'};
    ix = find(strcmp(f, aliases), 1);
    if ~isempty(ix)
        f = sprintf('figure_%d', 6 + mod(ix - 1, 5));
    end
    if strcmp(f, '*')
        f = 'all';
    end
    assert(ismember(f, {'figure_6', 'figure_7', 'figure_8', 'figure_9', 'figure_10', 'all'}));
    assert(ismember(char(cfg.statisticsMode), {'scipy_1_17', 'none'}), 'Invalid statisticsMode');
    cfg.figure = f;
    paper = {{'dcsga'}, {'dcsga', 'dtosc', 'to_v2i', 'to_wo_c', 'to_wo_r'}, {'dcsga', 'to_wo_c', 'to_wo_r'}, {'dcsga', 'dtosc'}, {'dcsga', 'dtosc'}};
    idx = 1;
    if ~strcmp(f, 'all')
        idx = str2double(f(8:end)) - 5;
    end
    if isempty(cfg.algorithms)
        cfg.algorithms = paper{idx};
    elseif ischar(cfg.algorithms)
        cfg.algorithms = {cfg.algorithms};
    elseif ~iscell(cfg.algorithms)
        cfg.algorithms = cellstr(cfg.algorithms);
    end
    for j = 1:numel(cfg.algorithms)
        cfg.algorithms{j} = lower(char(cfg.algorithms{j}));
        if strcmp(cfg.algorithms{j}, 'cuckoo')
            cfg.algorithms{j} = 'dcsga';
        end
    end
    cfg.algorithms = unique(cfg.algorithms, 'stable');
    added = {'cpo', 'dcpo_base', 'dcpo_cache', 'dcpo_criticality', 'gpc', 'gwo', 'gwo_aco', 'puma'};
    valid = [paper{2} added];
    assert(all(ismember(cfg.algorithms, valid)), 'Unsupported algorithm');
    hasAdded = any(ismember(cfg.algorithms, added));
    if isempty(cfg.experimentMode)
        if hasAdded
            cfg.experimentMode = 'fair_optimizer_comparison';
        else
            cfg.experimentMode = 'paper_reproduction';
        end
    end
    assert(ismember(cfg.experimentMode, {'paper_reproduction', 'fair_optimizer_comparison'}));
    if strcmp(cfg.experimentMode, 'paper_reproduction')
        assert(all(ismember(cfg.algorithms, paper{idx})), 'Paper mode accepts only algorithms printed in that figure');
        assert(isempty(cfg.maxFunctionEvaluations), 'Paper mode uses tmax; remove NFE cap');
    else
        assert(hasAdded, 'Fair mode must include an added optimizer');
        assert(~isempty(cfg.maxFunctionEvaluations), 'Fair comparison requires a common NFE cap');
        assert(~strcmp(f, 'all'), 'Fair comparisons target one figure');
    end
    if isempty(cfg.repetitions) && ~strcmp(f, 'all')
        cfg.repetitions = 1;
        if strcmp(f, 'figure_8')
            cfg.repetitions = 100;
        end
    end
    assert((strcmp(f, 'all') && isempty(cfg.repetitions)) || (cfg.repetitions >= 1 && fix(cfg.repetitions) == cfg.repetitions));
    assert(cfg.populationSize >= 2 && fix(cfg.populationSize) == cfg.populationSize);
    assert(cfg.tmax >= 1 && fix(cfg.tmax) == cfg.tmax);
    assert(isfinite(cfg.seedStart) && fix(cfg.seedStart) == cfg.seedStart && abs(cfg.seedStart) < 2^53);
    assert(isempty(cfg.maxFunctionEvaluations) || (cfg.maxFunctionEvaluations >= cfg.populationSize && isfinite(cfg.maxFunctionEvaluations) && fix(cfg.maxFunctionEvaluations) == cfg.maxFunctionEvaluations));
    if any(ismember(cfg.algorithms, {'gwo', 'gwo_aco'}))
        assert(cfg.populationSize >= 3);
    end
    if strcmp(f, 'figure_6')
        assert(~ismember('dtosc', cfg.algorithms), 'DTOSC has no population convergence');
    end
    if ~isempty(cfg.diagnosticVehicleCount)
        assert(ismember(f, {'figure_6', 'figure_7'}) && all(isfinite(cfg.diagnosticVehicleCount)) && all(fix(cfg.diagnosticVehicleCount) == cfg.diagnosticVehicleCount) && all(cfg.diagnosticVehicleCount >= 2) && all(cfg.diagnosticVehicleCount <= 76));
    end
    if strcmp(f, 'figure_6') && ~isempty(cfg.diagnosticVehicleCount)
        assert(isscalar(cfg.diagnosticVehicleCount));
    end
    if ~isempty(cfg.diagnosticRoadVehicleCount)
        assert(~ismember(f, {'figure_9', 'all'}) && cfg.diagnosticRoadVehicleCount >= 2 && cfg.diagnosticRoadVehicleCount <= min(96, numel(d.vehicles)));
    end
    if ~isempty(cfg.diagnosticSweepValues)
        assert(ismember(f, {'figure_9', 'figure_10'}));
        allowed = [30 40 50 60 70 80];
        if strcmp(f, 'figure_9')
            allowed = [75 80 85 90 95 100 105];
        end
        assert(all(ismember(cfg.diagnosticSweepValues, allowed)));
        cfg.diagnosticSweepValues = unique(cfg.diagnosticSweepValues, 'stable');
    end
    if strcmp(f, 'all')
        assert(isempty(cfg.diagnosticVehicleCount) && isempty(cfg.diagnosticRoadVehicleCount) && isempty(cfg.diagnosticSweepValues));
    end
    bench.validateData(d);
end
