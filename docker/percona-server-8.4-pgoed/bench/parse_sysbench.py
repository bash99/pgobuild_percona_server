#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import math
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


WORKLOADS = ("point_select", "read_only", "read_write")


@dataclass(frozen=True)
class SysbenchMetrics:
    tps: float | None
    qps: float | None
    total_time_s: float | None
    total_events: int | None
    latency_avg_ms: float | None
    latency_p95_ms: float | None
    latency_max_ms: float | None


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def _parse_first_float(text: str) -> float | None:
    try:
        return float(text.strip())
    except Exception:
        return None


def _parse_first_int(text: str) -> int | None:
    try:
        return int(text.strip())
    except Exception:
        return None


def parse_params_env(path: Path) -> dict[str, str]:
    params: dict[str, str] = {}
    if not path.exists():
        return params
    for raw_line in _read_text(path).splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        params[key.strip()] = value.strip()
    return params


def parse_server_variables_table(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    vars_map: dict[str, str] = {}
    for raw_line in _read_text(path).splitlines():
        line = raw_line.strip()
        if not (line.startswith("|") and line.endswith("|")):
            continue
        # | innodb_buffer_pool_size | 50331648 |
        parts = [p.strip() for p in line.strip("|").split("|")]
        if len(parts) != 2:
            continue
        name, value = parts
        if name and name != "Variable_name":
            vars_map[name] = value
    return vars_map


def parse_server_version_kv(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    out: dict[str, str] = {}
    for raw_line in _read_text(path).splitlines():
        if ":" not in raw_line:
            continue
        key, value = raw_line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if key and value and not key.startswith("*"):
            out[key] = value
    return out


def parse_docker_image_inspect_id(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(_read_text(path))
        if isinstance(data, list) and data:
            first = data[0]
            return {
                "id": first.get("Id"),
                "repo_tags": first.get("RepoTags"),
                "repo_digests": first.get("RepoDigests"),
                "created": first.get("Created"),
            }
    except Exception:
        return {}
    return {}


def parse_sysbench_log(path: Path) -> SysbenchMetrics:
    text = _read_text(path)

    def rx(pattern: str) -> re.Match[str] | None:
        return re.search(pattern, text, re.MULTILINE)

    tps = None
    m = rx(r"^\s*transactions:\s+\d+\s+\(([\d.]+)\s+per sec\.\)")
    if m:
        tps = float(m.group(1))
    else:
        m = rx(r"^\s*events:\s+\d+\s+\(([\d.]+)\s+per sec\.\)")
        if m:
            tps = float(m.group(1))

    qps = None
    m = rx(r"^\s*queries:\s+\d+\s+\(([\d.]+)\s+per sec\.\)")
    if m:
        qps = float(m.group(1))

    total_time_s = None
    m = rx(r"^\s*time elapsed:\s*([\d.]+)s")
    if m:
        total_time_s = float(m.group(1))
    else:
        m = rx(r"^\s*total time:\s+([\d.]+)s")
        if m:
            total_time_s = float(m.group(1))

    total_events = None
    m = rx(r"^\s*total number of events:\s+(\d+)")
    if m:
        total_events = int(m.group(1))

    latency_avg_ms = None
    latency_p95_ms = None
    latency_max_ms = None

    m = rx(r"^Latency \(ms\):\n(?:.*\n)*?\s*avg:\s*([\d.]+)")
    if m:
        latency_avg_ms = float(m.group(1))

    m = rx(r"^Latency \(ms\):\n(?:.*\n)*?\s*95th percentile:\s*([\d.]+)")
    if m:
        latency_p95_ms = float(m.group(1))

    m = rx(r"^Latency \(ms\):\n(?:.*\n)*?\s*max:\s*([\d.]+)")
    if m:
        latency_max_ms = float(m.group(1))

    return SysbenchMetrics(
        tps=tps,
        qps=qps,
        total_time_s=total_time_s,
        total_events=total_events,
        latency_avg_ms=latency_avg_ms,
        latency_p95_ms=latency_p95_ms,
        latency_max_ms=latency_max_ms,
    )


def _percentile(values: list[float], pct: float) -> float | None:
    if not values:
        return None
    if pct <= 0:
        return min(values)
    if pct >= 100:
        return max(values)
    values_sorted = sorted(values)
    k = (len(values_sorted) - 1) * (pct / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return values_sorted[int(k)]
    d0 = values_sorted[f] * (c - k)
    d1 = values_sorted[c] * (k - f)
    return d0 + d1


def parse_vmstat_iowait(path: Path) -> list[float]:
    if not path.exists():
        return []
    lines = _read_text(path).splitlines()
    header_idx = None
    wa_idx = None
    for i, line in enumerate(lines[:10]):
        cols = line.strip().split()
        if "wa" in cols and "id" in cols and "us" in cols:
            header_idx = i
            wa_idx = cols.index("wa")
            break
    if header_idx is None or wa_idx is None:
        return []
    waits: list[float] = []
    for line in lines[header_idx + 1 :]:
        cols = line.strip().split()
        if len(cols) <= wa_idx:
            continue
        if not cols[0].isdigit():
            continue
        try:
            waits.append(float(cols[wa_idx]))
        except Exception:
            continue
    return waits


def iter_sysbench_logs(run_dir: Path) -> Iterable[tuple[str, str, int, Path]]:
    # yields: (variant, workload, threads, path)
    for variant_dir in run_dir.iterdir():
        if not variant_dir.is_dir():
            continue
        variant = variant_dir.name
        sb_dir = variant_dir / "sysbench"
        if not sb_dir.is_dir():
            continue
        for path in sb_dir.glob("*.log"):
            name = path.stem
            m = re.match(r"^(?P<workload>.+)_t(?P<threads>\d+)$", name)
            if not m:
                continue
            workload = m.group("workload")
            if workload not in WORKLOADS:
                continue
            threads = int(m.group("threads"))
            yield (variant, workload, threads, path)


def fmt_float(value: float | None, digits: int = 2) -> str:
    if value is None:
        return "-"
    return f"{value:.{digits}f}"


def fmt_pct(value: float | None, digits: int = 2) -> str:
    if value is None:
        return "-"
    sign = "+" if value >= 0 else ""
    return f"{sign}{value:.{digits}f}%"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True, type=Path)
    parser.add_argument("--out-json", required=True, type=Path)
    parser.add_argument("--out-md", required=True, type=Path)
    args = parser.parse_args()

    run_dir: Path = args.run_dir
    params = parse_params_env(run_dir / "params.env")
    sysbench_version = (run_dir / "sysbench-version.txt").read_text(encoding="utf-8", errors="replace").strip() if (
        run_dir / "sysbench-version.txt"
    ).exists() else None

    by_variant: dict[str, dict[str, dict[int, SysbenchMetrics]]] = {}
    for variant, workload, threads, path in iter_sysbench_logs(run_dir):
        by_variant.setdefault(variant, {}).setdefault(workload, {})[threads] = parse_sysbench_log(path)

    variants_meta: dict[str, Any] = {}
    iowait_summary: dict[str, Any] = {}
    for variant in sorted(by_variant.keys()):
        vdir = run_dir / variant
        vars_map = parse_server_variables_table(vdir / "server-variables.txt")
        ver_map = parse_server_version_kv(vdir / "server-version.txt")
        image_meta = parse_docker_image_inspect_id(vdir / "image-inspect.json")
        dataset_mb = _parse_first_float((vdir / "dataset-size-mb.txt").read_text(encoding="utf-8", errors="replace")) if (
            vdir / "dataset-size-mb.txt"
        ).exists() else None

        variants_meta[variant] = {
            "server_version": ver_map,
            "server_variables": vars_map,
            "dataset_size_mb": dataset_mb,
            "image": image_meta,
        }

        wa_values: list[float] = []
        samples_root = vdir / "samples"
        if samples_root.is_dir():
            for vm_path in samples_root.glob("*/vmstat.log"):
                wa_values.extend(parse_vmstat_iowait(vm_path))
        iowait_summary[variant] = {
            "samples": len(wa_values),
            "avg_wa": (sum(wa_values) / len(wa_values)) if wa_values else None,
            "p95_wa": _percentile(wa_values, 95.0),
            "max_wa": max(wa_values) if wa_values else None,
        }

    # Only compare if we have both variants.
    comparison: dict[str, dict[int, Any]] = {}
    if "official" in by_variant and "pgoed" in by_variant:
        for workload in WORKLOADS:
            comp_rows: dict[int, Any] = {}
            threads_all = sorted(
                set(by_variant.get("official", {}).get(workload, {}).keys())
                | set(by_variant.get("pgoed", {}).get(workload, {}).keys())
            )
            for threads in threads_all:
                o = by_variant.get("official", {}).get(workload, {}).get(threads)
                p = by_variant.get("pgoed", {}).get(workload, {}).get(threads)
                if o is None or p is None:
                    continue
                tps_delta = ((p.tps / o.tps - 1.0) * 100.0) if (o.tps and p.tps) else None
                comp_rows[threads] = {
                    "official": o.__dict__,
                    "pgoed": p.__dict__,
                    "tps_delta_pct": tps_delta,
                }
            if comp_rows:
                comparison[workload] = comp_rows

    out: dict[str, Any] = {
        "run_dir": os.fspath(run_dir),
        "params": params,
        "sysbench_version": sysbench_version,
        "variants": variants_meta,
        "iowait": iowait_summary,
        "results": {
            variant: {
                workload: {str(threads): metrics.__dict__ for threads, metrics in threads_map.items()}
                for workload, threads_map in workload_map.items()
            }
            for variant, workload_map in by_variant.items()
        },
        "comparison": comparison,
    }

    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(out, indent=2, sort_keys=True), encoding="utf-8")

    md_lines: list[str] = []
    md_lines.append("# Sysbench head-to-head summary")
    md_lines.append("")
    md_lines.append(f"- run dir: `{run_dir}`")
    if sysbench_version:
        md_lines.append(f"- sysbench: `{sysbench_version}` (`{params.get('SYSBENCH_IMAGE', '-')}`)")
    md_lines.append(
        f"- dataset: tables={params.get('SB_TABLES','-')}, table_size={params.get('SB_TABLE_SIZE','-')}"
    )
    md_lines.append(f"- threads: `{params.get('SB_THREADS_LIST','-')}`")
    md_lines.append(f"- time: `{params.get('SB_TIME','-')}s`, warmup: `{params.get('SB_WARMUP_TIME','-')}s`")
    md_lines.append("")

    def variant_block(name: str) -> None:
        md_lines.append(f"## {name}")
        v = variants_meta.get(name, {})
        ver = v.get("server_version", {})
        img = v.get("image", {})
        md_lines.append(f"- image: `{params.get('OFFICIAL_IMAGE' if name=='official' else 'PGOED_IMAGE','-')}`")
        if img.get("id"):
            md_lines.append(f"- image id: `{img.get('id')}`")
        if ver.get("version"):
            md_lines.append(f"- mysqld version: `{ver.get('version')}`")
        if ver.get("version_comment"):
            md_lines.append(f"- version_comment: `{ver.get('version_comment')}`")
        dataset_mb = v.get("dataset_size_mb")
        if dataset_mb is not None:
            md_lines.append(f"- dataset size: `{fmt_float(dataset_mb, 1)} MB` (data+index)")
        vars_map = v.get("server_variables", {})
        if vars_map:
            md_lines.append("- key vars:")
            for k in (
                "innodb_buffer_pool_size",
                "innodb_flush_method",
                "innodb_flush_log_at_trx_commit",
                "innodb_redo_log_capacity",
                "sync_binlog",
                "performance_schema",
            ):
                if k in vars_map:
                    md_lines.append(f"  - `{k}={vars_map[k]}`")
        io = iowait_summary.get(name, {})
        if io.get("samples"):
            md_lines.append(
                f"- vmstat iowait(wa): avg `{fmt_float(io.get('avg_wa'), 2)}%`, p95 `{fmt_float(io.get('p95_wa'), 2)}%`, max `{fmt_float(io.get('max_wa'), 2)}%`"
            )
        md_lines.append("")

    if "official" in variants_meta:
        variant_block("official")
    if "pgoed" in variants_meta:
        variant_block("pgoed")

    for workload in WORKLOADS:
        md_lines.append(f"## results: {workload}")
        md_lines.append("")
        md_lines.append("| threads | official tps | pgoed tps | delta tps | official avg ms | pgoed avg ms | official p95 ms | pgoed p95 ms |")
        md_lines.append("|---:|---:|---:|---:|---:|---:|---:|---:|")
        comp = comparison.get(workload, {})
        for threads in sorted(comp.keys()):
            row = comp[threads]
            o = SysbenchMetrics(**row["official"])
            p = SysbenchMetrics(**row["pgoed"])
            md_lines.append(
                "| "
                + " | ".join(
                    [
                        str(threads),
                        fmt_float(o.tps, 2),
                        fmt_float(p.tps, 2),
                        fmt_pct(row.get("tps_delta_pct"), 2),
                        fmt_float(o.latency_avg_ms, 2),
                        fmt_float(p.latency_avg_ms, 2),
                        fmt_float(o.latency_p95_ms, 2),
                        fmt_float(p.latency_p95_ms, 2),
                    ]
                )
                + " |"
            )
        md_lines.append("")

    args.out_md.parent.mkdir(parents=True, exist_ok=True)
    args.out_md.write_text("\n".join(md_lines).rstrip() + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
