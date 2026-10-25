"""Deterministic landing-batch plan and data flaw injections.

Pure Python module with no Spark dependency so it can be tested locally.
"""

FINAL_BATCH = 3
SAMPLE_MOD = 500

BATCHES = {
    1: {"start": "1995-01-01", "end": "1995-05-01", "snapshot_date": "1995-01-01"},
    2: {"start": "1995-05-01", "end": "1995-09-01", "snapshot_date": "1995-07-01"},
    3: {"start": "1995-09-01", "end": "1996-01-01", "snapshot_date": "1995-10-01"},
}

SEGMENTS = ["AUTOMOBILE", "BUILDING", "FURNITURE", "HOUSEHOLD", "MACHINERY"]


def segment_after(segment: str) -> str:
    """Deterministic cyclic segment change (5 observed codes)."""
    return SEGMENTS[(SEGMENTS.index(segment) + 1) % len(SEGMENTS)]


def segment_changes(batch: int, customer_keys: list[int]) -> list[tuple[int, int]]:
    """[(customer_key, change_number)] for customers that change segment in batch.
    First 5 change in batch 2; next 5 change in batch 3; first 2 change again in batch 3.
    """
    sorted_keys = sorted(customer_keys)
    if batch == 2:
        return [(k, 1) for k in sorted_keys[:5]]
    if batch == 3:
        return [(k, 1) for k in sorted_keys[5:10]] + [(k, 2) for k in sorted_keys[:2]]
    return []


# Injections: (rule name, WHERE predicate on source columns, action).
# Action None duplicates whole rows; (col, SQL expr) modifies column values.
# Sampled keys are multiples of 500; predicates use residues divisible by 500 (~2% per rule).
ORDERS_RULES = [
    ("orders_null_customer_key", "o_orderkey % 25000 = 0", ("o_custkey", "NULL")),
    ("orders_negative_totalprice", "o_orderkey % 25000 = 500", ("o_totalprice", "-o_totalprice")),
]

LINEITEM_RULES = [
    ("lineitem_nonpositive_quantity", "l_orderkey % 25000 = 1000", ("l_quantity", "-l_quantity")),
    ("lineitem_discount_over_one", "l_orderkey % 25000 = 1500", ("l_discount", "l_discount + 1")),
    ("lineitem_exact_duplicate", "l_orderkey % 25000 = 2000", None),
]

CUSTOMER_RULES = []

# Five valid batch-3 orders whose lines land early in batch 2 (delayed headers).
EARLY_ORDER_PREDICATE = "o_orderkey % 25000 = 2500"
EARLY_ORDER_LIMIT = 5
