#!/usr/bin/env python3
"""review_normalize.py — Normalize code quality review output."""

from __future__ import annotations

import json
import sys
from typing import Any, Dict, List, Optional


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


def clamp01(value: Optional[float]) -> Optional[float]:
    if value is None:
        return None
    if value < 0:
        return 0.0
    if value > 1:
        return 1.0
    return value


def numeric_or_none(value: Any) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, bool):
        return float(value)
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def first_numeric(*values: Any) -> Optional[float]:
    for value in values:
        numeric_value = numeric_or_none(value)
        if numeric_value is not None:
            return numeric_value
    return None


def normalize_issue(issue: Any) -> Dict[str, Any]:
    if isinstance(issue, str):
        return {
            "severity": "medium",
            "category": "general",
            "title": issue,
            "details": None,
            "file": None,
        }

    if isinstance(issue, dict):
        severity = str(
            issue.get("severity")
            or issue.get("level")
            or issue.get("priority")
            or "medium"
        ).lower()
        return {
            "severity": severity,
            "category": issue.get("category") or issue.get("type") or "general",
            "title": issue.get("title")
            or issue.get("message")
            or issue.get("summary")
            or "Issue",
            "details": issue.get("details")
            or issue.get("description")
            or issue.get("reason"),
            "file": issue.get("file") or issue.get("path"),
        }

    return {
        "severity": "medium",
        "category": "general",
        "title": str(issue),
        "details": None,
        "file": None,
    }


def penalty(severity: str) -> float:
    mapping = {
        "critical": 0.30,
        "high": 0.20,
        "medium": 0.10,
        "low": 0.05,
    }
    return mapping.get(severity, 0.08)


def nested_value(mapping: Dict[str, Any], *keys: str) -> Any:
    current: Any = mapping
    for key in keys:
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
    return current


def summary_value(review: Dict[str, Any]) -> Any:
    for key in ("summary", "overview", "verdict"):
        if key in review:
            return review[key]
    return None


def normalize(review: Dict[str, Any], timestamp: str, feature_slug: str, subagent_id: str) -> Dict[str, Any]:
    raw_issues = review.get("issues") or review.get("findings") or review.get("problems") or []
    if not isinstance(raw_issues, list):
        raw_issues = []
    issues: List[Dict[str, Any]] = [normalize_issue(issue) for issue in raw_issues]

    score_source = review.get("scores") or review.get("category_scores") or review.get("categories") or {}
    score_entries: Dict[str, float] = {}
    if isinstance(score_source, dict):
        for key, value in score_source.items():
            numeric_value = numeric_or_none(value)
            if numeric_value is not None:
                score_entries[str(key)] = numeric_value

    direct_score = first_numeric(
        review.get("overall_score"),
        review.get("score"),
        nested_value(review, "scores", "overall"),
        nested_value(review, "summary", "overall_score"),
    )

    overall_score: Optional[float]
    if direct_score is not None:
        overall_score = clamp01(direct_score)
    elif score_entries:
        overall_score = clamp01(sum(score_entries.values()) / len(score_entries))
    elif issues:
        score = 1.0
        for issue in issues:
            score -= penalty(str(issue.get("severity") or "medium"))
        overall_score = 0.0 if score < 0 else score
    else:
        overall_score = None

    return {
        "timestamp": timestamp,
        "feature_slug": feature_slug,
        "stage": "code_quality",
        "subagent_id": subagent_id,
        "status": "completed",
        "overall_score": overall_score,
        "summary": summary_value(review),
        "scores": score_entries,
        "issues": issues,
        "failure_reason": None,
        "source": "subagent_review_output",
    }


def main() -> int:
    payload = load_payload()
    if payload is None:
        return emit({"ok": False, "error": "invalid_input"}, 1)

    review = payload.get("review")
    if review is None:
        review = {}
    if not isinstance(review, dict):
        return emit({"ok": False, "error": "invalid_review"}, 1)

    result = normalize(
        review=review,
        timestamp=str(payload.get("timestamp") or ""),
        feature_slug=str(payload.get("feature_slug") or ""),
        subagent_id=str(payload.get("subagent_id") or ""),
    )
    return emit(result, 0)


if __name__ == "__main__":
    raise SystemExit(main())
