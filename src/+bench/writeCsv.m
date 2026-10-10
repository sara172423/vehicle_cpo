function writeCsv(path, rows)
    fid = fopen(path, 'w');
    assert(fid >= 0, 'Cannot write %s', path);
    cleanup = onCleanup(@()fclose(fid));
    if isempty(rows)
        return
    end
    names = fieldnames(rows);
    fprintf(fid, '%s\n', strjoin(names, ','));
    for i = 1:numel(rows)
        cells = cell(1, numel(names));
        for j = 1:numel(names)
            v = rows(i).(names{j});
            if isempty(v)
                s = '';
            elseif ischar(v)
                s = v;
            elseif islogical(v) && isscalar(v)
                if v
                    s = 'True';
                else
                    s = 'False';
                end
            elseif isnumeric(v) && isscalar(v)
                s = sprintf('%.17g', v);
            else
                s = jsonencode(v);
            end
            s = strrep(s, '"', '""');
            cells{j} = ['"' s '"'];
        end
        fprintf(fid, '%s\n', strjoin(cells, ','));
    end
end
