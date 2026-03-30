#!/usr/bin/env python3
"""review_score.py — Weighted scoring for two-stage review results."""

from __future__ import annotations

import json
import sys
from typing import Any, Dict, Optional


def emit(payload: Dict[str, Any], exit_code: int) -> int:
    print(json.dumps(payload, ensure_ascii=False))
    return exit_code


def load_payload() -> Optional[Dict[str, Any]]:
    raw = sys.stdin.read()
    if not raw.strip():
        return None

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return None

    if not isinstance(payload, dict):
        return None

    return payload


def numeric(value: Any, default: float) -> float:
    if isinstance(value, bool):
        return float(value)
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return default
    return default


def build_combined_result(payload: Dict[str, Any]) -> Dict[str, Any]:
    spec_result = payload.get("spec_result")
    quality_result = payload.get("quality_result")
    if not isinstance(spec_result, dict):
        spec_result = {}
    if not isinstance(quality_result, dict):
        quality_result = {}

    spec_weight = numeric(payload.get("spec_weight"), 0.6)
    quality_weight = numeric(payload.get("quality_weight"), 0.4)
    pass_threshold = numeric(payload.get("review_pass_threshold"), 0.9)

    spec_score = numeric(spec_result.get("overall_score"), 0.0)
    quality_score = numeric(quality_result.get("overall_score"), 1.0)
    combined_score = (spec_score * spec_weight) + (quality_score * quality_weight)

    return {
        "timestamp": payload.get("timestamp") or "",
        "feature_slug": payload.get("feature_slug") or "",
        "stage1_spec_compliance": spec_result,
        "stage2_code_quality": quality_result,
        "overall": {
            "spec_score": round(spec_score, 2),
            "quality_score": round(quality_score, 2),
            "combined_score": round(combined_score, 2),
            "passed": combined_score >= pass_threshold,
        },
    }


def main() -> int:
    payload = load_payload()
    if payload is None:
        return emit({"ok": False, "error": "invalid_input"}, 1)

    return emit(build_combined_result(payload), 0)


if __name__ == "__main__":
    raise SystemExit(main())
