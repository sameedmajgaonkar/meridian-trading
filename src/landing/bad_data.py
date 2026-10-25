"""Deterministic batch configuration and injection rules."""

SAMPLE_MOD = 500

BATCHES = {
    1: {"start": "1995-01-01", "end": "1995-05-01", "snapshot_date": "1995-01-01"},
    2: {"start": "1995-05-01", "end": "1995-09-01", "snapshot_date": "1995-07-01"},
    3: {"start": "1995-09-01", "end": "1996-01-01", "snapshot_date": "1995-10-01"},
}

NEXT_SEGMENT = {
    "AUTOMOBILE": "BUILDING",
    "BUILDING": "FURNITURE",
    "FURNITURE": "HOUSEHOLD",
    "HOUSEHOLD": "MACHINERY",
    "MACHINERY": "AUTOMOBILE",
}

# 4 injection rules by row position
ORDERS_RULES = [
    ("orders_null_customer_key", "rn = 3", ("o_custkey", "NULL")),
]

LINEITEM_RULES = [
    ("lineitem_negative_quantity", "rn = 5", ("l_quantity", "-l_quantity")),
    ("lineitem_discount_over_one", "rn = 11", ("l_discount", "l_discount + 1.0")),
    ("lineitem_duplicate", "rn = 23", None),
]


def get_segment_changes(batch: int, customer_keys: list[int]) -> list[int]:
    """Returns customer keys that change segment in this batch."""
    keys = sorted(customer_keys)
    if batch == 2:
        return keys[:5]
    if batch == 3:
        return keys[5:10] + keys[:2]
    return []
