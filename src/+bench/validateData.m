function validateData(d)
    expected = struct('B', 20, 'delta2', -114, 'Y_v2i', 3.76, 'Y_v2v', 1.8, 'sigma_v2i', 8, 'sigma_v2v', 3, 'h_rsu', 5, 'h_vehicle', 1.5, 'G_rsu', 8, 'G_vehicle', 3, 'levy_lambda', 1.5, 'p_discard_init', .2, 'S', 50, 'k', 1e-25, 'cell_radius_rsu', 250, 'rec_noi_rsu', 5, 'rec_noi_vehicle', 9, 'pmax_vehicle', 23, 'pmax_rsu', 30, 'fmax_vehicle', 3, 'fmax_rsu', 50, 'vehicle_speed_min_kmh', 60, 'vehicle_speed_max_kmh', 80, 'application_rate_per_second', 10);
    keys = fieldnames(expected);
    for j = 1:numel(keys)
        k = keys{j};
        assert(isfield(d.params, k) && abs(d.params.(k) - expected.(k)) <= max(1e-30, abs(expected.(k)) * 1e-9), 'Table III parameter mismatch: %s', k);
    end
    assert(numel(d.vehicles) >= 76 && numel(d.rsus) >= 5);
    assert(all([d.vehicles.cpu_capacity] == 3e9) && all([d.vehicles.cache_capacity] == 625e6));
    assert(all([d.rsus(1:5).cpu_capacity] == 50e9) && all([d.rsus(1:5).cache_capacity] == 625e6));
    assert(all(ismember(30:10:100, [d.application_types.deadline])));
    for app = reshape(d.application_types, 1, [])
        ts = d.tasks([d.tasks.application_type_id_id] == app.id);
        assert(numel(ts) == 10);
        assert(all([ts.workload_cycles] >= 1e7 & [ts.workload_cycles] <= 3e7));
        for t = reshape(ts, 1, [])
            k = d.task_types([d.task_types.id] == t.task_type_id_id);
            assert(numel(k) == 1);
            assert(k.size * 8 >= 5e8 && k.size * 8 <= 1e9);
            snap = t.initial_snapshot;
            if isfield(snap, 'output_size_bits')
                bits = snap.output_size_bits;
            else
                bits = k.initial_snapshot.communication_data_bits;
            end
            assert(bits >= 1e5 && bits <= 3e5);
        end
    end
    for sp = reshape(d.service_providers, 1, [])
        assert(sum([d.resources.sp_id_id] == sp.id) == 1, 'Provider must have exactly one resource');
    end
end
