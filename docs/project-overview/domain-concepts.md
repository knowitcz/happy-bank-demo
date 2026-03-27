# Happy Bank — Domain Concepts

## Core Models

| Concept | Model | Notes |
|---|---|---|
| Client | `Client` | Has a name and unique national number; owns multiple accounts |
| Account | `Account` | Has a name, balance (int), type, and belongs to one client |
| Transaction | `Transaction` | Records money movement; type derived from which account IDs are set |

## Transaction Type Derivation

The `Transaction` type is not stored explicitly — it is derived from the presence or absence of
`source_account_id` and `target_account_id`:

| `source_account_id` | `target_account_id` | Derived type |
|---|---|---|
| `None` | set | **DEPOSIT** |
| set | `None` | **WITHDRAWAL** |
| set | set | **TRANSFER** |
| `None` | `None` | **Invalid** — prevented by DB constraint |

## Related Documentation

- Architecture & layer mapping → [architecture.md](architecture.md)
- Transaction analysis (HB-9) → [../HB-9/analysis-developers.md](../HB-9/analysis-developers.md)
