# Product Decisions

## Completed tasks

Completed tasks should be kept, not deleted.

Current behavior:

- Tasks that are done remain in their board.
- Done tasks are treated as completed work and historical context.
- Dashboard attention areas should generally focus on active work, while completed tasks can still contribute to progress summaries.
- Delete should be reserved for accidental, duplicate, or unwanted tasks.

Future behavior to consider:

- Add an `archived_at` field for tasks.
- Add a board option to hide completed tasks.
- Add an action to archive completed tasks after a chosen time window.
- Keep archived tasks searchable and recoverable.

Product rule:

Done means completed. Archive means out of sight. Delete means remove forever.
