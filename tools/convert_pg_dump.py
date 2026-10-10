#!/usr/bin/env python3
"""Convert the project's PostgreSQL COPY dump to MATLAB-friendly CSV/JSON.

Scientific scenario and runtime-state tables are exported. Historical DAG
backups are retained separately; Django authentication is framework metadata.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


TABLES = {
    "dag_applicationtype": "application_types.csv",
    "dag_tasktype": "task_types.csv",
    "dag_task": "tasks.csv",
    "dag_taskdependency": "dependencies.csv",
    "object_rsu": "rsus.csv",
    "object_vehicle": "vehicles.csv",
    "object_serviceprovider": "service_providers.csv",
    "resource_resource": "resources.csv",
    "cache_cache": "cache.csv",
    "application_application": "applications.csv",
    "parameter_parameter": "parameters.csv",
}


def read_dump(path: Path) -> str:
    raw = path.read_bytes()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16")
    if raw.count(b"\x00") > len(raw) // 10:
        return raw.decode("utf-16-le")
    return raw.decode("utf-8")


def unescape_pg(value: str):
    if value == r"\N":
        return None
    result = []
    i = 0
    escapes = {"b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v"}
    while i < len(value):
        c = value[i]
        i += 1
        if c != "\\" or i == len(value):
            result.append(c)
            continue
        c = value[i]
        i += 1
        if c in escapes:
            result.append(escapes[c])
        elif c in "01234567":
            digits = c
            while i < len(value) and len(digits) < 3 and value[i] in "01234567":
                digits += value[i]
                i += 1
            result.append(chr(int(digits, 8)))
        elif c == "x" and i < len(value) and value[i] in "0123456789abcdefABCDEF":
            digits = value[i]
            i += 1
            if i < len(value) and value[i] in "0123456789abcdefABCDEF":
                digits += value[i]
                i += 1
            result.append(chr(int(digits, 16)))
        else:
            result.append(c)
    return "".join(result)


def typed_cell(value):
    if value is None:
        return None
    if value in {"t", "f"}:
        return value == "t"
    try:
        return json.loads(value)
    except (ValueError, TypeError):
        return value


def parse_copy_blocks(text: str):
    lines = iter(text.splitlines())
    for line in lines:
        if not line.startswith("COPY public.") or " FROM stdin;" not in line:
            continue
        prefix, _ = line.split(" FROM stdin;", 1)
        table_and_columns = prefix[len("COPY public.") :]
        table, raw_columns = table_and_columns.split(" (", 1)
        columns = [item.strip() for item in raw_columns[:-1].split(",")]
        rows = []
        for data_line in lines:
            if data_line == r"\.":
                break
            values = [unescape_pg(item) for item in data_line.split("\t")]
            if len(values) != len(columns):
                raise ValueError(
                    f"Column mismatch in {table}: {len(values)} != {len(columns)}"
                )
            rows.append(values)
        yield table, columns, rows


def typed_parameter(value: str, value_type: str):
    kind = value_type.strip().lower()
    if kind in {"int", "integer"}:
        return int(float(value))
    if kind in {"float", "double", "number"}:
        return float(value)
    if kind in {"bool", "boolean"}:
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return value


def convert(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    extracted = {}
    canonical = {}
    for table, columns, rows in parse_copy_blocks(read_dump(source)):
        if table not in TABLES:
            optional = {"execution_taskexecution":"executions.csv", "state_state":"states.csv", "object_rsuvehicle":"rsu_vehicles.csv"}
            if table in optional:
                filename = optional[table]
            elif table.startswith("dag_taskdependency_"):
                filename = table + ".csv"
            else:
                continue
        else:
            filename = TABLES[table]
        target = destination / filename
        with target.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(columns)
            writer.writerows(rows)
        extracted[table] = {"file": target.name, "rows": len(rows)}
        canonical[target.stem] = [{k: typed_cell(v) for k, v in zip(columns, row)} for row in rows]

    missing = sorted(set(TABLES) - set(extracted))
    if missing:
        raise ValueError(f"Required COPY blocks are missing: {missing}")

    import hashlib
    canonical["provenance"] = {"source": source.name, "sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
    dataset_path = destination.parent / "dataset.json" if destination.name == "raw" else destination / "dataset.json"
    dataset_path.write_text(json.dumps(canonical, ensure_ascii=False, indent=2), encoding="utf-8")

    parameters = {}
    parameter_csv = destination / TABLES["parameter_parameter"]
    with parameter_csv.open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            parameters[row["key"]] = {
                "value": typed_parameter(row["value"], row["value_type"]),
                "unit": row["unit"],
                "type": row["value_type"],
            }
    (destination / "parameters.json").write_text(
        json.dumps(parameters, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (destination / "metadata.json").write_text(
        json.dumps(
            {
                "source": source.name,
                "format": "MATLAB-friendly CSV tables",
                "excluded": [
                    "Django auth/migrations/session",
                    "Django admin/authentication infrastructure",
                ],
                "tables": extracted,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("dump", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    convert(args.dump, args.output)


if __name__ == "__main__":
    main()
