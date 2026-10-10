function export(results, cfg)
    out = char(cfg.outputDir);
    if ~isfolder(out)
        mkdir(out);
    end
    bench.writeCsv(fullfile(out, 'summary_results.csv'), results.summary);
    bench.writeCsv(fullfile(out, 'execution_audit.csv'), results.executionAudit);
    bench.writeCsv(fullfile(out, 'pairwise_statistics.csv'), results.pairwiseStatistics);
    if strcmp(results.figure, 'figure_6')
        bench.writeCsv(fullfile(out, 'nfe_summary_results.csv'), results.nfeSummary);
    end
    if ~cfg.summaryOnly
        bench.writeCsv(fullfile(out, 'raw_results.csv'), results.raw);
        bench.writeCsv(fullfile(out, 'application_results.csv'), results.applications);
        bench.writeCsv(fullfile(out, 'convergence_results.csv'), results.convergence);
    end
    metadata = rmfield(results, {'raw', 'summary', 'applications', 'convergence', 'runs'});
    metadata.article_doi = '10.1109/TVT.2025.3540639';
    metadata.matlab_runtime_verified = false;
    metadata.reconstruction_assumptions = {'Stored DAG realizations are unpublished reconstructions'; 'Source-program bits = roundEven(0.1 * service-environment bits), numeric source size unpublished'; 'Compile work is supplied by task-type snapshots, numeric Wk unpublished'; 'V2V and sender-power model follow uploaded Python declared approximations'; 'One static joint scheduling epoch; 10 applications/s not dynamically simulated'; 'Remote MEC uses access RSU and zero added backhaul delay/energy'; 'Cache Eq40 counts OTHER cached providers, preserving uploaded implementation'; 'Wilcoxon auto policy follows SciPy 1.17; statisticsMode=none reproduces no-SciPy null p-values'};
    writeJson(fullfile(out, 'metadata.json'), metadata);
    if ~cfg.summaryOnly
        writeJson(fullfile(out, 'experiment_result.json'), results);
    end
end

function writeJson(path, x)
    fid = fopen(path, 'w');
    assert(fid >= 0);
    cleanup = onCleanup(@()fclose(fid));
    fwrite(fid, jsonencode(x), 'char');
end
