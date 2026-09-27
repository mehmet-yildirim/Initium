Systematically diagnose and fix the described bug or error.

## Step 0: Branch Check

Verify you are on a feature branch (`fix/` prefix for bugs). If on `main` or `develop`, stop and create one first (see AGENTS.md → Git Workflow).

---

## Step 1: Restate the Problem
- What is the expected behavior?
- What is the actual behavior?
- Under what conditions does it occur? (always / sometimes / specific input)
- What error messages, stack traces, or logs are available?

## Step 2: Hypotheses
List 3–5 possible root causes, ordered from most to least likely. For each:
- What would cause this symptom?
- What evidence supports or contradicts this hypothesis?

## Step 3: Investigation Plan
For each hypothesis, describe:
- What to check (code, logs, database, network)
- What a positive result looks like
- What tools or commands to use

## Step 4: Diagnosis
Read the relevant code, logs, and error messages provided.
- Which hypothesis is most consistent with the evidence?
- What is the precise root cause?

## Step 5: Fix
Provide the corrected code with explanation:
- What exactly was wrong?
- Why does the fix work?
- Are there other places in the codebase with the same bug?

## Step 6: Verification
How do we confirm the fix works?
- What test to run
- What to observe
- How to add a regression test to prevent recurrence

## Step 7: Prevention
- What class of bug is this?
- How can we prevent it in the future? (linting rule, type improvement, pattern change, documentation)

---
Issue to debug: $ARGUMENTS
