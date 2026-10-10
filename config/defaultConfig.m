function cfg = defaultConfig()
    % Main experiment settings. Override these fields in the Command Window.
    % Physics/DAG/resource values remain in data/dataset.json.
    root = fileparts(fileparts(mfilename('fullpath')));

    cfg = struct( ...
        'figure', 'figure_6', ...                  % Figure 6, 7, 8, 9 or 10
        'algorithms', {{}}, ...                   % Empty = source-figure defaults
        'experimentMode', '', ...                 % Paper reproduction or fair NFE
        'repetitions', [], ...                    % Empty = figure-specific default
        'statisticsMode', 'scipy_1_17', ...        % Statistical policy; or 'none'
        'seedStart', 1, ...                       % First repetition's seed
        'populationSize', 50, ...                 % Number of solutions
        'tmax', 15, ...                           % Initialization + search limit
        'maxFunctionEvaluations', [], ...         % Common NFE cap in fair mode
        'vehicleCount', 76, ...                   % Internal snapshot default
        'diagnosticVehicleCount', [], ...         % Optional Mission count override
        'diagnosticRoadVehicleCount', [], ...     % Optional Road count override
        'diagnosticSweepValues', [], ...          % Optional speed/MEC subset
        'exportArtifacts', true, ...              % Write results and figures
        'summaryOnly', false, ...                 % Skip detailed output files
        'outputDir', fullfile(root, 'results'), ...
        'dataDir', fullfile(root, 'data', 'dataset.json'));
end
