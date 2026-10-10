
# Vehicle CPO — Vehicular Edge–Fog Computing Optimization in MATLAB

A research-oriented MATLAB implementation for task scheduling and cache-aware optimization in Vehicular Edge–Fog Computing (VEFC).

This repository contains a MATLAB port and cleaned research codebase derived from the project implementation of:

> **Cuckoo Search-Enabled Task Scheduling and Cache Updating in Vehicular Edge-Fog Computing**  
> IEEE Transactions on Vehicular Technology, 2025  
> DOI: `10.1109/TVT.2025.3540639`

The repository includes the paper-aligned DCSGA/Cuckoo baseline, a discrete CPO-based optimizer and several additional comparison optimizers under a shared benchmark/evaluation framework.

---

## Project goals

The project is designed to:

- reproduce and study the vehicular edge–fog scheduling model;
- evaluate task scheduling and cache-aware assignment strategies;
- compare CPO-based variants against the DCSGA/Cuckoo baseline;
- support fair optimizer comparisons using a common objective/evaluator and a shared NFE budget;
- reproduce benchmark scenarios corresponding to Figures 6–10 of the base study;
- export convergence, statistical and application-level results for analysis.

The MATLAB package focuses on the scientific/optimization layer. The former application/API worker layer is intentionally outside the scope of this MATLAB version.

---

## Implemented algorithms

The benchmark runner currently recognizes the following algorithm names:

| Algorithm name | Description |
|---|---|
| `dcsga` / `cuckoo` | Paper-aligned Cuckoo Search / DCSGA baseline |
| `cpo` | Full discrete CPO-based optimizer |
| `dcpo_base` | Base CPO variant |
| `dcpo_criticality` | CPO variant using task criticality guidance |
| `dcpo_cache` | CPO variant using cache-related guidance |
| `gpc` | Discrete GPC comparison optimizer |
| `gwo` / `gwo_aco` | Discrete GWO comparison optimizer |
| `puma` | Discrete Puma comparison optimizer |
| `dtosc` | DTOSC baseline |
| `to_v2i` | DCSGA ablation / V2I-only mode |
| `to_wo_c` | DCSGA without caching |
| `to_wo_r` | DCSGA without task ranking |

> The CPO/GPC/GWO/Puma implementations in this repository are discrete, project-adapted variants. They should not be interpreted as unmodified continuous versions of the original algorithms.

---

## Repository structure

```text
vehicle_cpo/
├── config/
│   └── defaultConfig.m          # Main experiment configuration
├── data/
│   └── dataset.json             # VEFC dataset used by the MATLAB model
├── results/                     # Experiment outputs and generated figures
├── src/
│   ├── +bench/                  # Benchmark runner, statistics and plots
│   ├── +dataio/                 # Dataset loading/state handling
│   ├── +monarch/                # Ported numerical/model utilities
│   ├── +optim/                  # Optimization algorithms
│   └── +vefc/                   # VEFC model, evaluator, formulas and cache logic
├── tools/
│   └── convert_pg_dump.py       # Optional PostgreSQL dump converter
├── run_experiment.m             # Main experiment entry point
├── run_snapshot.m               # Fixed snapshot / assignment evaluation
├── startup.m                    # Adds project folders to the MATLAB path
├── README.md
└── .gitignore
```

MATLAB folders beginning with `+` are package namespaces. For example:

```text
src/+optim/cpo.m  ->  optim.cpo
```

---

## Requirements

### Required

- MATLAB
- The complete repository, including `data/dataset.json`

### Optional

- Python, only if you need to regenerate `dataset.json` from a PostgreSQL dump using `tools/convert_pg_dump.py`

No Python environment is required for normal MATLAB experiment execution.

---

## Quick start

Clone the repository:

```bash
git clone https://github.com/sara172423/vehicle_cpo.git
cd vehicle_cpo
```

Open MATLAB and set the repository root — the directory containing `startup.m` — as the **Current Folder**.

Then run:

```matlab
startup
cfg = defaultConfig();
results = run_experiment(cfg);
```

The default configuration is defined in:

```text
config/defaultConfig.m
```

---

## Small smoke test

For a very small startup test:

```matlab
startup
cfg = defaultConfig();
cfg.figure = 'figure_6';
cfg.repetitions = 1;
cfg.populationSize = 2;
cfg.tmax = 1;
cfg.diagnosticVehicleCount = 3;
cfg.diagnosticRoadVehicleCount = 8;
cfg.summaryOnly = true;
cfg.outputDir = fullfile(pwd, 'results', 'smoke_test');
results = run_experiment(cfg);
```

This is only a functional smoke test. It is **not** suitable for scientific comparison or convergence claims.

---

## Example: fair CPO vs DCSGA comparison

```matlab
startup
cfg = defaultConfig();

cfg.figure = 'figure_6';
cfg.algorithms = {'dcsga', 'cpo'};
cfg.experimentMode = 'fair_optimizer_comparison';

cfg.seedStart = 2001;
cfg.repetitions = 3;
cfg.populationSize = 20;
cfg.tmax = 200;
cfg.maxFunctionEvaluations = 300;

cfg.diagnosticVehicleCount = 20;
cfg.diagnosticRoadVehicleCount = 20;

cfg.outputDir = fullfile(pwd, 'results', 'cpo_vs_dcsga');
results = run_experiment(cfg);
```

In `fair_optimizer_comparison` mode, a common function-evaluation budget (`maxFunctionEvaluations`) is required.

---

## Experiment modes

The project supports two experiment modes:

### `paper_reproduction`

Used for paper-aligned reproduction runs. Only the algorithms associated with the selected source figure are accepted, and the run is controlled by `tmax` rather than a shared NFE cap.

### `fair_optimizer_comparison`

