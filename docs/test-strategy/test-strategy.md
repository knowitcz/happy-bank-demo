# Test Strategy — Happy Bank

## Goal
Ensure that the bank account and transfer system is functional, secure, reliable, and ready for deployment. Cover critical functionality, integrations, performance, and data integrity.

## Scope
- API for account management, transfers, and transactions
- Database persistence of transactions and account states
- End-to-end scenarios (e.g., transfer between accounts)
- Error and edge cases (insufficient balance, invalid inputs)

## Testing Levels
- Unit tests: business logic, input validation, balance calculations
- Integration tests: repository/DB, API endpoints, message queues (if present)
- End-to-end tests: complete API scenarios (transfer, balance verification, transaction recording)
- Smoke tests: basic health checks after deployment; target is `GET /health`, tested via a router-only app with an overridden service (importing `app.main` touches the real DB)
- Regression tests: critical scenarios after changes

## Test Types
- Functional: account CRUD, transfers, transaction list
- API: contract tests, status codes, error states; API contract tests are co-located as `app/api/test_*_routes.py` (`test_health_routes.py` is the first)
- Data integrity: atomic transactions, error rollback
- Performance: API latency, transfer load, DB throughput
- Security: authentication, authorization, input validation, SQL injection
- Reliability/Concurrency: race conditions during concurrent transfers
- Exploratory and negative testing: invalid amounts, non-existent accounts

## Test Data and Environment
- Isolated test DB (snapshots/containers) + restore/rollback capability
- Test accounts/fixtures: explicitly defined states (e.g., Vilhem: Secret 2000, Alice: Savings 500)
- Seed + teardown or transactional rollback for idempotent tests
- Identification of sensitive data and its masking

## Tools and Infrastructure
- Unit: pytest / Jest / xUnit depending on the stack
- API/E2E: pytest+requests, Postman/Newman, Playwright/Selenium (if UI exists)
- DB: testcontainers or local test DB + migration tooling
- CI: GitHub Actions / Azure Pipelines — run unit + integration + smoke on PRs, nightly runs for E2E/performance
- Monitoring/reporting: test reports (JUnit), coverage, Sentry/observability for deployment

## Test Design and Coverage
- Prioritize critical scenarios (money transfers, rollback, authorization)
- Define test cases: input, expected output, cleanup
- Map tests to acceptance criteria and user stories
- Measure coverage for business logic (not necessarily full 100% for infrastructure)

## CI/CD Integration
- PR gate: unit + lint + fast integration
- Merge: full integration + smoke
- Nightly: E2E + performance + security scans
- Fail-fast policy for critical tests

## Reporting and Metrics
- Test pass rate, flakiness, test duration
- Number of bugs/priorities identified by testing
- Time to fix (MTTR)
- Automated reports connected to PRs and Slack/Teams

## Risks and Mitigations
- Flaky tests: isolate and fix / quarantine
- Database state drift: use migrations + seed + teardown
- Parallel API changes: contract tests + consumer-driven contracts

## Test Maintenance
- Test reviews as part of PRs
- Periodic review and cleanup of old/outdated tests
- Documentation of test fixtures and test environment execution