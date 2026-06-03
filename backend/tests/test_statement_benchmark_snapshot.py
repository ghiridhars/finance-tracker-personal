import json
import os

import pytest

from tests.fixtures.statement_cases import PHASE0_CASES
from tests.helpers.statement_case_loader import (
    case_skip_reason,
    parse_statement_case,
    resolve_statement_corpus_root,
)


def test_phase0_statement_snapshot_capture():
    if os.getenv("FINANCE_TRACKER_RUN_CORPUS_SNAPSHOT") != "1":
        pytest.skip("Set FINANCE_TRACKER_RUN_CORPUS_SNAPSHOT=1 to collect local statement snapshots.")

    root = resolve_statement_corpus_root()
    if root is None:
        pytest.skip("Statement corpus not found. Set FINANCE_TRACKER_STATEMENT_CORPUS_ROOT.")

    snapshots = []
    skipped = []

    for case in PHASE0_CASES:
        skip_reason = case_skip_reason(case, root)
        if skip_reason:
            skipped.append({"case": case.key, "reason": skip_reason})
            continue

        snapshots.append(parse_statement_case(case, root))

    assert snapshots, "No statement cases were available for snapshot capture."

    print(
        json.dumps(
            {
                "root": str(root),
                "snapshots": snapshots,
                "skipped": skipped,
            },
            indent=2,
            sort_keys=True,
        )
    )