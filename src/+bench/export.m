function export(results, cfg)
    % Export a compact research artifact set.
    %
    % Files written here:
    %   - summary_results.csv
    %   - raw_results.csv          (unless summaryOnly=true)
    %   - metadata.json
    %
    % Figure PNG/PDF files are written separately by bench.plots().
    % For Figure 6, bench.plots() also writes figure_6_nfe.png/.pdf.

    out = char(cfg.outputDir);
    if ~isfolder(out)
        mkdir(out);
    end

    % Remove artifacts produced by older versions so an existing results
    % folder does not keep obsolete files after a new run.
    removeLegacyArtifacts(out, cfg.summaryOnly);

    % Keep the two CSV files that are most useful for analysis/review.
    bench.writeCsv(fullfile(out, 'summary_results.csv'), results.summary);

    if ~cfg.summaryOnly
        bench.writeCsv(fullfile(out, 'raw_results.csv'), results.raw);
    end

    % Keep reproducibility/scientific metadata in one JSON file instead of
    % exporting several auxiliary CSV/JSON files. Detailed audit/statistics
    % remain available inside this metadata structure.
    metadata = rmfield(results, {'raw', 'summary', 'applications', 'convergence', 'runs'});
    metadata.article_doi = '10.1109/TVT.2025.3540639';
    metadata.matlab_runtime_verified = false;
    metadata.reconstruction_assumptions = { ...
        'Stored DAG realizations are unpublished reconstructions'; ...
        'Source-program bits = roundEven(0.1 * service-environment bits), numeric source size unpublished'; ...
        'Compile work is supplied by task-type snapshots, numeric Wk unpublished'; ...
        'V2V and sender-power model follow uploaded Python declared approximations'; ...
        'One static joint scheduling epoch; 10 applications/s not dynamically simulated'; ...
        'Remote MEC uses access RSU and zero added backhaul delay/energy'; ...
        'Cache Eq40 counts OTHER cached providers, preserving uploaded implementation'; ...
        'Wilcoxon auto policy follows SciPy 1.17; statisticsMode=none reproduces no-SciPy null p-values' ...
    };

    writeJson(fullfile(out, 'metadata.json'), metadata);
end

function removeLegacyArtifacts(out, summaryOnly)
    obsolete = { ...
        'application_results.csv', ...
        'convergence_results.csv', ...
        'execution_audit.csv', ...
        'experiment_result.json', ...
        'nfe_summary_results.csv', ...
        'pairwise_statistics.csv' ...
    };

    for i = 1:numel(obsolete)
        path = fullfile(out, obsolete{i});
        if isfile(path)
            delete(path);
        end
    end

    % If this run explicitly requests summary-only output, remove a raw CSV
    % left by an earlier non-summary run in the same folder.
    if summaryOnly
        path = fullfile(out, 'raw_results.csv');
        if isfile(path)
            delete(path);
        end
    end
end

function writeJson(path, x)
    fid = fopen(path, 'w');
    assert(fid >= 0, 'Could not open JSON output file: %s', path);
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, jsonencode(x), 'char');
end
