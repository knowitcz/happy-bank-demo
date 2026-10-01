# Applied HTSM – Happy Bank

Heuristic Test Strategy Model applied to the Happy Bank domain. Use this checklist during test plan design to ensure systematic coverage. Source: `docs/htsm.pdf` (Heuristic Test Strategy Model by James Bach).

---

## Product Elements

What the product IS — features and components to test.

| Element | Happy Bank Scope |
|---|---|
| Accounts | Get, balance tracking, withdraw, deposit, transfer between accounts |
| Health | Health endpoint, database connectivity check |
| Validation | Cash amount limits (ATM/Online), ValidationResult/ValidationError |
| Bank Services | BranchBankService (no limits), AtmBankService (validated), OnlineBankService (validated) |
| API Layer | REST endpoints, status codes, error responses, dependency injection |
| Persistence | SQLModel/SQLite, Alembic migrations, session management |
| Schemas | Account model (`app/models/account.py`) |

---

## Quality Criteria

What makes the product GOOD — quality attributes to verify.

| Criterion | What to verify in Happy Bank |
|---|---|
| Correctness | Balances update atomically on transfer; transaction records match operations |
| Data integrity | Insufficient balance raises ValueError; no partial transfers; rollback on failure |
| Reliability | Concurrent transfers don't corrupt balances; session cleanup on errors |
| Security | Input validation prevents negative/zero amounts; SQL injection via SQLModel parameterization |
| Performance | API response latency under load; DB query efficiency for transaction history |
| Usability | Clear error messages; transaction type derivation (DEPOSIT/WITHDRAWAL/TRANSFER) |
| Compatibility | API contract stability; schema backward compatibility |

---

## Test Techniques

HOW to test — techniques to apply.

| Technique | Application in Happy Bank |
|---|---|
| Boundary values | Amount = 0, 1, max_cash_limit, max_cash_limit+1; balance = 0 then withdraw |
| Equivalence partitioning | Valid amounts vs. negative vs. zero vs. over-limit; existing vs. nonexistent account IDs |
| State transitions | Account: created → deposit → withdraw → transfer; balance lifecycle |
| Error guessing | Double-spend, transfer to same account, nonexistent account, null fields |
| Scenario testing | Full flow: create account → deposit → transfer → verify balances |
| Stress testing | Multiple concurrent transfers on same account |
| Data flow | Verify transaction.source_account_id / target_account_id correctly null for deposit/withdrawal |

---

## Checklist for Test Plan Review

Use this when reviewing a test plan for completeness:

- [ ] Every Product Element has at least one happy-path test
- [ ] Every Quality Criterion has at least one targeted test
- [ ] At least 3 Test Techniques are applied
- [ ] Boundary values tested for amounts AND balances
- [ ] Error conditions tested for all service methods
- [ ] At least one end-to-end scenario across layers
- [ ] Validator behavior tested for each bank service variant (Branch/ATM/Online)
