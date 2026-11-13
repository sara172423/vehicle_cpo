function plots(results, cfg)
    % Plot/export only. This file does not modify any optimizer, evaluator,
    % metric, seed, or numeric result. Completion-rate values remain stored
    % as fractions in [0,1]; they are displayed as percentages in figures.

    out = char(cfg.outputDir);
    if ~isfolder(out)
        mkdir(out);
    end

    % Different fitness definitions can have different numerical score scales.
    % When several fitnesses are requested in one experiment, export one plot
    % set per fitness instead of drawing incomparable objective scales together.
    if isfield(results.raw, 'fitness_id') && ~isempty(results.raw)
        ids = unique({results.raw.fitness_id}, 'stable');
        if numel(ids) > 1
            for q = 1:numel(ids)
                id = ids{q};
                sub = results;
                sub.raw = selectFitness(results.raw, id);
                sub.summary = selectFitness(results.summary, id);
                sub.convergence = selectFitness(results.convergence, id);
                sub.nfeSummary = selectFitness(results.nfeSummary, id);
                c = cfg;
                c.outputDir = fullfile(out, id);
                bench.plots(sub, c);
            end
            return
        end
    end

    rows = results.summary;

    switch results.figure
        case 'figure_6'
            f = newFigure([100 100 1000 720]);
            hold on;
            names = unique({results.raw.algorithm}, 'stable');
            for i = 1:numel(names)
                r = results.raw(strcmp({results.raw.algorithm}, names{i}) & strcmp({results.raw.point_type}, 'population'));
                st = algorithmStyle(names{i}, i);
                plot([r.iteration], [r.total_efficiency], '.', ...
                     'MarkerSize', 9, 'Color', st.color, 'DisplayName', label(names{i}));
            end
            last = max([results.raw.iteration]);
            set(gca, 'XTick', 0:max(1, ceil(last / 10)):last);
            xlabel('Number of iterations');
            if isfield(results.raw, 'fitness_id') && ~isempty(results.raw) && ~strcmp(results.raw(1).fitness_id, 'fitness_1')
                ylabel('Optimization score');
            else
                ylabel('Total offloading efficiency');
            end
            finishAxes(gca);
            legend('Location', 'best', 'Box', 'off');
            saveFigure(f, out, 'figure_6');
            close(f);

            f = newFigure([100 100 1000 650]);
            n = results.nfeSummary;
            yLabel = 'Best-so-far total offloading efficiency';
            if ~isempty(n) && isfield(n, 'fitness_id') && ~strcmp(n(1).fitness_id, 'fitness_1')
                yLabel = 'Best-so-far optimization score';
            end
            panel(n, 'function_evaluations', 'best_total_efficiency', ...
                  'Objective function evaluations (NFE)', yLabel);
            saveFigure(f, out, 'figure_6_nfe');
            close(f);
            return

        case 'figure_7'
            f = newFigure([100 100 1080 790]);
            t = tiledlayout(f, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

            ax = nexttile(t, 1);
            panel(rows, 'mission_vehicle_count', 'avg_delay', ...
                  'Number of vehicles', 'Average delay (s)');
            ylim(ax, [0.02 0.07]);
            yticks(ax, 0.02:0.01:0.07);
            title(ax, '(a)', 'FontWeight', 'normal');

            ax = nexttile(t, 2);
            panel(rows, 'mission_vehicle_count', 'avg_efficiency', ...
                  'Number of vehicles', 'Average offloading efficiency');
            ylim(ax, [0 0.6]);
            yticks(ax, 0:0.1:0.6);
            title(ax, '(b)', 'FontWeight', 'normal');

            ax = nexttile(t, 3);
            panel(rows, 'mission_vehicle_count', 'total_efficiency', ...
                  'Number of vehicles', 'Total offloading efficiency');
            ylim(ax, [0 40]);
            yticks(ax, 0:10:40);
            title(ax, '(c)', 'FontWeight', 'normal');

            ax = nexttile(t, 4);
            panel(rows, 'mission_vehicle_count', 'completion_rate', ...
                  'Number of vehicles', 'Completion rate (%)');
            applyCompletionAxis(ax, [rows.completion_rate], 'figure_7');
            title(ax, '(d)', 'FontWeight', 'normal');

        case 'figure_11'
            % Original research extension, NOT a figure of Shen et al. (2025).
            % X: mission vehicles (same scenario sweep as paper Figure 7).
            % Y: Jain fairness of total MEC busy time. Higher is more even.
            % Multi-fitness output is already split into separate directories
            % by selectFitness() above; never mix raw optimizer scores.
            f = newFigure([100 100 1180 720]);
            ax = axes('Parent', f, 'Position', [.095 .18 .72 .71]);
            hold(ax, 'on');
            names = unique({rows.algorithm}, 'stable');
            counts = sort(unique([rows.mission_vehicle_count]));
            handles = gobjects(1, numel(names));
            anyNoMec = false;
            for i = 1:numel(names)
                r = rows(strcmp({rows.algorithm}, names{i}));
                [~, ix] = sort([r.mission_vehicle_count]);
                r = r(ix);
                st = algorithmStyle(names{i}, i);

                % Uncertainty: mean +/- one sample standard deviation across
                % independent repetitions. No error bar for a single seed.
                if isfield(r, 'load_jain_std') && isfield(r, 'sample_count')
                    enough = [r.sample_count] > 1;
                    if any(enough)
                        values = [r.load_jain];
                        spread = [r.load_jain_std];
                        spread(~enough) = 0;
                        whiskerColor = 0.65 * [1 1 1] + 0.35 * st.color;
                        errorbar(ax, [r.mission_vehicle_count], values, ...
                            spread, 'LineStyle', 'none', 'Color', whiskerColor, ...
                            'LineWidth', .65, 'HandleVisibility', 'off');
                    end
                end
                handles(i) = plot(ax, [r.mission_vehicle_count], [r.load_jain], ...
                    st.lineStyle, 'Marker', st.marker, 'Color', st.color, ...
                    'LineWidth', 1.9, 'MarkerSize', 6, ...
                    'DisplayName', label(names{i}));
            end
            % Report the no-MEC convention: the current FitnessLibrary returns
            % Jain=1 for zero load, a mathematically undefined 0/0 case.
            a = results.executionAudit;
            if ~isempty(a) && isfield(a, 'mec_busy_time_total_s')
                a = a(strcmp({a.fitness_id}, rows(1).fitness_id));
                anyNoMec = any([a.mec_busy_time_total_s] <= 1e-18);
            end
            xlabel(ax, 'Number of mission vehicles');
            ylabel(ax, 'Jain fairness index of MEC busy time (higher is better)');
            xticks(ax, counts);
            % Jain is a bounded index. A disclosed zoom improves legibility
            % when all values cluster close to 1; never truncate data.
            spreadAll = [rows.load_jain];
            if isfield(rows, 'load_jain_std')
                spreadAll = spreadAll - [rows.load_jain_std];
            end
            if ~isempty(spreadAll) && min(spreadAll) >= 0.75
                floorY = max(0, floor((min(spreadAll) - 0.025) * 20) / 20);
                ylim(ax, [floorY 1]);
                yticks(ax, linspace(floorY, 1, 6));
                isZoomed = floorY > 0;
            else
                ylim(ax, [0 1]);
                yticks(ax, 0:0.2:1);
                isZoomed = false;
            end
            finishAxes(ax);
            legend(ax, handles, cellfun(@label, names, 'UniformOutput', false), ...
                'Location', 'eastoutside', 'Box', 'off', 'FontSize', 10);
            if ~isempty(rows) && isfield(rows, 'fitness_id')
                if strcmp(rows(1).fitness_id, 'fitness_1')
                    title(ax, 'Figure 11 | MEC load balance | Fitness 1 (paper)', ...
                        'FontWeight', 'normal');
                else
                    title(ax, 'Figure 11 | MEC load balance | Fitness 2 (load-aware)', ...
                        'FontWeight', 'normal');
                end
            end
            if numel(unique([rows.sample_count])) == 1 && rows(1).sample_count > 1
                detail = sprintf('Mean +/- 1 SD across %d independent seeds', rows(1).sample_count);
            else
                detail = 'Mean across seeds; whiskers: +/- 1 SD when n > 1';
            end
            if isZoomed
                detail = [detail ' | Y-axis zoomed (Jain is bounded by 0 and 1)'];
            end
            if anyNoMec
                detail = [detail ' | WARNING: zero MEC busy time is assigned Jain=1 by baseline code'];
                warning('Figure 11: at least one run has zero MEC busy time; Jain=1 is a code convention, not meaningful load balance.');
            end
            annotation(f, 'textbox', [.085 .055 .86 .06], 'String', detail, ...
                'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
                'FontName', 'Times New Roman', 'FontSize', 10);
            % Do not modify the objective, all algorithms, or article plots.

        case 'figure_8'
            f = newFigure([100 100 1100 470]);
            t = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

            ax = nexttile(t, 1);
            panel(rows, 'deadline_s', 'avg_delay', ...
                  'Deadline of application (s)', 'Average delay (s)');
            xlim(ax, [0.03 0.10]);
            xticks(ax, 0.03:0.01:0.10);
            ylim(ax, [0.02 0.08]);
            yticks(ax, 0.02:0.01:0.08);
            title(ax, '(a)', 'FontWeight', 'normal');

            ax = nexttile(t, 2);
            panel(rows, 'deadline_s', 'completion_rate', ...
                  'Deadline of application (s)', 'Completion rate (%)');
            xlim(ax, [0.03 0.10]);
            xticks(ax, 0.03:0.01:0.10);
            applyCompletionAxis(ax, [rows.completion_rate], 'figure_8');
            title(ax, '(b)', 'FontWeight', 'normal');

        case 'figure_9'
            f = newFigure([100 100 900 620]);
            names = unique({rows.algorithm}, 'stable');
            speeds = sort(unique([rows.speed_kmh]));
            vals = zeros(numel(speeds), numel(names));
            for i = 1:numel(names)
                for j = 1:numel(speeds)
                    r = rows(strcmp({rows.algorithm}, names{i}) & [rows.speed_kmh] == speeds(j));
                    vals(j, i) = r.total_efficiency;
                end
            end
            b = bar(1:numel(speeds), vals, 'grouped');
            for i = 1:min(numel(b), numel(names))
                st = algorithmStyle(names{i}, i);
                b(i).FaceColor = st.color;
            end
            set(gca, 'XTick', 1:numel(speeds), ...
                'XTickLabel', arrayfun(@num2str, speeds, 'UniformOutput', false));
            xlabel('Speed of vehicles (km/h)');
            ylabel('Total offloading efficiency');
            finishAxes(gca);
            legend(cellfun(@label, names, 'UniformOutput', false), ...
                   'Location', 'best', 'Box', 'off');

        case 'figure_10'
            f = newFigure([100 100 1000 650]);
            names = unique({rows.algorithm}, 'stable');
            plotPosition = [.12 .15 .72 .74];
            left = axes('Parent', f, 'Position', plotPosition);
            hold(left, 'on');
            right = axes('Parent', f, 'Position', plotPosition, ...
                         'Color', 'none', 'YAxisLocation', 'right', 'XTick', [], 'Box', 'off');
            hold(right, 'on');
            handles = gobjects(0);

            for i = 1:numel(names)
                r = rows(strcmp({rows.algorithm}, names{i}));
                [~, ix] = sort([r.mec_capacity_ghz]);
                r = r(ix);
                st = algorithmStyle(names{i}, i);

                h1 = plot(left, [r.mec_capacity_ghz], [r.avg_efficiency], ...
                          st.lineStyle, 'Marker', st.marker, 'Color', st.color, ...
                          'LineWidth', 2.0, 'MarkerSize', 6);
                plot(right, [r.mec_capacity_ghz], [r.completion_rate], ...
                     '--', 'Marker', st.marker, 'Color', st.color, ...
                     'LineWidth', 1.7, 'MarkerSize', 5.5);
                handles(end + 1) = h1; %#ok<AGROW>
            end

            xlabel(left, 'Computing capacity of MEC servers (GHz)');
            ylabel(left, 'Average offloading efficiency');
            ylabel(right, 'Completion rate (%)');

            set(left, 'XLim', [28 82], 'XTick', 30:10:80);
            set(right, 'XLim', [28 82]);

            % Paper-style efficiency range when suitable; otherwise keep all data visible.
            ev = [rows.avg_efficiency];
            if ~isempty(ev) && min(ev) >= 0.20 && max(ev) <= 0.50
                ylim(left, [0.20 0.50]);
                yticks(left, 0.20:0.05:0.50);
            else
                paddedLimits(left, ev, 0.05, 0);
            end

            applyCompletionAxis(right, [rows.completion_rate], 'figure_10');

            finishAxes(left);
            set(right, 'FontName', 'Times New Roman', 'FontSize', 11, ...
                'LineWidth', 0.9, 'TickDir', 'out');
            legend(left, handles, cellfun(@label, names, 'UniformOutput', false), ...
                   'Location', 'northwest', 'Box', 'off');
            title(left, 'Solid: efficiency   |   Dashed: completion rate', ...
                  'FontWeight', 'normal', 'FontSize', 10);
            set(left, 'Position', plotPosition);
            set(right, 'Position', plotPosition);

    end

    saveFigure(f, out, results.figure);
    close(f);
end

function panel(rows, xkey, ykey, xlabelText, ylabelText)
    names = unique({rows.algorithm}, 'stable');
    hold on;
    for i = 1:numel(names)
        r = rows(strcmp({rows.algorithm}, names{i}));
        [~, ix] = sort([r.(xkey)]);
        r = r(ix);
        st = algorithmStyle(names{i}, i);

        plot([r.(xkey)], [r.(ykey)], st.lineStyle, ...
             'Marker', st.marker, ...
             'Color', st.color, ...
             'LineWidth', 2.0, ...
             'MarkerSize', 6, ...
             'DisplayName', label(names{i}));
    end

    values = sort(unique([rows.(xkey)]));
    if numel(values) <= 10
        set(gca, 'XTick', values);
    end
    xlabel(xlabelText);
    ylabel(ylabelText);
    finishAxes(gca);
    legend('Location', 'best', 'Box', 'off');
end

function applyCompletionAxis(ax, values, mode)
    % Keep underlying data unchanged in [0,1], but show human-readable percent.
    values = values(isfinite(values));

    switch mode
        case 'figure_7'
            % Matches the paper's main Figure 7(d) scale when the data fit it.
            lower = 0.60;
            if ~isempty(values) && min(values) < lower
                lower = max(0, floor(min(values) * 10) / 10);
            end
            upper = 1.00;
            ylim(ax, [lower upper]);
            ticks = lower:0.10:upper;
            if abs(ticks(end) - upper) > 1e-12
                ticks = [ticks upper];
            end

        case 'figure_8'
            % Figure 8 evaluates completion over the full 0%-100% range.
            ylim(ax, [0 1]);
            ticks = 0:0.20:1;

        case 'figure_10'
            % The paper zooms into very high completion rates here (98.8%-100%).
            if isempty(values) || (min(values) >= 0.988 && max(values) <= 1.0)
                ylim(ax, [0.988 1.000]);
                ticks = 0.988:0.002:1.000;
            else
                lo = max(0, floor((min(values) - 0.005) * 100) / 100);
                hi = min(1, ceil((max(values) + 0.005) * 100) / 100);
                if hi <= lo
                    lo = max(0, hi - 0.01);
                end
                ylim(ax, [lo hi]);
                ticks = linspace(lo, hi, 7);
            end

        otherwise
            ylim(ax, [0 1]);
            ticks = 0:0.20:1;
    end

    yticks(ax, ticks);
    set(ax, 'YTickLabel', arrayfun(@(v)percentLabel(v), ticks, 'UniformOutput', false));
end

function s = percentLabel(v)
    pct = 100 * v;
    if abs(pct - round(pct)) < 1e-9
        s = sprintf('%.0f%%', pct);
    else
        s = sprintf('%.1f%%', pct);
    end
end

function paddedLimits(ax, values, step, lowerBound)
    values = values(isfinite(values));
    if isempty(values)
        return
    end
    lo = min(values);
    hi = max(values);
    span = max(hi - lo, step);
    pad = max(step, 0.10 * span);
    lo = max(lowerBound, floor((lo - pad) / step) * step);
    hi = ceil((hi + pad) / step) * step;
    if hi <= lo
        hi = lo + step;
    end
    ylim(ax, [lo hi]);
end

function finishAxes(ax)
    set(ax, ...
        'FontName', 'Times New Roman', ...
        'FontSize', 11, ...
        'LineWidth', 0.9, ...
        'TickDir', 'out', ...
        'Box', 'on', ...
        'Layer', 'top');
    grid(ax, 'on');
    ax.GridLineStyle = ':';
    ax.GridAlpha = 0.20;
end

function f = newFigure(position)
    f = figure('Visible', 'off', 'Color', 'w', 'Position', position);
end

function st = algorithmStyle(name, index)
    % Stable, publication-friendly styles; also remain distinguishable in grayscale.
    palette = [ ...
               0.0000 0.4470 0.7410; ...
               0.8500 0.3250 0.0980; ...
               0.4660 0.6740 0.1880; ...
               0.4940 0.1840 0.5560; ...
               0.3010 0.7450 0.9330; ...
               0.6350 0.0780 0.1840; ...
               0.9290 0.6940 0.1250];

    switch name
        case 'dcsga'
            st.color = palette(1, :);
            st.marker = 'o';
            st.lineStyle = '-';
        case 'gwo'
            st.color = palette(4, :);
            st.marker = 's';
            st.lineStyle = '--';
        case 'gpc'
            st.color = [0.10 0.60 0.50];
            st.marker = '^';
            st.lineStyle = '--';
        case 'cpo'
            st.color = [0.80 0.10 0.35];
            st.marker = 'x';
            st.lineStyle = '-';
        case 'dcpo'
            st.color = [0.10 0.35 0.75];
            st.marker = 'p';
            st.lineStyle = '-.';
        case 'dcpo_base'
            st.color = [0.35 0.35 0.35];
            st.marker = 'v';
            st.lineStyle = ':';
        case 'dcpo_criticality'
            st.color = [0.55 0.25 0.70];
            st.marker = 'h';
            st.lineStyle = '--';
        case 'dcpo_cache'
            st.color = [0.15 0.60 0.60];
            st.marker = '>';
            st.lineStyle = '--';
        case 'puma'
            st.color = [0.90 0.35 0.25];
            st.marker = 'd';
            st.lineStyle = '--';
        otherwise
            k = mod(index - 1, size(palette, 1)) + 1;
            st.color = palette(k, :);
            st.marker = 'o';
            st.lineStyle = '-';
    end
end

function s = label(n)
    names = {'dcsga', 'gwo', 'gpc', 'cpo', 'dcpo', ...
             'dcpo_base', 'dcpo_criticality', 'dcpo_cache', 'puma'};
    labels = {'DCSGA/Cuckoo', 'D-GWO', 'D-GPC', 'CPO (one-hot)', ...
              'DCPO (direct-discrete)', 'DCPO-base', ...
              'DCPO-criticality', 'DCPO-cache', 'D-Puma'};
    ix = find(strcmp(n, names), 1);
    if isempty(ix)
        s = n;
    else
        s = labels{ix};
    end
end

function rows = selectFitness(rows, id)
    if isempty(rows) || ~isfield(rows, 'fitness_id')
        return
    end
    rows = rows(strcmp({rows.fitness_id}, id));
end

function saveFigure(f, out, name)
    set(f, 'PaperPositionMode', 'auto');
    set(f, 'PaperUnits', 'inches');
    pos = get(f, 'Position');
    set(f, 'PaperSize', pos(3:4) / 100);
    set(f, 'PaperPosition', [0 0 pos(3:4) / 100]);

    png = fullfile(out, [name '.png']);
    pdf = fullfile(out, [name '.pdf']);

    print(f, png, '-dpng', '-r300');
    print(f, pdf, '-dpdf');

    info = dir(pdf);
    if isempty(info) || info.bytes == 0
        drawnow;
        print(f, pdf, '-dpdf');
        info = dir(pdf);
    end
    assert(~isempty(info) && info.bytes > 0, 'PDF export failed');
end
