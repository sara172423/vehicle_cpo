function list = scenarios(cfg, available)
    f = char(cfg.figure);
    list = struct([]);
    diag = cfg.diagnosticVehicleCount;
    road = cfg.diagnosticRoadVehicleCount;
    sweep = cfg.diagnosticSweepValues;
    switch f
        case 'figure_6'
            n = 76;
            if ~isempty(diag)
                n = diag;
            end
            list = make('iteration', cfg.tmax - 1, n, n, n, n, [], 50);
            if ~isempty(road)
                assert(road >= n);
                list.extensionRoadCount = road;
            end
        case 'figure_7'
            values = [52 56 60 64 68 72 76];
            if ~isempty(diag)
                values = diag;
            end
            for j = 1:numel(values)
                scenarioRecord = make('mission_vehicle_count', values(j), values(j), 76, available, max(values), [], 50);
                if isempty(list)
                    list = scenarioRecord;
                else
                    list(j) = scenarioRecord;
                end
                if ~isempty(road)
                    assert(road >= max(values));
                    list(j).extensionRoadCount = road;
                end
            end
        case 'figure_8'
            list = make('deadline_s', 0, 68, 68, 68, 68, [], 50);
            if ~isempty(road)
                assert(road >= 68);
                list.extensionRoadCount = road;
            end
        case 'figure_9'
            values = [75 80 85 90 95 100 105];
            pool = min(available, max(optim.PythonRandom.roundEven(4 * 1000 ./ (2.5 * values / 3.6))));
            if ~isempty(sweep)
                values = sweep;
            end
            for j = 1:numel(values)
                n = min(pool, optim.PythonRandom.roundEven(4 * 1000 / (2.5 * values(j) / 3.6)));
                scenarioRecord = make('speed_kmh', values(j), n, n, pool, n, values(j), 50);
                if isempty(list)
                    list = scenarioRecord;
                else
                    list(j) = scenarioRecord;
                end
            end
        case 'figure_10'
            values = [30 40 50 60 70 80];
            if ~isempty(sweep)
                values = sweep;
            end
            for j = 1:numel(values)
                scenarioRecord = make('mec_capacity_ghz', values(j), 68, 68, 68, 68, [], values(j));
                if isempty(list)
                    list = scenarioRecord;
                else
                    list(j) = scenarioRecord;
                end
                if ~isempty(road)
                    assert(road >= 68);
                    list(j).extensionRoadCount = road;
                end
            end
        otherwise
            error('Unsupported figure %s', f);
    end
    for j = 1:numel(list)
        assert(list(j).poolCount <= available && list(j).extensionRoadCount <= available);
    end
end

function s = make(param, val, A, R, pool, assign, speed, mec)
    s = struct('sweepParameter', param, 'sweepValue', val, 'vehicleCount', A, 'roadVehicleCount', R, 'poolCount', pool, 'assignmentPoolCount', assign, 'speedKmh', speed, 'mecCapacityGHz', mec, 'extensionRoadCount', R);
end
