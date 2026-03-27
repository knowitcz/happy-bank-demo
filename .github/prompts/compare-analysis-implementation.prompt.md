---
name: compare-analysis-implementation
description: "Compare one or more analysis files with the corresponding feature branch implementation and report missing, extra, or unverified work."
argument-hint: "Provide one or more analysis file paths"
agent: agent
---

# Compare Analysis Against Implementation

Compare the provided analysis files against the not-yet-merged implementation branch.

## Inputs

- One or more analysis files
- Optional extra context from the user

If the analysis files are not provided, ask for them.

## Branch and Commit Rules

1. Read all provided analysis files.
2. Extract the feature ID from the analysis.
3. If no feature ID can be determined, ask the user.
4. If more than one distinct feature ID is found, stop and ask the user which one to validate.
5. Use branch `feature/$ID` as the implementation branch.
6. Compare only the commits reachable from `feature/$ID` after the branching point from `main`.
7. Verify that every commit in that scope starts with the prefix `$ID:`.

## Validation Goals

Validate all of the following:

1. The Definition of Done in the analysis is fully satisfied.
2. Every scenario described in the analysis is implemented.
3. Every scenario described in the analysis is covered by tests, or there is a clear reason why test coverage is missing.
4. Relevant tests can be identified and run successfully.
5. The feature branch does not introduce additional functionality beyond the analysis.

Treat minor non-functional changes as acceptable when they are clearly incidental to the feature, for example:

- small refactors without behavioral change
- formatting or naming cleanup
- minimal test infrastructure adjustments
- minor documentation updates

Treat new user-visible behavior, new business rules, extra endpoints, extra screens, extra workflows, or extra feature scope as additional functionality and report it.

## Required Process

1. Read the analysis files carefully and extract:
   - feature ID
   - Definition of Done items
   - scenarios
   - explicit constraints
   - acceptance criteria
2. Inspect the implementation in `feature/$ID`.
3. Determine the branch point against `main` and inspect only the commits and file changes after that point.
4. Map each analysis item to implementation evidence.
5. Map each analysis item to test evidence.
6. Identify any changed files or behaviors that are not justified by the analysis.
7. Run the relevant tests when possible. Infer the appropriate commands from the repository instead of asking the user unless blocked.
8. If something cannot be verified, say exactly what evidence is missing.

## Output Format

Produce a concise review with these sections:

### Scope

- Analysis files reviewed
- Feature ID used
- Branch reviewed
- Branch point used
- Test commands executed, if any

### Findings

Provide a table with these columns:

| Area | Item | Status | Evidence | Reason |
|------|------|--------|----------|--------|

Use `PASS`, `FAIL`, `WARNING`, or `UNVERIFIED` for `Status`.

Include rows for:

- each Definition of Done item
- each scenario
- commit prefix validation
- additional functionality check
- test execution result

### Verdict

- Overall result
- Missing or incomplete items
- Additional functionality, if any
- Risks or follow-up questions

## Review Rules

- Do not modify code unless the user explicitly asks for fixes.
- Do not assume an item is implemented just because nearby code changed.
- Prefer direct evidence: code, tests, git history, and runnable commands.
- When evidence is partial, mark it `UNVERIFIED` instead of guessing.
- Be strict about missing required behavior and extra functionality.
- Be precise about why a minor extra change is acceptable.