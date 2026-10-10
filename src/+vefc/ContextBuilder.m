classdef ContextBuilder
    methods (Static)

        function ctx = build(d, cfg, s)
            if nargin < 3
                s = struct();
            end
            get = @(name, def)vefc.ContextBuilder.pick(s, name, def);
            seed = get('seed', cfg.seedStart);
            A = get('vehicleCount', cfg.vehicleCount);
            R = get('roadVehicleCount', A);
            mec = get('mecCapacityGHz', 50);
            speed = get('speedKmh', []);
            pool = get('poolCount', numel(d.vehicles));
            assignPool = get('assignmentPoolCount', A);
            explicit = isfield(s, 'roadState') || isfield(s, 'assignments');
            if explicit
                assert(isfield(s, 'roadState') && isfield(s, 'assignments'), 'Provide roadState and assignments together');
                A = numel(s.assignments);
                R = numel(s.roadState);
                assignPool = A;
                assert(A > 0 && R >= A);
                pool = numel(d.vehicles);
            end
            vs = d.vehicles;
            [~, ix] = sort([vs.id]);
            vs = vs(ix);
            eligible = [d.service_providers(strcmp({d.service_providers.type}, 'vehicle')).vehicle_id_id];
            vs = vs(ismember([vs.id], eligible));
            assert(pool <= numel(vs) && R <= pool && A <= R);
            baseVs = vs(1:pool);
            rs = d.rsus;
            [~, ix] = sort([rs.id]);
            rs = rs(ix);
            rs = rs(1:5);
            par = d.params;
            lanes = sort(unique(arrayfun(@(v)v.initial_snapshot.lane_x_coord, vs)));
            assert(numel(lanes) == 4 && all(diff(lanes) == 4));
            rngRoad = optim.PythonRandom(seed * 1000003 + 7919);
            selected = rngRoad.shuffle(1:pool);
            selected = selected(1:R);
            roadIds = [baseVs(selected).id];
            position = zeros(R, 2);
            speeds = zeros(R, 1);
            cursor = 1;
            for l = 1:4
                count = floor(R / 4) + (l <= mod(R, 4));
                ys = zeros(1, count);
                for j = 1:count
                    ys(j) = rngRoad.uniform(0, 1000);
                end
                ys = sort(ys);
                for y = ys
                    position(cursor, :) = [lanes(l) y];
                    if isempty(speed)
                        speeds(cursor) = rngRoad.uniform(60, 80);
                    else
                        speeds(cursor) = speed;
                    end
                    cursor = cursor + 1;
                end
            end
            missionRoadIds = roadIds;
            if isfield(s, 'extensionRoadCount') && s.extensionRoadCount > R
                target = s.extensionRoadCount;
                assert(target <= numel(vs));
                extraRng = optim.PythonRandom(seed * 1000003 + 32452843);
                extraIx = find(~ismember([vs.id], roadIds));
                extraIx = extraRng.shuffle(extraIx);
                extraIx = extraIx(1:target - R);
                cursor = 1;
                for l = 1:4
                    count = floor(target / 4) + (l <= mod(target, 4)) - sum(position(:, 1) == lanes(l));
                    for j = 1:count
                        roadIds(end + 1) = vs(extraIx(cursor)).id;
                        position(end + 1, :) = [lanes(l), extraRng.uniform(0, 1000)];
                        if isempty(speed)
                            speeds(end + 1) = extraRng.uniform(60, 80);
                        else
                            speeds(end + 1) = speed;
                        end
                        cursor = cursor + 1;
                    end
                end
                R = target;
            end
            if explicit
                roadIds = [s.roadState.vehicle_id];
                position = [[s.roadState.x]' [s.roadState.y]'];
                speeds = [s.roadState.speed_kmh]';
                missionRoadIds = roadIds;
                assert(numel(unique(roadIds)) == R && all(ismember(roadIds, [vs.id])), 'Unknown or duplicate road vehicles');
            end
            access = zeros(R, 1);
            for i = 1:R
                distance = arrayfun(@(q)vefc.FormulaLibrary.distance3d(position(i, :), par.h_vehicle, [q.x_coord q.y_coord], par.h_rsu), rs);
                [dist, j] = min(distance);
                assert(dist <= par.cell_radius_rsu, 'Vehicle outside RSU cells');
                access(i) = rs(j).id;
            end
            if explicit && isfield(s.roadState, 'rsu_id')
                access = [s.roadState.rsu_id]';
                assert(all(ismember(access, [rs.id])), 'Unknown access RSU');
            end
            sp = d.service_providers;
            mask = strcmp({sp.type}, 'rsu');
            for i = 1:numel(sp)
                if strcmp(sp(i).type, 'vehicle')
                    mask(i) = ismember(sp(i).vehicle_id_id, roadIds);
                end
            end
            sp = sp(mask);
            [~, ix] = sort([sp.id]);
            sp = sp(ix);
            P = numel(sp);
            id = [sp.id]';
            isRsu = strcmp({sp.type}, 'rsu')';
            pos = zeros(P, 2);
            cpu = zeros(P, 1);
            cap = zeros(P, 1);
            vehicle = nan(P, 1);
            rsu = nan(P, 1);
            providerAccess = zeros(P, 1);
            for p = 1:P
                if isRsu(p)
                    row = find([rs.id] == sp(p).rsu_id_id, 1);
                    assert(~isempty(row));
                    rsu(p) = rs(row).id;
                    pos(p, :) = [rs(row).x_coord rs(row).y_coord];
                    cpu(p) = mec * 1e9;
                    cap(p) = rs(row).cache_capacity;
                else
                    row = find(roadIds == sp(p).vehicle_id_id, 1);
                    v = vs(find([vs.id] == roadIds(row), 1));
                    vehicle(p) = v.id;
                    pos(p, :) = position(row, :);
                    cpu(p) = v.cpu_capacity;
                    cap(p) = v.cache_capacity;
                    providerAccess(p) = access(row);
                end
            end
            mr = optim.PythonRandom(seed * 1000033 + 104729);
            pr = optim.PythonRandom(seed * 1000033 + 130363);
            missionOrder = mr.shuffle(missionRoadIds);
            assert(assignPool <= numel(missionOrder));
            missionOrder = missionOrder(1:assignPool);
            at = d.application_types;
            [~, ix] = sortrows([[at.deadline]' [at.id]'], [1 2]);
            at = at(ix);
            dagIds = [at.id];
            assert(numel(dagIds) == 8);
            deadlines = [];
            dw = [5 10 15 20 20 15 10 5];
            for j = 1:8
                deadlines = [deadlines repmat(20 + 10 * j, 1, dw(j))];
            end
            deadlines = pr.shuffle(deadlines);
            dagIds = pr.shuffle(dagIds);
            pairs = zeros(assignPool, 2);
            cursor = 1;
            while cursor <= assignPool
                for j = 1:numel(deadlines)
                    pairs(cursor, :) = [deadlines(j), dagIds(mod(j - 1, 8) + 1)];
                    cursor = cursor + 1;
                    if cursor > assignPool
                        break
                    end
                end
                deadlines = pr.shuffle(deadlines);
                dagIds = pr.shuffle(dagIds);
            end
            if explicit
                rows = s.assignments;
                missionOrder = [rows.vehicle_id];
                pairs = [[rows.deadline_s]' * 1000 [rows.application_type_id]'];
                assert(numel(unique(missionOrder)) == A && all(ismember(missionOrder, roadIds)), 'Mission IDs must be unique and present on road');
                assert(numel(unique([rows.application_id])) == A && all(ismember(pairs(:, 2), [at.id])), 'Invalid application IDs or DAG');
            end
            ctx = struct('seed', seed, 'params', par, 'applicationCount', A, 'providerCount', P, 'providerId', id, 'isRsu', isRsu, 'providerType', {{sp.type}}, 'providerPosition', pos, 'providerCpu', cpu, 'providerCache', cap, 'providerVehicleId', vehicle, 'providerRsuId', rsu, 'roadVehicleIds', roadIds, 'roadPosition', position, 'roadSpeeds', speeds, 'roadAccessRsuId', access, 'missionVehicleId', missionOrder(1:A)', 'applicationId', -(1:A)', 'applicationTypeId', pairs(1:A, 2), 'deadline', pairs(1:A, 1) / 1000, 'useCaching', true, 'mecCapacityGHz', mec);
            if explicit
                ctx.applicationId = [rows.application_id]';
            end
            ctx.localProvider = zeros(A, 1);
            ctx.appDomain = cell(A, 1);
            ctx.radioEndpoint = zeros(A, P);
            ctx.providerShare = zeros(A, P);
            ctx.taskApp = [];
            ctx.taskBaseId = [];
            ctx.taskType = [];
            ctx.cycles = [];
            ctx.outputBits = [];
            ctx.taskIndex = {};
            ctx.predecessor = {};
            ctx.children = {};
            ctx.entryTaskIds = zeros(1, A);
            ctx.naturalOrders = cell(1, A);
            for a = 1:A
                local = find(vehicle == missionOrder(a), 1);
                ctx.localProvider(a) = local;
                ar = providerAccess(local);
                dom = find(isRsu | providerAccess == ar)';
                ctx.appDomain{a} = dom;
                ep = 1:P;
                ep(isRsu) = find(rsu == ar, 1);
                ctx.radioEndpoint(a, :) = ep;
                ctx.providerShare(a, :) = max(1, sum(access == ar));
                ts = d.tasks([d.tasks.application_type_id_id] == pairs(a, 2));
                [~, ix] = sort([ts.id]);
                ts = ts(ix);
                offset = numel(ctx.cycles);
                tids = offset + (1:numel(ts));
                base = [ts.id];
                for j = 1:numel(ts)
                    t = tids(j);
                    ctx.taskApp(t, 1) = a;
                    ctx.taskBaseId(t, 1) = ts(j).id;
                    ctx.taskType(t, 1) = ts(j).task_type_id_id;
                    ctx.cycles(t, 1) = ts(j).workload_cycles;
                    ctx.taskIndex{t} = ts(j).index;
                    snap = ts(j).initial_snapshot;
                    if isfield(snap, 'output_size_bits')
                        ctx.outputBits(t, 1) = fix(snap.output_size_bits);
                    else
                        kind = d.task_types([d.task_types.id] == ts(j).task_type_id_id);
                        ctx.outputBits(t, 1) = fix(kind.initial_snapshot.communication_data_bits);
                    end
                    ctx.predecessor{t} = [];
                    ctx.children{t} = [];
                end
            end
            % Joint provider union excludes road peers outside every mission alliance.
            used = unique([ctx.appDomain{:}]);
            map = zeros(1, P);
            map(used) = 1:numel(used);
            ctx.localProvider = map(ctx.localProvider)';
            for a = 1:A
                ctx.appDomain{a} = map(ctx.appDomain{a});
            end
            ctx.radioEndpoint = reshape(map(ctx.radioEndpoint(:, used)), A, numel(used));
            ctx.providerShare = ctx.providerShare(:, used);
            id = id(used);
            isRsu = isRsu(used);
            pos = pos(used, :);
            cpu = cpu(used);
            cap = cap(used);
            vehicle = vehicle(used);
            rsu = rsu(used);
            sp = sp(used);
            P = numel(used);
            ctx.providerCount = P;
            ctx.providerId = id;
            ctx.isRsu = isRsu;
            ctx.providerType = {sp.type};
            ctx.providerPosition = pos;
            ctx.providerCpu = cpu;
            ctx.providerCache = cap;
            ctx.providerVehicleId = vehicle;
            ctx.providerRsuId = rsu;
            N = numel(ctx.cycles);
            ctx.taskCount = N;
            ctx.edgeBits = zeros(N, N);
            for a = 1:A
                members = find(ctx.taskApp == a)';
                base = ctx.taskBaseId(members);
                for q = 1:numel(d.dependencies)
                    dep = d.dependencies(q);
                    pa = find(base == dep.parent_task_id_id, 1);
                    ch = find(base == dep.child_task_id_id, 1);
                    if isempty(pa) || isempty(ch)
                        continue
                    end
                    p = members(pa);
                    t = members(ch);
                    assert(p ~= t && ~ismember(p, ctx.predecessor{t}));
                    ctx.predecessor{t}(end + 1) = p;
                    ctx.children{p}(end + 1) = t;
                    if isstruct(dep.initial_snapshot) && isfield(dep.initial_snapshot, 'communication_data_bits')
                        bits = dep.initial_snapshot.communication_data_bits;
                    else
                        bits = ctx.outputBits(p);
                    end
                    bits = fix(bits);
                    assert(bits > 0);
                    ctx.edgeBits(p, t) = bits;
                end
                for t = members
                    ctx.predecessor{t} = sort(ctx.predecessor{t});
                    ctx.children{t} = sort(ctx.children{t});
                end
                entry = members(cellfun(@isempty, ctx.predecessor(members)));
                assert(numel(entry) == 1, 'One entry required');
                ctx.entryTaskIds(a) = entry;
                ctx.naturalOrders{a} = vefc.ContextBuilder.topological(ctx, members);
            end
            ctx.entryTask = false(N, 1);
            ctx.entryTask(ctx.entryTaskIds) = true;
            ctx.domain = cell(N, 1);
            for t = 1:N
                ctx.domain{t} = ctx.appDomain{ctx.taskApp(t)};
            end
            K = max([d.task_types.id]);
            ctx.serviceBits = zeros(K, 1);
            ctx.compileCycles = zeros(K, 1);
            for kind = reshape(d.task_types, 1, [])
                k = kind.id;
                ctx.serviceBits(k) = fix(kind.size) * 8;
                ss = kind.initial_snapshot;
                names = {'compile_workload_cycles', 'compile_cycles', 'w_k_cycles', 'W_k', 'Wk'};
                for j = 1:numel(names)
                    if isstruct(ss) && isfield(ss, names{j})
                        ctx.compileCycles(k) = ss.(names{j});
                        break
                    end
                end
            end
            ctx.compileCyclesByApp = repmat(ctx.compileCycles(:)', A, 1);
            for a = 1:A
                app = d.application_types([d.application_types.id] == ctx.applicationTypeId(a));
                snapshot = app.initial_snapshot;
                compileMap = struct();
                if isstruct(snapshot)
                    if isfield(snapshot, 'compile_workloads')
                        compileMap = snapshot.compile_workloads;
                    elseif isfield(snapshot, 'service_compile_workloads')
                        compileMap = snapshot.service_compile_workloads;
                    end
                end
                for k = unique(ctx.taskType(ctx.taskApp == a))'
                    kind = d.task_types([d.task_types.id] == k);
                    ss = kind.initial_snapshot;
                    has = false;
                    for j = 1:numel(names)
                        has = has || (isstruct(ss) && isfield(ss, names{j}) && ~isempty(ss.(names{j})));
                    end
                    if ~has && isstruct(compileMap)
                        key = sprintf('x%d', k);
                        if isfield(compileMap, key)
                            value = compileMap.(key);
                            ctx.compileCyclesByApp(a, k) = value;
                            ctx.compileCycles(k) = value;
                        end
                    end
                end
            end
            ctx.sourceBits = max(1, optim.PythonRandom.roundEven(ctx.serviceBits * 0.1));
            ctx.localTime = zeros(A, 1);
            ctx.localEnergy = zeros(A, 1);
            ctx.referenceTime = zeros(A, 1);
            ctx.modelTref = zeros(A, 1);
            ctx.modelElocal = zeros(A, 1);
            ctx.alpha = zeros(A, 1);
            ctx.beta = zeros(A, 1);
            ctx.allocatedCpu = zeros(A, P);
            for a = 1:A
                cyc = ctx.cycles(ctx.taskApp == a);
                f = cpu(ctx.localProvider(a));
                energyTerms = arrayfun(@(c)par.k * f^2 * c, cyc);
                % Benchmark references use Python sum; library references use explicit +=.
                ctx.localTime(a) = vefc.FormulaLibrary.pythonSum(cyc) / f;
                ctx.localEnergy(a) = vefc.FormulaLibrary.pythonSum(energyTerms);
                ctx.referenceTime(a) = min(ctx.localTime(a), ctx.deadline(a));
                ctx.modelTref(a) = min(vefc.FormulaLibrary.sumOrdered(cyc / f), ctx.deadline(a));
                ctx.modelElocal(a) = vefc.FormulaLibrary.sumOrdered(energyTerms);
                [ctx.alpha(a), ctx.beta(a)] = vefc.FormulaLibrary.articleWeights(ctx.deadline(a));
                for p = ctx.appDomain{a}
                    if isRsu(p)
                        ctx.allocatedCpu(a, p) = cpu(p);
                    else
                        ctx.allocatedCpu(a, p) = vefc.FormulaLibrary.assignedCpuFrequency(ctx.alpha(a), ctx.localEnergy(a), ctx.beta(a), par.k, ctx.referenceTime(a), cpu(p));
                    end
                end
            end
            ctx.bandwidthHz = par.B * 1e6;
            ctx.noiseW = vefc.FormulaLibrary.dbmToWatt(par.delta2);
            ctx.linkTimePerBit = zeros(A, P, P);
            ctx.linkEnergyPerBit = zeros(A, P, P);
            ctx.linkGain = zeros(A, P, P);
            ctx.linkPower = zeros(A, P, P);
            ctx.linkRate = zeros(A, P, P);
            ctx.serviceProgramEnergy = zeros(A, P, K);
            for a = 1:A
                dom = ctx.appDomain{a};
                ep = ctx.radioEndpoint(a, :);
                phys = unique(ep(dom));
                links = [];
                sig = [];
                seeds = [];
                for p = phys
                    for q = phys
                        if p == q || (isRsu(p) && isRsu(q))
                            continue
                        end
                        links(end + 1, :) = [p q];
                        if isRsu(p) || isRsu(q)
                            sig(end + 1) = par.sigma_v2i;
                        else
                            sig(end + 1) = par.sigma_v2v;
                        end
                        seeds(end + 1) = mod(seed * 1000003 + ctx.applicationId(a) * 97409 + id(p) * 9973 + id(q) * 37, 2^32);
                    end
                end
                [shadow, ray] = optim.channelFading(seeds, sig);
                for j = 1:size(links, 1)
                    p = links(j, 1);
                    q = links(j, 2);
                    h1 = par.h_vehicle;
                    h2 = h1;
                    g1 = par.G_vehicle;
                    g2 = g1;
                    if isRsu(p)
                        h1 = par.h_rsu;
                        g1 = par.G_rsu;
                    end
                    if isRsu(q)
                        h2 = par.h_rsu;
                        g2 = par.G_rsu;
                    end
                    distance = vefc.FormulaLibrary.distance3d(pos(p, :), h1, pos(q, :), h2);
                    if isRsu(p) || isRsu(q)
                        loss = vefc.FormulaLibrary.v2iPathLoss(distance);
                    else
                        loss = vefc.FormulaLibrary.v2vPathLoss(distance);
                    end
                    gain = vefc.FormulaLibrary.channelGain(loss, shadow(j), ray(j), g1, g2);
                    mx = vefc.FormulaLibrary.dbmToWatt(par.pmax_vehicle);
                    if isRsu(p)
                        mx = vefc.FormulaLibrary.dbmToWatt(par.pmax_rsu);
                    end
                    power = vefc.FormulaLibrary.optimizeTransmitPower(ctx.alpha(a), ctx.modelTref(a), ctx.beta(a), ctx.modelElocal(a), 1, ctx.bandwidthHz, gain, ctx.noiseW, mx);
                    rate = vefc.FormulaLibrary.uplinkRate(ctx.bandwidthHz, ctx.providerShare(a, p), power, gain, ctx.noiseW);
                    ctx.linkRate(a, p, q) = rate;
                    ctx.linkGain(a, p, q) = gain;
                    ctx.linkPower(a, p, q) = power;
                    ctx.linkTimePerBit(a, p, q) = 1 / rate;
                    if ~isRsu(p)
                        ctx.linkEnergyPerBit(a, p, q) = power / rate;
                    end
                end
                for p = dom
                    for q = dom
                        if p ~= q && ~(isRsu(p) && isRsu(q))
                            ctx.linkRate(a, p, q) = ctx.linkRate(a, ep(p), ep(q));
                            ctx.linkGain(a, p, q) = ctx.linkGain(a, ep(p), ep(q));
                            ctx.linkPower(a, p, q) = ctx.linkPower(a, ep(p), ep(q));
                            ctx.linkTimePerBit(a, p, q) = ctx.linkTimePerBit(a, ep(p), ep(q));
                            ctx.linkEnergyPerBit(a, p, q) = ctx.linkEnergyPerBit(a, ep(p), ep(q));
                        end
                    end
                end
                for p = dom
                    sources = dom(~isRsu(dom)' & dom ~= p);
                    if isempty(sources)
                        continue
                    end
                    for k = unique(ctx.taskType(ctx.taskApp == a))'
                        energies = zeros(size(sources));
                        for j = 1:numel(sources)
                            duration = ctx.sourceBits(k) / ctx.linkRate(a, sources(j), p);
                            energies(j) = ctx.linkPower(a, sources(j), p) * duration;
                        end
                        ctx.serviceProgramEnergy(a, p, k) = min(energies);
                    end
                end
            end
            ctx.initialCache = cell(P, 1);
            ctx.initialProviderFinish = zeros(P, 1);
            ctx.initialLinkFinish = zeros(P, P);
            if isfield(s, 'initialCache')
                for j = 1:numel(s.initialCache)
                    p = find(id == s.initialCache(j).provider_id, 1);
                    assert(~isempty(p), 'Cache provider outside mission domains');
                    ctx.initialCache{p} = sort(unique(s.initialCache(j).task_type_ids(:)'));
                end
            end
            if isfield(s, 'providerQueues')
                for j = 1:numel(s.providerQueues)
                    p = find(id == s.providerQueues(j).provider_id, 1);
                    assert(~isempty(p));
                    ctx.initialProviderFinish(p) = max(0, s.providerQueues(j).finish_s);
                end
            end
            if isfield(s, 'linkQueues')
                for j = 1:numel(s.linkQueues)
                    p = find(id == s.linkQueues(j).source_provider_id, 1);
                    q = find(id == s.linkQueues(j).destination_provider_id, 1);
                    assert(~isempty(p) && ~isempty(q));
                    ctx.initialLinkFinish(p, q) = max(0, s.linkQueues(j).finish_s);
                end
            end
            ctx = vefc.ContextBuilder.rank(ctx);
        end

        function ctx = rank(ctx)
            rank = zeros(ctx.taskCount, 1);
            for a = 1:ctx.applicationCount
                dom = ctx.appDomain{a};
                avgCommRates = [];
                for p = dom
                    for q = dom
                        if p ~= q && ~(ctx.isRsu(p) && ctx.isRsu(q))
                            r = ctx.linkRate(a, p, q);
                            if r > 0
                                avgCommRates(end + 1) = r;
                            end
                        end
                    end
                end
                order = ctx.naturalOrders{a};
                for t = fliplr(order)
                    times = zeros(size(dom));
                    for j = 1:numel(dom)
                        p = dom(j);
                        times(j) = vefc.Evaluator.compute(ctx, a, p, t, ctx.initialCache);
                    end
                    rank(t) = vefc.FormulaLibrary.pythonSum(times) / numel(dom);
                    best = 0;
                    for ch = ctx.children{t}
                        comm = 0;
                        if ~isempty(avgCommRates)
                            comm = vefc.FormulaLibrary.pythonSum(ctx.edgeBits(t, ch) ./ avgCommRates) / numel(avgCommRates);
                        end
                        best = max(best, comm + rank(ch));
                    end
                    rank(t) = rank(t) + best;
                end
            end
            ctx.rankValue = rank;
            ctx.globalRank = rank + max(ctx.deadline) - ctx.deadline(ctx.taskApp);
            optimized = find(~ctx.entryTask);
            [~, ix] = sortrows([-ctx.globalRank(optimized) optimized], [1 2]);
            ctx.optimTaskIds = optimized(ix)';
            ctx.dimension = numel(optimized);
            ctx.scheduleOrder = [ctx.entryTaskIds ctx.optimTaskIds];
            ctx.unrankedTaskIds = [];
            maxlen = max(cellfun(@numel, ctx.naturalOrders));
            for j = 2:maxlen
                for a = 1:ctx.applicationCount
                    ord = ctx.naturalOrders{a};
                    ord = ord(ord ~= ctx.entryTaskIds(a));
                    if j - 1 <= numel(ord)
                        ctx.unrankedTaskIds(end + 1) = ord(j - 1);
                    end
                end
            end
        end

        function order = topological(ctx, members)
            indeg = zeros(ctx.taskCount, 1);
            for t = members
                indeg(t) = numel(ctx.predecessor{t});
            end
            ready = sort(members(indeg(members) == 0));
            order = [];
            while ~isempty(ready)
                t = ready(1);
                ready(1) = [];
                order(end + 1) = t;
                for ch = ctx.children{t}
                    indeg(ch) = indeg(ch) - 1;
                    if indeg(ch) == 0
                        ready = sort([ready ch]);
                    end
                end
            end
            assert(numel(order) == numel(members), 'Cyclic DAG');
        end

        function v = pick(s, n, f)
            if isfield(s, n)
                v = s.(n);
            else
                v = f;
            end
        end

    end
end