Used when comparing added optimizers. A common:

```matlab
cfg.maxFunctionEvaluations
```

must be specified so algorithms are evaluated under a shared objective-evaluation budget.

---

## Main configuration fields

The most frequently used fields are:

| Field | Purpose |
|---|---|
| `figure` | Selects benchmark scenario: `figure_6` … `figure_10` |
| `algorithms` | Algorithms to compare |
| `experimentMode` | `paper_reproduction` or `fair_optimizer_comparison` |
| `repetitions` | Number of repeated runs |
| `seedStart` | First random seed |
| `populationSize` | Optimizer population size |
| `tmax` | Search-loop limit |
| `maxFunctionEvaluations` | Shared NFE cap for fair comparisons |
| `diagnosticVehicleCount` | Optional reduced Mission count |
| `diagnosticRoadVehicleCount` | Optional reduced road-vehicle count |
| `diagnosticSweepValues` | Optional subset for Figure 9/10 sweeps |
| `exportArtifacts` | Enables result/figure export |
| `summaryOnly` | Skips detailed output artifacts |
| `outputDir` | Result output directory |
| `dataDir` | Path to `dataset.json` |

Always begin a new experiment from a fresh configuration:

```matlab
cfg = defaultConfig();
```

---

## Benchmark scenarios

| Figure | Scenario |
|---|---|
| Figure 6 | Convergence / population behavior and best-so-far vs NFE |
| Figure 7 | Mission vehicle count sweep: 52, 56, …, 76 |
| Figure 8 | Deadline-based analysis using 68 missions |
| Figure 9 | Vehicle-speed sweep: 75–105 km/h |
| Figure 10 | MEC-capacity sweep: 30–80 GHz |

Figure 8 uses a larger default repetition count than the other individual figure runs. For quick checks, explicitly set:

```matlab
cfg.repetitions = 1;
```

---

## Important source files

| File | Responsibility |
|---|---|
| `src/+optim/cpo.m` | CPO search logic and CPO variants |
| `src/+optim/cuckoo.m` | DCSGA / Cuckoo baseline |
| `src/+optim/gpc.m` | GPC optimizer |
| `src/+optim/gwo.m` | GWO optimizer |
| `src/+optim/puma.m` | Puma optimizer |
| `src/+optim/dtosc.m` | DTOSC implementation |
| `src/+optim/EvaluationBudget.m` | Function-evaluation budget tracking |
| `src/+optim/OptimizerCommon.m` | Shared optimizer utilities / initialization |
| `src/+vefc/Evaluator.m` | Fitness, delay, energy and task execution evaluation |
| `src/+vefc/FormulaLibrary.m` | Model formulas and numerical compatibility helpers |
| `src/+vefc/ContextBuilder.m` | Builds optimization context and provider domains |
| `src/+vefc/CacheManager.m` | Cache handling |
| `src/+bench/runAlgorithm.m` | Selects optimizer/variant |
| `src/+bench/scenarios.m` | Figure-specific benchmark scenarios |
| `src/+bench/run.m` | Benchmark execution |
| `src/+bench/plots.m` | Plot generation |

---

## Results

Depending on configuration, an experiment can export artifacts such as:

- raw experiment results;
- summary results;
- convergence histories;
- application-level metrics;
- NFE summaries;
- pairwise statistical results;
- metadata and execution audit information;
- PNG/PDF benchmark figures.

Set a dedicated output directory for every important experiment to avoid overwriting previous results:

```matlab
cfg.outputDir = fullfile(pwd, 'results', 'my_experiment_name');
```

---

## Dataset

The default MATLAB input is:

```text
data/dataset.json
```

The current project data contains the VEFC entities and parameters required by the benchmark model, including vehicles, RSUs, application/task data, dependencies, services and resource parameters.

If a new PostgreSQL dump must be converted, the optional converter can be used from a system terminal:

```bash
python tools/convert_pg_dump.py new_dump.sql data/raw
```

This may regenerate/overwrite dataset artifacts. Back up the existing data before conversion.

---

## Reproducibility notes

For meaningful algorithm comparisons:

1. use the same scenario and dataset;
2. use controlled seeds;
3. keep the objective/evaluator identical;
4. use a common NFE budget for fair optimizer comparisons;
5. report population size, `tmax`, NFE budget and repetitions;
6. use multiple seeds for statistical conclusions;
7. keep generated outputs in separate experiment directories.

The code includes numerical compatibility work intended to preserve important behavior from the reference Python implementation, but final scientific claims should still be based on verified MATLAB runs on the target MATLAB installation.

---

## Scientific scope and limitations

This repository preserves several modeling assumptions from the source implementation/research reconstruction. In particular:

- the workload/DAG data are a research reconstruction rather than an official public dataset from the paper;
- the MATLAB benchmark solves a static experiment snapshot rather than the complete dynamic web/API worker system;
- implementation parity with a reference codebase does not by itself prove the scientific superiority or novelty of any optimizer;
- fair comparison requires more than using a common objective function — budgets, seeds, parameter settings and repetition counts must also be reported.

---

## Git workflow

A typical contribution workflow is:

```bash
git switch -c feature/my-change
# edit files
git add .
git commit -m "Describe the change"
git push -u origin feature/my-change
```

Then open a Pull Request on GitHub and merge only after reviewing the changes and experiment impact.

Avoid committing secrets, local environments, raw database dumps or temporary MATLAB/Python artifacts. The included `.gitignore` covers the common cases for this repository.

---

## Reference

Base paper:

**Cuckoo Search-Enabled Task Scheduling and Cache Updating in Vehicular Edge-Fog Computing**  
DOI: `10.1109/TVT.2025.3540639`

---

## Repository

GitHub: `https://github.com/sara172423/vehicle_cpo`

