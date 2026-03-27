# Pending Decision: Request Data Flow Diagram

**Status**: Awaiting specialist input
**Source**: Comparison with cestak project conventions (2026-03-27)
**Related issue**: N/A — raised during cross-project instruction review

## Context

The cestak project includes a data flow diagram in its copilot instructions showing how data moves through the system layers:

```
YAML config → loader → Pydantic models → calculator → results → ...
```

Happy Bank currently documents the **layer hierarchy** (which layer depends on which) but not the **runtime request flow** (how a request travels through the layers).

## Proposed Addition

A request data flow diagram for Happy Bank, e.g.:

```
HTTP request → API route → Service → Repository → Database
                  ↓
              Validator (input validation, no exceptions)
```

The human prefers this to live in **project documentation** (`docs/`) rather than in `copilot-instructions.md`.

## Questions for Specialists

1. **Architect**: Would a request data flow diagram add clarity beyond the existing layer diagram? Should it cover response flow as well?
2. **Product Owner**: Is this worth the maintenance cost?
3. **Tester**: Would it help when designing integration test scenarios?

## Decision

_Pending — orchestrator should route to architect, product-owner, tester._
