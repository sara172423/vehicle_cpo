# VEFC MATLAB Benchmark — Clean Research Version

This repository contains the MATLAB implementation used for VEFC task scheduling/cache experiments based on:

**Cuckoo Search-Enabled Task Scheduling and Cache Updating in Vehicular Edge-Fog Computing**  
DOI: `10.1109/TVT.2025.3540639`

The project keeps the paper objective immutable and isolates the proposed load-aware objective so algorithms and fitness definitions can be tested independently.

## Supported optimizers

Only the optimizer families currently used in this project are enabled:

| MATLAB ID | Meaning |
|---|---|
| `dcsga` (alias: `cuckoo`) | Paper-aligned discrete Cuckoo / DCSGA baseline |
| `cpo` | Full proposed CPO variant |
| `dcpo_base` | Base CPO ablation |
| `dcpo_criticality` | CPO + criticality guidance |
| `dcpo_cache` | CPO + cache guidance |
| `gwo` | Discrete Grey Wolf Optimizer |
| `gpc` | Discrete Giza Pyramids Construction optimizer |
| `puma` | Discrete Puma Optimizer |

PSO, DTOSC and the old TO-* branches are not part of this clean version.

## Active fitness functions

Only two active fitness definitions are retained:

### 1. `fitness_1` — Paper Baseline

Exact article total offloading-efficiency objective. This is the immutable baseline and must not be modified.

### 2. `fitness_load_aware` — Load-Aware Weighted-Sum

The previously screened `fitness_4` has been renamed to a scientific descriptive ID:

```text
fitness_load_aware
```

Formula:

```text
Score = (1-lambda)*PaperQ + lambda*N*Jain(MEC busy time)
```

Default:

```matlab
cfg.loadAwareWeight = 0.05;
```

The old experimental `fitness_2`, `fitness_3` and `fitness_5` IDs have been removed.

**Important:** do not compare raw `optimization_score` magnitudes across different fitness definitions. For cross-fitness analysis compare PaperQ, delay, energy, MEC load imbalance/Jain, completion rate and task-mode counts.

## Temporary/new fitness location

A clearly marked section named:

```text
TEMPORARY EXPERIMENTAL FITNESS SLOT
```

exists in:

```text
src/+vefc/FitnessLibrary.m
```

To test a new temporary fitness:

1. add any new parameter to `config/defaultConfig.m`;
2. add the temporary ID to `allowedFitnesses` in `src/+bench/validateConfig.m`;
3. add one new `case` under the marked slot in `src/+vefc/FitnessLibrary.m`;
4. do **not** change optimizer files and do **not** modify `fitness_1`.

## Repository structure

```text
config/defaultConfig.m        Main configuration
data/dataset.json             VEFC simulation dataset
src/+bench/                   Runner, validation, statistics, plots, export
src/+optim/                   Cuckoo, CPO, GPC, GWO, Puma
src/+vefc/                    Context, evaluator, formulas, fitness library
src/+monarch/Model.m          Ported numerical model utilities
run_experiment.m              Main experiment entry point
run_snapshot.m                Frozen-snapshot/fixed-assignment evaluation
startup.m                     Adds project folders to MATLAB path
EXPERIMENT_COMMANDS.md        Clean commands for Figures 6–10
```

## Quick start

```matlab
startup
cfg = defaultConfig();
results = run_experiment(cfg);
```

With the untouched default configuration this runs the DCSGA/Cuckoo baseline using `fitness_1`.

## Fair optimizer comparison

Use a common NFE budget:

```matlab
cfg = defaultConfig();
cfg.figure = 'figure_6';
cfg.experimentMode = 'fair_optimizer_comparison';
cfg.algorithms = {'dcsga','cpo','gpc','gwo','puma'};
cfg.fitnesses = {'fitness_1'};
cfg.repetitions = 5;
cfg.seedStart = 10001;
cfg.populationSize = 50;
cfg.tmax = 200;
cfg.maxFunctionEvaluations = 1000;
cfg.outputDir = fullfile(pwd,'results','figure_6_base');
results = run_experiment(cfg);
```

## Fitness selection

Baseline only:

```matlab
cfg.fitnesses = {'fitness_1'};
```

Load-aware only:

```matlab
cfg.fitnesses = {'fitness_load_aware'};
cfg.loadAwareWeight = 0.05;
```

Paired baseline-vs-load-aware comparison on the same frozen seed/scenario:

```matlab
cfg.fitnesses = {'fitness_1','fitness_load_aware'};
cfg.loadAwareWeight = 0.05;
```

The runner builds each scenario once per seed and reuses that frozen context for every selected fitness and algorithm.

## Experiment modes

### `paper_reproduction`

- algorithm: DCSGA/Cuckoo only;
- fitness: `fitness_1` only;
- controlled by `tmax`;
- no common NFE cap.

### `fair_optimizer_comparison`

- any supported optimizer(s);
- either active fitness or both;
- requires `cfg.maxFunctionEvaluations`;
- all optimizer/fitness runs consume the same NFE budget.

## Benchmark scenarios

| Figure | Scenario |
|---|---|
| Figure 6 | Convergence / best-so-far vs NFE |
| Figure 7 | Mission-count sweep: 52, 56, 60, 64, 68, 72, 76 |
| Figure 8 | Deadline-group analysis with 68 missions |
| Figure 9 | Vehicle-speed sweep: 75–105 km/h |
| Figure 10 | MEC capacity sweep: 30–80 GHz |

Figure 7 now uses the strict 76-record paper-aligned vehicle/provider pool instead of mixing the 20 extension records into the road sample.

Figure 9 retains the stochastic per-lane spatial Poisson road process; the finite 96-record provider pool is used because a realization can exceed 76 vehicles.

## Reconstruction assumptions

The benchmark remains a reconstructed simulation benchmark, not a real traffic trace. Two unpublished reconstruction parameters remain explicit/configurable:

```matlab
cfg.deadlineSamplingWeights = [5 10 15 20 20 15 10 5];
cfg.sourceProgramFraction = 0.10;
```

These assumptions are written to `metadata.json` for every exported experiment.

## Exported artifacts

With:

```matlab
cfg.exportArtifacts = true;
cfg.summaryOnly = false;
```

the main output is intentionally compact:

- `summary_results.csv`
- `raw_results.csv`
- `metadata.json`
- `fitness_comparison_results.csv` only when more than one fitness is selected
- figure PNG/PDF files; Figure 6 also exports NFE plots

The full MATLAB `results` structure is returned in memory. Save it manually only when you actually need a `.mat` archive.

## Scientific comparison notes

- Use the same seed/scenario for paired algorithm and fitness comparisons.
- Use a common NFE budget in fair optimizer comparisons.
- Keep `fitness_1` immutable.
- For final claims use independent held-out seeds and report mean/dispersion, paired tests and effect sizes.
- MEC load balance is **MEC-server load balance**, not whole-system/user fairness.
- A no-MEC-use solution has mathematically equal zero MEC loads; always inspect `mec_task_count_total` alongside Jain/load imbalance so zero utilization is not misinterpreted as useful balance.
