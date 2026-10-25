# ADR-002: Canonical deterministic order hash

Status: **DESIGN SELECTED; collision check passed on live source (2026-10-25); phase-1 implementation pending**.

Interpret “hashed on the order key” as a deterministic cross-fact linkage key. Convert the validated natural key to BIGINT, then use `lower(sha2(cast(order_key AS STRING), 256))` in both facts. Orders are unique on the hash; lines are unique on `(order_key_hash, line_number)`. Keep the original key for restricted audits and reconciliation.

Other interpretations: physical distribution/partitioning by hash, or anonymization. Physical layout is a separate performance concern and needs trainer clarification if intended. Hashing a low-entropy integer does not anonymize it. Neither SHA-256 nor a natural-key join prevents multiplying a header across its lines; grain-aware aggregation does that.

Canonical casting avoids hashing `000123` in one source and `123` in another. Reject invalid/null keys before Gold. Verify one natural key maps to one non-null hash, no hash maps to several natural keys, and both facts agree for the same order. Do not partition the table into one partition per order hash.

Trade-off: a wider key and collision checks versus a reproducible cross-fact contract. The collision check is still required even though a SHA-256 collision is exceedingly unlikely at project scale.

Sources: local Package 02 image and [metric-view references](../references.md#modeling-and-history). Observed 2026-10-25: within the 1995 window, 1,136,308 distinct `o_orderkey` map to 1,136,308 distinct SHA-256 hashes — the collision check passes on live source (`evidence/runs/20261025T153202Z_profile_70cb9460/order_grain.json`). The trainer's physical-layout intent remains open; it does not block the selected logical design.
