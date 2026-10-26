"""The fixed replay window and customer segment cycle."""

SAMPLE_MOD = 500
BATCHES = {
    1: {"start": "1995-01-01", "end": "1995-05-01", "snapshot_date": "1995-01-01"},
    2: {"start": "1995-05-01", "end": "1995-09-01", "snapshot_date": "1995-07-01"},
    3: {"start": "1995-09-01", "end": "1996-01-01", "snapshot_date": "1995-10-01"},
}
NEXT_SEGMENT = {
    "AUTOMOBILE": "BUILDING", "BUILDING": "FURNITURE", "FURNITURE": "HOUSEHOLD",
    "HOUSEHOLD": "MACHINERY", "MACHINERY": "AUTOMOBILE",
}


def get_segment_changes(batch, customer_keys):
    return sorted(customer_keys)[:2] if batch in (2, 3) else []
