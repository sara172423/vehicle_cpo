function data = loadDataset(path)
    % Portable canonical JSON, built byte-for-byte from the supplied SQL tables.
    if nargin == 0
        path = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'data', 'dataset.json');
    end
    % Accept either the JSON filename or the directory containing it.
    % fileparts(path) would incorrectly jump to the parent of data/.
    if isfolder(path)
        path = fullfile(path, 'dataset.json');
    end
    assert(isfile(path), 'Dataset file not found: %s', char(path));
    data = jsondecode(fileread(path));
    data.params = struct();
    for i = 1:numel(data.parameters)
        r = data.parameters(i);
        data.params.(r.key) = r.value;
    end
    assert(numel(unique([data.tasks.id])) == numel(data.tasks), 'Duplicate task IDs');
    assert(all([data.tasks.workload_cycles] > 0), 'Nonpositive workload');
    assert(all(ismember([data.dependencies.parent_task_id_id], [data.tasks.id])) && all(ismember([data.dependencies.child_task_id_id], [data.tasks.id])), 'Unknown dependency');
end
