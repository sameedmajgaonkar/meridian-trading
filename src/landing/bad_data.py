"""Deterministic landing-batch plan shared by simulate.py and the tests.

Pure module: no spark import, safe to unit-test locally. Keep values in sync
with docs/data_contract.md (synthetic fixture contract) — the quality gate's
manifest reconciliation is the real guard; these constants define the plan.
"""

# Locked window (ADR-001): three disjoint order-date shards covering the whole
# window exactly (12 months / 3 batches = 4 months each). Each batch also
# re-lands the FULL selected customer population (a complete snapshot) stamped
# with a business-effective date (ADR-004).
BATCH_MONTHS = 4
BATCH_EFFECTIVE_DATES = {1: "1995-01-01", 2: "1995-07-01", 3: "1995-10-01"}

SEGMENTS = ["AUTOMOBILE", "BUILDING", "FURNITURE", "HOUSEHOLD", "MACHINERY"]

# SCD2 demo seeds picked from the Phase 0 profile (docs/data_contract.md):
# batch 2 moves the first five once, batch 3 moves the rest once and the first
# two again -> two customers reach three versions (baseline + two changes).
SCD_CANDIDATES = [210556, 738508, 373396, 12916, 51769,
                  254500, 299800, 325726, 537313, 69775]


def segment_after(segment: str) -> str:
    """Deterministic cyclic segment change (5 observed codes, data contract)."""
    return SEGMENTS[(SEGMENTS.index(segment) + 1) % len(SEGMENTS)]


def changes_for_batch(batch: int) -> list[tuple[int, int]]:
    """[(customer_key, change_number)] applied in this batch's snapshot."""
    if batch == 2:
        return [(k, 1) for k in SCD_CANDIDATES[:5]]
    if batch == 3:
        return ([(k, 1) for k in SCD_CANDIDATES[5:]]
                + [(k, 2) for k in SCD_CANDIDATES[:2]])
    return []


def shard_range(start_iso: str, batch: int) -> tuple[str, str]:
    """[start, end) month-based third of the locked window; end exclusive."""
    import datetime

    y, m = divmod(int(start_iso[:4]) * 12 + int(start_iso[5:7]) - 1
                  + BATCH_MONTHS * batch, 12)
    end = f"{y:04d}-{m + 1:02d}-01"
    y, m = divmod(y * 12 + m - BATCH_MONTHS, 12)
    start = f"{y:04d}-{m + 1:02d}-01"
    return start, end


# Injections: (rule name, WHERE-style predicate on source columns, action).
# Action None duplicates the whole row; otherwise (column, SQL replacement).
# Predicates are keyed on source values, so reruns are deterministic.
ORDERS_RULES = [
    ("orders_null_customer_key", "o_orderkey % 150001 = 3", ("o_custkey", "NULL")),
    ("orders_negative_totalprice", "o_orderkey % 200003 = 11", ("o_totalprice", "-o_totalprice")),
]
LINEITEM_RULES = [
    ("lineitem_nonpositive_quantity", "l_orderkey % 175001 = 7", ("l_quantity", "-l_quantity")),
    ("lineitem_discount_over_one", "l_orderkey % 225007 = 9", ("l_discount", "l_discount + 1")),
    ("lineitem_exact_duplicate", "l_orderkey % 275017 = 13", None),
]
CUSTOMER_RULES = [
    ("customer_exact_duplicate", "c_custkey % 400009 = 17", None),
]
# Five valid batch-3 orders whose lines land early in batch 2 (delayed headers).
EARLY_ORDER_PREDICATE = "o_orderkey % 50021 = 1"
EARLY_ORDER_LIMIT = 5
