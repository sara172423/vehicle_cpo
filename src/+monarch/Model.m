classdef Model
    % Function-name-preserving port of every monarch_pylib.model function.
    methods (Static)

        function y = assigned_cpu_frequency(z, fstar, fmax)
            y = 0;
            if z > 0
                y = min(z * fstar, fmax);
            end
        end

        function y = tx_power_aux_function(z, a, b, T, E, p, h, n)
            y = 0;
            if z <= 0 || T <= 0 || E <= 0 || h <= 0 || n <= 0 || p < 0
                return
            end
            y = z * (b / E) * log2(1 + p * h / n) - z * (a / T + b / E * p) * (h / (log(2) * (n + p * h)));
        end

        function y = tx_power_aux_derivative(z, a, b, T, E, p, h, n)
            y = 0;
            if z <= 0 || T <= 0 || E <= 0 || h <= 0 || n <= 0 || p < 0
                return
            end
            y = z * h^2 * (a / T + b / E * p) / (log(2) * (n + p * h)^2);
        end

        function y = tx_power_aux_at_zero(z, a, T, h, n)
            y = 0;
            if z <= 0 || T <= 0 || h <= 0 || n <= 0
                return
            end
            y = -(z * a * h) / (log(2) * n * T);
        end

        function y = cache_state_update_constraint(u, z, v)
            y = u + z * v;
        end

        function y = cache_capacity_used(u, L)
            n = min(numel(u), numel(L));
            y = 0;
            for i = 1:n
                y = y + u(i) * L(i);
            end
        end

        function y = cache_capacity_constraint(u, L, maxL)
            y = double(monarch.Model.cache_capacity_used(u, L) <= maxL);
        end

        function y = local_task_compute_time(C, f)
            y = 0;
            if C > 0 && f > 0
                y = C / f;
            end
        end

        function y = local_task_compute_energy(k, f, C)
            y = 0;
            if k > 0 && f > 0 && C > 0
                y = k * f^2 * C;
            end
        end

        function y = v2v_service_compile_time(v, u, W, f)
            y = 0;
            if f > 0
                y = monarch.Model.setup_cycles(v, u, W) / f;
            end
        end

        function y = v2v_task_processing_time(C, f)
            y = monarch.Model.local_task_compute_time(C, f);
        end

        function y = v2v_task_total_compute_time(t1, t2)
            y = max(0, t1) + max(0, t2);
        end

        function y = v2v_task_compute_energy(k, v, u, W, f, C)
            y = 0;
            if k <= 0 || f <= 0
                return
            end
            setup = k * f^2 * monarch.Model.setup_cycles(v, u, W);
            proc = 0;
            if C > 0
                proc = k * f^2 * C;
            end
            y = setup + proc;
        end

        function y = mec_task_compute_time(v, u, W, f, C)
            y = 0;
            if f <= 0
                return
            end
            setup = monarch.Model.setup_cycles(v, u, W) / f;
            proc = 0;
            if C > 0
                proc = C / f;
            end
            y = setup + proc;
        end

        function y = solution_distance_bound(d)
            d = max(0, fix(d));
            y = [d 2 * d];
        end

        function y = reference_time(T, ddl)
            if T <= 0 && ddl <= 0
                y = 0;
            elseif T <= 0
                y = max(0, ddl);
            elseif ddl <= 0
                y = max(0, T);
            else
                y = min(T, ddl);
            end
        end

        function y = all_local_execution_time(C, f)
            y = 0;
            if f <= 0
                return
            end
            for c = C(:)'
                if c > 0
                    y = y + c / f;
                end
            end
        end

        function y = all_local_execution_energy(k, C, f)
            y = 0;
            if k <= 0 || f <= 0
                return
            end
            for c = C(:)'
                if c > 0
                    y = y + k * f^2 * c;
                end
            end
        end

        function y = offloaded_completion_time(times, z)
            y = 0;
            n = min(monarch.Model.row_count(times), monarch.Model.row_count(z));
            selected = [];
            for i = 1:n
                selected(end + 1) = monarch.Model.dot_ordered(monarch.Model.row(times, i), monarch.Model.row(z, i));
            end
            if ~isempty(selected)
                y = max(selected);
            end
        end

        function y = offloaded_total_energy(energies, z)
            y = 0;
            n = min(monarch.Model.row_count(energies), monarch.Model.row_count(z));
            for i = 1:n
                e = monarch.Model.row(energies, i);
                r = monarch.Model.row(z, i);
                for j = 1:min(numel(e), numel(r))
                    y = y + r(j) * e(j);
                end
            end
        end

        function y = application_offloading_efficiency(a, b, T, to, E, eo)
            y = 0;
            if T <= 0 || E <= 0
                return
            end
            y = a * ((T - to) / T) + b * ((E - eo) / E);
        end

        function y = single_task_efficiency(a, b, T, finish, E, eo)
            y = monarch.Model.application_offloading_efficiency(a, b, T, finish, E, eo);
        end

        function y = cache_keep_state_rule(u)
            y = u;
        end

        function y = cache_service_value_score(C, v, mu, denC, denV)
            y = 0;
            numerator = monarch.Model.dot_ordered(C, v);
            den = (mu + 1) * monarch.Model.dot_ordered(denC, denV);
            if den > 0
                y = numerator / den;
            end
        end

        function y = task_offload_decision(id, local, v2v, v2i)
            y = double(double(logical(local)) + double(logical(v2v)) + double(logical(v2i)) == 1);
        end

        function y = dependency_output_receive_time(src, sameFinish, idle, tx, same)
            if same
                y = sameFinish;
            else
                y = max(src, idle) + max(0, tx);
            end
        end

        function y = task_finish_timestamp(start, compute)
            y = start + max(0, compute);
        end

        function y = all_dependencies_receive_time(v)
            y = 0;
            if ~isempty(v)
                y = max(v);
            end
        end

        function y = task_start_timestamp(deps, prev)
            y = max(deps, prev);
        end

        function y = provider_rank_finish_time(times, z)
            y = monarch.Model.dot_ordered(z, times);
        end

        function y = heft_task_local_rank(t, comm, ranks)
            n = min(numel(comm), numel(ranks));
            best = 0;
            for i = 1:n
                best = max(best, comm(i) + ranks(i));
            end
            y = t + best;
        end

        function y = heft_task_global_rank(local, maxD, ddl)
            y = local + maxD - ddl;
        end

        function y = channel_gain_v2i(tau, rho, varpi, d, gamma)
            y = 0;
            if d > 0
                y = tau * rho * varpi * d^(-gamma);
            end
        end

        function y = v2i_uplink_rate(B, V, p, h, n)
            y = 0;
            if B <= 0 || V <= 0 || n <= 0
                return
            end
            snr = p * h / n;
            if snr > 0
                y = B / V * log2(1 + snr);
            end
        end

        function y = intermediate_data_tx_time(bits, rate)
            y = 0;
            if bits > 0 && rate > 0
                y = bits / rate;
            end
        end

        function y = intermediate_data_tx_energy(power, time)
            y = 0;
            if power > 0 && time > 0
                y = power * time;
            end
        end

        function y = distance_3d(x1, y1, h1, x2, y2, h2)
            dx = x1 - x2;
            dy = y1 - y2;
            dh = h1 - h2;
            y = (dx * dx + dy * dy + dh * dh)^.5;
        end

        function y = distance_2d(x1, y1, x2, y2)
            dx = x1 - x2;
            dy = y1 - y2;
            y = (dx * dx + dy * dy)^.5;
        end

        function y = distance_1d(x1, x2)
            y = abs(x1 - x2);
        end

        function y = speed_vehicle(L, T)
            y = 0;
            if T > 0
                y = L / T;
            end
        end

        function y = current_position(total, now, path)
            assert(~isempty(path), 'path_xy is empty');
            if size(path, 1) == 1 || total <= 0
                y = path(1, :);
                return
            end
            p = now / total;
            if p <= 0
                y = path(1, :);
                return
            elseif p >= 1
                y = path(end, :);
                return
            end
            lens = zeros(1, size(path, 1) - 1);
            L = 0;
            for i = 1:numel(lens)
                dx = path(i + 1, 1) - path(i, 1);
                dy = path(i + 1, 2) - path(i, 2);
                lens(i) = (dx * dx + dy * dy)^.5;
                L = L + lens(i);
            end
            if L <= 0
                y = path(1, :);
                return
            end
            d = p * L;
            acc = 0;
            for i = 1:numel(lens)
                if d <= acc + lens(i) || i == numel(lens)
                    if lens(i) <= 0
                        y = path(i, :);
                    else
                        r = (d - acc) / lens(i);
                        y = [path(i, 1) + r * (path(i + 1, 1) - path(i, 1)), path(i, 2) + r * (path(i + 1, 2) - path(i, 2))];
                    end
                    return
                end
                acc = acc + lens(i);
            end
            y = path(end, :);
        end

        function y = path_length_2d(path)
            y = 0;
            for i = 1:size(path, 1) - 1
                dx = path(i + 1, 1) - path(i, 1);
                dy = path(i + 1, 2) - path(i, 2);
                y = y + (dx * dx + dy * dy)^.5;
            end
        end

    end
    methods (Static, Access = private)

        function n = row_count(x)
            if iscell(x)
                n = numel(x);
            else
                n = size(x, 1);
            end
        end

        function y = row(x, i)
            if iscell(x)
                y = x{i};
            else
                y = x(i, :);
            end
        end

        function s = setup_cycles(v, u, W)
            s = 0;
            for i = 1:min([numel(v), numel(u), numel(W)])
                need = v(i) * (1 - u(i));
                if need > 0 && W(i) > 0
                    s = s + need * W(i);
                end
            end
        end

        function s = dot_ordered(x, y)
            s = 0;
            for i = 1:min(numel(x), numel(y))
                s = s + x(i) * y(i);
            end
        end

    end
end
