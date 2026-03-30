#!/usr/bin/env python3
"""wave_plan.py — Wave DAG planner contract."""

from __future__ import annotations

import json
import sys
from typing import Any, Dict, List, Tuple


def emit(payload: Dict[str, Any], exit_code: int) -> int:
    print(json.dumps(payload, ensure_ascii=False))
    return exit_code


def load_tasks() -> List[Dict[str, Any]] | None:
    raw = sys.stdin.read()
    if not raw.strip():
        return None

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return None

    if isinstance(payload, dict) and "tasks" in payload:
        tasks = payload["tasks"]
    else:
        tasks = payload

    if not isinstance(tasks, list):
        return None

    normalized: List[Dict[str, Any]] = []
    for task in tasks:
        if isinstance(task, dict):
            normalized.append(task)
        else:
            return None

    return normalized


def validate(tasks: List[Dict[str, Any]]) -> Tuple[bool, Dict[str, Any]]:
    ids = [task.get("id") for task in tasks]

    seen: Dict[Any, int] = {}
    duplicate_ids: List[Any] = []
    for task_id in ids:
        seen[task_id] = seen.get(task_id, 0) + 1
        if seen[task_id] == 2:
            duplicate_ids.append(task_id)

    id_set = set(ids)
    missing_dependencies: List[Dict[str, Any]] = []
    for task in tasks:
        for dep in list(task.get("dependencies") or []):
            if dep not in id_set:
                missing_dependencies.append(
                    {"task_id": task.get("id"), "dependency": dep}
                )

    valid = not duplicate_ids and not missing_dependencies
    return valid, {
        "valid": valid,
        "duplicate_ids": duplicate_ids,
        "missing_dependencies": missing_dependencies,
    }


def resolve(tasks: List[Dict[str, Any]]) -> Tuple[Dict[str, Any], int]:
    valid, validation = validate(tasks)
    if not valid:
        return {
            "ok": False,
            "error": "invalid_dependency_graph",
            "duplicate_ids": validation["duplicate_ids"],
            "missing_dependencies": validation["missing_dependencies"],
        }, 1

    indegree: Dict[Any, int] = {}
    adjacency: Dict[Any, List[Any]] = {}

    for task in tasks:
        task_id = task.get("id")
        deps = list(task.get("dependencies") or [])
        indegree[task_id] = len(deps)
        adjacency.setdefault(task_id, [])

    for task in tasks:
        task_id = task.get("id")
        for dep in list(task.get("dependencies") or []):
            adjacency.setdefault(dep, []).append(task_id)

    ready = [task.get("id") for task in tasks if indegree.get(task.get("id"), 0) == 0]
    order: List[Any] = []
    waves: List[List[Any]] = []
    processed = 0

    while ready:
        current_wave = list(ready)
        waves.append(current_wave)
        next_ready: List[Any] = []

        for ready_id in current_wave:
            order.append(ready_id)
            processed += 1

            for neighbor in adjacency.get(ready_id, []):
                indegree[neighbor] = indegree.get(neighbor, 0) - 1
                if indegree[neighbor] == 0 and neighbor not in next_ready:
                    next_ready.append(neighbor)

        ready = next_ready

    if processed != len(tasks):
        unresolved = [
            {
                "id": task.get("id"),
                "dependencies": list(task.get("dependencies") or []),
            }
            for task in tasks
            if indegree.get(task.get("id"), 0) > 0
        ]
        return {
            "ok": False,
            "error": "circular_dependency",
            "order": order,
            "waves": waves,
            "unresolved": unresolved,
        }, 1

    return {
        "ok": True,
        "order": order,
        "waves": waves,
        "validation": validation,
        "unresolved": [],
    }, 0


def main() -> int:
    tasks = load_tasks()
    if tasks is None:
        return emit({"ok": False, "error": "invalid_input"}, 1)

    payload, exit_code = resolve(tasks)
    return emit(payload, exit_code)


if __name__ == "__main__":
    raise SystemExit(main())
