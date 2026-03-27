# Fixture Patterns – Happy Bank Tests

Test doubles and helper patterns used across the Happy Bank test suite. These are extracted from real test files to ensure consistency.

---

## Test Doubles (Dummy Classes)

The codebase uses lightweight dummy classes instead of deep mocking. Create these in the test file that needs them.

### `DummyClient`

```python
class DummyClient:
    def __init__(self, id=1, name="Alice", national_number="123456", accounts=None):
        self.id = id
        self.name = name
        self.national_number = national_number
        self.accounts = accounts if accounts is not None else []
```

Used in: `test_client_service.py`, `test_client_routes.py`

### `DummyAccount`

```python
class DummyAccount:
    def __init__(self, id=1, name="Savings", balance=100, type="savings", client_id=1):
        self.id = id
        self.name = name
        self.balance = balance
        self.type = type
        self.client_id = client_id
```

Used in: `test_account_repository.py`, `test_client_routes.py`, `test_transaction_service.py`

Note: Some test files use a minimal variant with fewer fields (e.g. only `id`, `balance`, `client_id`). Match the fields to what the code under test actually reads.

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

## Helper Functions

### `_make_service()` (Transaction Service)

Factory that wires up mocked repos for transaction service tests:

```python
def _make_service(accounts=None, transactions=None, summary=None):
    account_repo = Mock()
    tx_repo = Mock()
    account_repo.get_by_client_id.return_value = accounts or []
    tx_repo.find_transactions.return_value = transactions or []
    tx_repo.get_summary.return_value = summary or {"total_incoming": 0, "total_outgoing": 0}
    return TransactionService(account_repo, tx_repo), account_repo, tx_repo
```

Used in: `test_transaction_service.py`

---

## API Test Pattern (FastAPI)

Override dependencies via `app.dependency_overrides`, always clear in `finally`:

```python
from fastapi.testclient import TestClient
from app.api.dependencies import get_client_service
from app.main import app

def _get_test_client(service_mock):
    app.dependency_overrides[get_client_service] = lambda: service_mock
    return TestClient(app)

# In tests:
def test_get_clients_endpoint_returns_200():
    service = Mock()
    service.get_all_clients.return_value = [DummyClient()]
    client = _get_test_client(service)
    try:
        response = client.get("/api/v1/client")
        assert response.status_code == 200
    finally:
        app.dependency_overrides.clear()
```

Used in: `test_client_routes.py`

---

## When to Use What

| Need | Approach |
|---|---|
| Service test (mock repo) | `Mock()` for repo, verify `.assert_called_once_with()` |
| Repository test (mock session) | `Mock()` for SQLModel session, verify `.exec()`, `.add()` |
| Bank service test (verify delegation) | `AccountServiceDouble` recording double |
| Validator test | Direct instantiation, no mocks needed |
| API test | `TestClient` + dependency override + `finally` cleanup |

---

## Test Patterns

### Testing Calculations
```python
class TestCalculateCarCost:
    """Testy pro výpočet nákladů na cestu autem."""

    def test_basic_calculation(self):
        """Základní výpočet."""
        cost = calculate_car_cost(200, 8.7, 35.50, 0.0)
        assert cost == 617.70

    def test_zero_distance(self):
        """Nulová vzdálenost."""
        cost = calculate_car_cost(0, 8.7, 35.50, 5.60)
        assert cost == 0.0
```

### Testing with Dates (Edge Cases)
```python
def test_boundary_5_hours(self, constants, employee):
    """Přesně 5 hodin = level 1 stravné."""
    order = _make_order(
        date(2025, 1, 6), date(2025, 1, 6),
        [_make_trip(date(2025, 1, 6), time(8, 0), time(13, 0))]
    )
    # ...
```

### Testing Validation
```python
def test_missing_field(self):
    """Chybějící povinné pole."""
    result = validate(order_with_missing_field)
    assert any(m.severity == "ERROR" for m in result.messages)
```

### Config Loader Tests with `tmp_path`
```python
def test_save_and_load(self, tmp_path):
    """Uložení a načtení cestovního příkazu."""
    config_dir = tmp_path / "config"
    config_dir.mkdir()
    # Create test config files in tmp_path...
    save_travel_order(order, str(tmp_path / "data"))
    loaded = load_travel_order(str(tmp_path / "data" / "CP_TEST" / "travel_order.yaml"))
    assert loaded.metadata.id == order.metadata.id
```

---

## Coverage Expectations

| Module | Minimum coverage | Focus areas |
|---|---|---|
| `calculator.py` | 90%+ | All band transitions, rounding, optimization |
| `validator.py` | 85%+ | All validation rules, edge cases |
| `loader.py` | 80%+ | YAML roundtrip, date/time parsing |
| `models.py` | 70%+ | Validators, properties, computed fields |
| `pdf_generator.py` | 50%+ | Core generation flow (hard to test visually) |
| `cli/main.py` | 30%+ | Integration tests cover the main flows |
