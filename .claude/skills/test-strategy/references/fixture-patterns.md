# Fixture Patterns – Happy Bank Tests

Test doubles and helper patterns extracted from the real Happy Bank test files.

---

## Test Doubles (Dummy Classes)

The codebase uses lightweight dummy classes instead of deep mocking. Create these in the test file that needs them.

### `DummyAccount`

```python
class DummyAccount:
    def __init__(self, id=1, name="Savings", balance=100):
        self.id = id
        self.name = name
        self.balance = balance
```

Used in: `test_account_repository.py`, `test_account_service.py` 

Match the fields to what the code under test actually reads (existing files use minimal variants).

### `AccountServiceDouble`

A recording test double for bank service tests — captures all calls instead of using `Mock`.

```python
class AccountServiceDouble:
    def __init__(self):
        self.deposits = []
        self.withdrawals = []
        self.transfers = []

    def deposit_money(self, account_id, amount):
        self.deposits.append((account_id, amount))

    def withdraw_money(self, account_id, amount):
        self.withdrawals.append((account_id, amount))

    def transfer_money(self, from_account_id, to_account_id, amount):
        self.transfers.append((from_account_id, to_account_id, amount))
```

Used in: `test_bank_service.py`

---

## Validator Test Doubles

For bank services that accept a validator function:

```python
def dummy_validator(amount: int) -> ValidationResult:
    """Always succeeds."""
    return ValidationResult.success()

def strict_amount_validator(amount: int) -> ValidationResult:
    """Fails above 10000 — for testing limit enforcement."""
    if amount > 10000:
        return ValidationResult.error("Amount cannot exceed 10000.")
    return ValidationResult.success()
```

Used in: `test_bank_service.py` (ATM and Online service tests)

---

## Mocked Repository Pattern

Services take a repository in the constructor; pass a `Mock()` and assert on calls (see `test_health_service.py`):

```python
def test_check_health_returns_ok_status() -> None:
    repo = Mock()
    result = HealthService(repo).check_health()
    assert result == {"status": "ok"}
    repo.check_database.assert_called_once_with()
```

Used in: `test_account_service.py`, `test_health_service.py`, `test_account_repository.py` (mock session)

---

## API Test Pattern (FastAPI)

Override dependencies via `app.dependency_overrides`, always clear in `finally`:

```python
from fastapi.testclient import TestClient
from app.api.dependencies import get_account_service
from app.main import app

def _get_test_client(service_mock):
    app.dependency_overrides[get_account_service] = lambda: service_mock
    return TestClient(app)

def test_get_account_endpoint_returns_200():
    service = Mock()
    service.get_account_by_id.return_value = DummyAccount()
    client = _get_test_client(service)
    try:
        response = client.get("/account/1")  # check app/main.py for any router prefix
        assert response.status_code == 200
    finally:
        app.dependency_overrides.clear()
```

---

## When to Use What

| Need | Approach |
|---|---|
| Service test (mock repo) | `Mock()` for repo, verify `.assert_called_once_with()` |
| Repository test (mock session) | `Mock()` for SQLModel session, verify `.exec()`, `.add()` |
| Bank service test (verify delegation) | `AccountServiceDouble` recording double |
| Validator test | Direct instantiation, no mocks needed |
| API test | `TestClient` + dependency override + `finally` cleanup |
