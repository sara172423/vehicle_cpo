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
    assert(ismember(f, {'figure_6', 'figure_7', 'figure_8', 'figure_9', 'figure_10', 'all'}), 'Unsupported figure');
    assert(ismember(char(cfg.statisticsMode), {'scipy_1_17', 'none'}), 'Invalid statisticsMode');
    cfg.figure = f;

    % Supported optimizer family after cleanup:
    % Cuckoo/DCSGA, full/ablated CPO, GPC, GWO and Puma.
    if isempty(cfg.algorithms)
        cfg.algorithms = {'dcsga'};
    elseif ischar(cfg.algorithms) || isstring(cfg.algorithms)
        cfg.algorithms = cellstr(cfg.algorithms);
    elseif ~iscell(cfg.algorithms)
        error('algorithms must be a char/string or cell array');
    end
    for j = 1:numel(cfg.algorithms)
        cfg.algorithms{j} = lower(char(cfg.algorithms{j}));
        if strcmp(cfg.algorithms{j}, 'cuckoo')
            cfg.algorithms{j} = 'dcsga';
        end
    end
    cfg.algorithms = unique(cfg.algorithms, 'stable');
    validAlgorithms = {'dcsga', 'cpo', 'dcpo_base', 'dcpo_criticality', 'dcpo_cache', 'gpc', 'gwo', 'puma'};
    assert(all(ismember(cfg.algorithms, validAlgorithms)), 'Unsupported algorithm');

    % Only two active scientific fitnesses are retained.
    if ischar(cfg.fitnesses) || isstring(cfg.fitnesses)
        cfg.fitnesses = cellstr(cfg.fitnesses);
    elseif ~iscell(cfg.fitnesses)
        error('fitnesses must be a char/string or cell array');
    end
    for j = 1:numel(cfg.fitnesses)
        cfg.fitnesses{j} = lower(char(cfg.fitnesses{j}));
    end
    cfg.fitnesses = unique(cfg.fitnesses, 'stable');
    assert(~isempty(cfg.fitnesses), 'At least one fitness must be selected');
    allowedFitnesses = {'fitness_1', 'fitness_load_aware'};
    assert(all(ismember(cfg.fitnesses, allowedFitnesses)), ...
        'Unsupported fitness ID. Use fitness_1 or fitness_load_aware.');
    assert(isscalar(cfg.loadAwareWeight) && isfinite(cfg.loadAwareWeight) && ...
        cfg.loadAwareWeight >= 0 && cfg.loadAwareWeight < 1, ...
        'loadAwareWeight must be in [0,1)');

    % Auto mode: exact DCSGA + base fitness without NFE means paper mode;
    % every other experiment is a fair common-NFE comparison.
    if isempty(cfg.experimentMode)
        if isequal(cfg.algorithms, {'dcsga'}) && ...
                isequal(cfg.fitnesses, {'fitness_1'}) && isempty(cfg.maxFunctionEvaluations)
            cfg.experimentMode = 'paper_reproduction';
        else
            cfg.experimentMode = 'fair_optimizer_comparison';
        end
    end
    assert(ismember(cfg.experimentMode, {'paper_reproduction', 'fair_optimizer_comparison'}), ...
        'Invalid experimentMode');

    if strcmp(cfg.experimentMode, 'paper_reproduction')
        assert(isequal(cfg.algorithms, {'dcsga'}), ...
            'Paper reproduction uses the DCSGA/Cuckoo baseline only');
        assert(isequal(cfg.fitnesses, {'fitness_1'}), ...
            'Paper reproduction must use fitness_1 only');
        assert(isempty(cfg.maxFunctionEvaluations), ...
            'Paper reproduction uses tmax; remove the NFE cap');
    else
        assert(~isempty(cfg.maxFunctionEvaluations), ...
            'Fair optimizer comparison requires a common maxFunctionEvaluations');
        assert(~strcmp(f, 'all'), 'Fair comparisons target one figure at a time');
    end

    if isempty(cfg.repetitions) && ~strcmp(f, 'all')
        cfg.repetitions = 1;
        if strcmp(f, 'figure_8')
            cfg.repetitions = 100;
        end
    end
    assert((strcmp(f, 'all') && isempty(cfg.repetitions)) || ...
        (cfg.repetitions >= 1 && fix(cfg.repetitions) == cfg.repetitions));
    assert(cfg.populationSize >= 2 && fix(cfg.populationSize) == cfg.populationSize);
    assert(cfg.tmax >= 1 && fix(cfg.tmax) == cfg.tmax);
    assert(isfinite(cfg.seedStart) && fix(cfg.seedStart) == cfg.seedStart && abs(cfg.seedStart) < 2^53);
    assert(isnumeric(cfg.deadlineSamplingWeights) && numel(cfg.deadlineSamplingWeights) == 8 && ...
        all(isfinite(cfg.deadlineSamplingWeights)) && all(cfg.deadlineSamplingWeights >= 0) && ...
        all(fix(cfg.deadlineSamplingWeights) == cfg.deadlineSamplingWeights) && ...
        sum(cfg.deadlineSamplingWeights) > 0, ...
        'deadlineSamplingWeights must be eight nonnegative integer weights for 30:10:100 ms');
    cfg.deadlineSamplingWeights = reshape(cfg.deadlineSamplingWeights, 1, []);
    assert(isscalar(cfg.sourceProgramFraction) && isfinite(cfg.sourceProgramFraction) && ...
        cfg.sourceProgramFraction > 0, 'sourceProgramFraction must be a positive scalar');
    assert(isempty(cfg.maxFunctionEvaluations) || ...
        (cfg.maxFunctionEvaluations >= cfg.populationSize && isfinite(cfg.maxFunctionEvaluations) && ...
         fix(cfg.maxFunctionEvaluations) == cfg.maxFunctionEvaluations));
    if any(strcmp(cfg.algorithms, 'gwo'))
        assert(cfg.populationSize >= 3, 'GWO requires populationSize >= 3');
    end

    if ~isempty(cfg.diagnosticVehicleCount)
        assert(ismember(f, {'figure_6', 'figure_7'}) && ...
            all(isfinite(cfg.diagnosticVehicleCount)) && ...
            all(fix(cfg.diagnosticVehicleCount) == cfg.diagnosticVehicleCount) && ...
            all(cfg.diagnosticVehicleCount >= 2) && all(cfg.diagnosticVehicleCount <= 76));
    end
    if strcmp(f, 'figure_6') && ~isempty(cfg.diagnosticVehicleCount)
        assert(isscalar(cfg.diagnosticVehicleCount));
    end
    if ~isempty(cfg.diagnosticRoadVehicleCount)
        assert(~ismember(f, {'figure_9', 'all'}) && ...
            cfg.diagnosticRoadVehicleCount >= 2 && ...
            cfg.diagnosticRoadVehicleCount <= min(96, numel(d.vehicles)));
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
        assert(isempty(cfg.diagnosticVehicleCount) && ...
            isempty(cfg.diagnosticRoadVehicleCount) && isempty(cfg.diagnosticSweepValues));
    end
    bench.validateData(d);
end
