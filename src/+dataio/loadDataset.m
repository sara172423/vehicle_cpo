function data = loadDataset(path)
    % Portable canonical JSON, built byte-for-byte from the supplied SQL tables.
    if nargin == 0
        path = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'data', 'dataset.json');
    end
    if exist(path, 'dir')
        path = fullfile(fileparts(path), 'dataset.json');
    end
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
