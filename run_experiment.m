function results = run_experiment(cfg)
    if nargin < 1
        cfg = defaultConfig();
    end
    if ~isfield(cfg, 'dataDir')
        base = defaultConfig();
        cfg.dataDir = base.dataDir;
    end
    d = dataio.loadDataset(cfg.dataDir);
    cfg = bench.validateConfig(cfg, d);
    results = bench.run(d, cfg);
    if cfg.exportArtifacts
        if strcmp(cfg.figure, 'all')
            names = fieldnames(results.results);
            for j = 1:numel(names)
                r = results.results.(names{j});
                c = r.configuration;
                c.outputDir = fullfile(cfg.outputDir, names{j});
                bench.export(r, c);
                bench.plots(r, c);
            end
        else
            bench.export(results, cfg);
            bench.plots(results, cfg);
        end
    end
end
