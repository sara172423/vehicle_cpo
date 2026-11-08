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
| `cpo` | Paper-based CPO defense equations with VEFC-specific categorical projection |
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


## Figure 11 — MEC load-balance comparison (original research addition)

Figure 11 is **not** in the original Cuckoo paper. It uses the same seven
mission-vehicle counts as Figure 7 (52, 56, 60, 64, 68, 72, 76) and plots
**Jain fairness of total MEC busy time** (Y, range 0–1; higher means more
balanced) against **number of mission vehicles** (X). It draws a different
curve for every optimizer in `cfg.algorithms`; results are averaged over
independent seeds, with +/- one standard deviation shown when available.

To choose Fitness 1 or Fitness 2, set `cfg.fitnesses` to a single ID. To
run both, pass both IDs: separate `fitness_1/figure_11.png` and
`fitness_load_aware/figure_11.png` (and corresponding PDFs) are saved.

```matlab
startup
cfg = defaultConfig();
cfg.figure = 'figure_11';
cfg.algorithms = {'dcsga','cpo','gpc','gwo','puma'};
cfg.fitnesses = {'fitness_1','fitness_load_aware'};  % Or choose one
cfg.experimentMode = 'fair_optimizer_comparison';
cfg.maxFunctionEvaluations = 1000;
cfg.tmax = 300;
cfg.populationSize = 50;
cfg.repetitions = 5;
cfg.seedStart = 101;
cfg.loadAwareWeight = 0.05;
cfg.outputDir = fullfile(pwd, 'results', 'figure_11_all');
results = run_experiment(cfg);
```

For 5 optimizers, 2 fitness definitions, 7 vehicle counts and 5 seeds,
this requires **350 optimization runs**. For a short smoke run select fewer
vehicle counts using `cfg.diagnosticVehicleCount=[52 76]` and fewer seeds.

**Interpretation warning:** a Jain value near 1 describes equal MEC busy
loads, not high utilization or better delay/energy. `FitnessLibrary` currently
returns Jain=1 when all MECs are idle, which is a 0/0 mathematical case;
Figure 11 warns when such runs occur. Do not compare the numerical values
of different fitness objective functions to choose a winner.


## CPO implementation and archived variant (2026-11-08)

`src/+optim/cpo.m` is now the former article-based implementation previously named `cpo_article.m`. It applies the paper-based CPO defense update equations in a continuous one-hot embedding, followed by a VEFC-specific categorical projection. The projection is a bounded-edit/Hamming-neighborhood rule; it is an adaptation for the VEFC assignment problem, not an equation from the CPO paper.

The former discrete VEFC-specific implementation of `cpo.m` has been preserved, without changing its source code, at `trash/cpo.m`. It is archived and is not dispatched by the active benchmark runner. Its `dcpo_base`, `dcpo_criticality`, and `dcpo_cache` variants are therefore no longer active algorithm IDs.

The active CPO retains immediate one-parent/one-child greedy acceptance after each NEW fitness evaluation, and uses the shared VEFC linear defense schedule from `optim.cpoDefenseSchedule` (25/25/40/10 initially, moving to 5/5/15/75). This is not the fixed defense schedule of the original CPO paper. The implementation is not a complete reproduction of the original continuous CPO: the one-hot representation, categorical projection, initialization, NFE clock, population handling, and some adaptation choices remain problem-specific. No System Model, evaluator, dataset, cache, fitness, or Cuckoo implementation was changed in this reorganization.
