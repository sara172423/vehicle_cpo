function summary = summarize(rows, keys, metrics)
    summary = struct([]);
    if isempty(rows)
        return
    end
    groups = containers.Map('KeyType', 'char', 'ValueType', 'any');
    ordered = {};
    for i = 1:numel(rows)
        vals = cell(1, numel(keys));
        for j = 1:numel(keys)
            vals{j} = rows(i).(keys{j});
        end
        k = jsonencode(vals);
        if ~isKey(groups, k)
            groups(k) = i;
            ordered{end + 1} = k;
        else
            groups(k) = [groups(k) i];
        end
    end
    for i = 1:numel(ordered)
        idx = groups(ordered{i});
        row = struct();
        for j = 1:numel(keys)
            row.(keys{j}) = rows(idx(1)).(keys{j});
        end
        for j = 1:numel(metrics)
            m = metrics{j};
            st = bench.stats([rows(idx).(m)]);
            names = fieldnames(st);
            row.(m) = st.mean;
            for k = 1:numel(names)
                if ~strcmp(names{k}, 'mean')
                    row.([m '_' names{k}]) = st.(names{k});
                end
            end
        end
        row.sample_count = numel(idx);
        if isempty(summary)
            summary = row;
        else
            summary(end + 1) = row;
        end

    end
    % Sort Python tuple keys lexicographically, including numeric values.
    idx = 1:numel(summary);
    for j = numel(keys):-1:1
        v = {summary(idx).(keys{j})};
        if isnumeric(v{1})
            [~, ix] = sort(cell2mat(v));
        else
            [~, ix] = sort(v);
        end
        idx = idx(ix);
    end
    summary = summary(idx);
end
