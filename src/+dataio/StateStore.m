classdef StateStore < handle
    % In-process replacement for ORM record CRUD and state persistence.
    % Worker loops and Django HTTP endpoints are intentionally absent.
    properties (SetAccess = private)
        data
    end
    methods

        function obj = StateStore(path)
            if nargin < 1
                obj.data = dataio.loadDataset();
            else
                obj.data = dataio.loadDataset(path);
            end
        end

        function records = list(obj, table)
            assert(isfield(obj.data, table), 'Unknown table');
            records = obj.data.(table);
        end

        function record = get(obj, table, id)
            records = obj.list(table);
            ix = find([records.id] == id);
            assert(numel(ix) == 1, 'Record not found or duplicate');
            record = records(ix);
        end

        function insert(obj, table, record)
            records = obj.list(table);
            assert(isstruct(record) && isscalar(record) && isfield(record, 'id'), 'Record needs an id');
            if ~isempty(records)
                assert(~ismember(record.id, [records.id]), 'Duplicate record');
                assert(isequal(sort(fieldnames(record)), sort(fieldnames(records))), 'Schema mismatch');
                record = orderfields(record, records);
            end
            if isempty(records)
                records = record;
            else
                records(end + 1) = record;
            end
            obj.data.(table) = records;
            obj.refreshParams(table);
        end

        function update(obj, table, id, fields)
            records = obj.list(table);
            ix = find([records.id] == id);
            assert(numel(ix) == 1, 'Record not found');
            keys = fieldnames(fields);
            for j = 1:numel(keys)
                assert(isfield(records, keys{j}), 'Unknown record field');
                assert(~strcmp(keys{j}, 'id'), 'ID cannot change');
                records(ix).(keys{j}) = fields.(keys{j});
            end
            obj.data.(table) = records;
            obj.refreshParams(table);
        end

        function remove(obj, table, id)
            records = obj.list(table);
            ix = find([records.id] == id);
            assert(numel(ix) == 1, 'Record not found');
            records(ix) = [];
            obj.data.(table) = records;
            obj.refreshParams(table);
        end

        function resetRuntime(obj)
            names = {'applications', 'cache', 'executions', 'states', 'rsu_vehicles'};
            for j = 1:numel(names)
                if isfield(obj.data, names{j})
                    obj.data.(names{j}) = struct([]);
                end
            end
            for j = 1:numel(obj.data.resources)
                obj.data.resources(j).cpu_used = 0;
                obj.data.resources(j).cache_used = 0;
            end
        end

        function save(obj, path)
            fid = fopen(path, 'w');
            assert(fid >= 0, 'Cannot save data');
            cleanup = onCleanup(@()fclose(fid));
            fwrite(fid, jsonencode(obj.data), 'char');
        end

        function advancePositions(obj, timeStepSeconds)
            assert(isfinite(timeStepSeconds) && timeStepSeconds >= 0);
            vs = obj.data.vehicles;
            for j = 1:numel(vs)
                v = vs(j);
                path = v.path;
                if isempty(path) || size(path, 1) < 2
                    continue
                end
                speed = v.speed;
                if isstruct(v.initial_snapshot) && isfield(v.initial_snapshot, 'speed_kmh')
                    speed = v.initial_snapshot.speed_kmh;
                end
                length = monarch.Model.path_length_2d(path);
                if speed <= 0 || length <= 0
                    pos = path(1, :);
                else
                    travel = length / (speed / 3.6);
                    pos = monarch.Model.current_position(travel, min(timeStepSeconds, travel), path);
                end
                vs(j).x_coord = pos(1);
                vs(j).y_coord = pos(2);
            end
            obj.data.vehicles = vs;
        end

    end
    methods (Access = private)

        function refreshParams(obj, table)
            if strcmp(table, 'parameters')
                obj.data.params = struct();
                for j = 1:numel(obj.data.parameters)
                    r = obj.data.parameters(j);
                    obj.data.params.(r.key) = r.value;
                end
            end
        end

    end
end
