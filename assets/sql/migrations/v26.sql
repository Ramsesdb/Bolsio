-- v26: backfill status for transactions that were created without one
-- (notably those auto-imported by the notification listener, CSV import,
-- or any legacy path that omitted the `status` column). A NULL status
-- silently excludes transactions from stats/budgets/goals because the
-- SQL filter `status IN (...)` never matches NULL.
--
-- Idempotent: once all NULLs are replaced the UPDATE is a no-op.
UPDATE transactions SET status = 'R' WHERE status IS NULL;
