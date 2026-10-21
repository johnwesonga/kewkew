# Visitor-flow data model

## Scope and principles

This is the logical data model for the initial visitor flow in [the visitor stories](visitor-flow-user-stories.md). It covers a published queue, anonymous or name-required ticket creation, private ticket tracking, and durable state history. It does not define staff authentication, full organization setup, notification delivery, or analytics storage.

The initial design uses PostgreSQL through AshPostgres and keeps the application as a modular monolith. Visitors do not need account records. The ticket is the visitor's durable queue record; a public ticket number is for recognition, while a separate secret grants access to the private tracking page.

## Entity relationship sketch

```mermaid
erDiagram
    LOCATION ||--o{ QUEUE : hosts
    SERVICE ||--o{ QUEUE : serves
    QUEUE ||--o{ QUEUE_SESSION : runs
    QUEUE_SESSION ||--o{ TICKET : contains
    TICKET ||--o{ TICKET_EVENT : records
    TICKET ||--o{ TRACKING_CREDENTIAL : grants

    LOCATION {
      uuid id
      string name
      string timezone
    }
    SERVICE {
      uuid id
      uuid location_id
      string name
      boolean active
    }
    QUEUE {
      uuid id
      uuid location_id
      uuid service_id
      string public_slug
      string identity_policy
      integer max_active_tickets
    }
    QUEUE_SESSION {
      uuid id
      uuid queue_id
      string status
      integer next_ticket_number
      bigint next_queue_sequence
      timestamptz opened_at
      timestamptz closed_at
    }
    TICKET {
      uuid id
      uuid queue_session_id
      integer ticket_number
      integer queue_sequence
      string status
      string first_name
      string last_name
      timestamptz joined_at
      timestamptz called_at
      timestamptz started_at
      timestamptz completed_at
      timestamptz cancelled_at
    }
    TICKET_EVENT {
      uuid id
      uuid ticket_id
      string from_status
      string to_status
      string actor_type
      timestamptz occurred_at
    }
    TRACKING_CREDENTIAL {
      uuid id
      uuid ticket_id
      string token_digest
      timestamptz expires_at
      timestamptz revoked_at
    }
```

`Location` and `Service` are included to show the queue's context. Their complete ownership, staff membership, and configuration schema belongs to the business foundation stories. If a location can offer a service at multiple locations, service ownership should be normalized differently; decide this when those stories are scoped.

## Entities

### Queue

Represents reusable configuration for a line serving a service at a location. A queue can be reused across many operating sessions; closing a session does not delete the queue or its ticket history.

| Field | Type | Rules and purpose |
|---|---|---|
| `id` | UUID | Internal primary key; never used as the public tracking secret. |
| `location_id` | UUID | Required owning location. |
| `service_id` | UUID | Required service being provided. |
| `public_slug` | String | Unique, non-sequential link component for the join page; may be rotated/revoked. |
| `identity_policy` | Enum | `anonymous` or `name_required`; source of truth for join form and validation. |
| `max_active_tickets` | Integer, nullable | Optional capacity; null means no configured cap. |
| `created_at`, `updated_at` | Timestamps | Audit timestamps. |

The queue identity policy is read from the persisted queue during ticket creation. Do not accept the identity policy from visitor-submitted parameters. Store the policy on the queue; duplicating it on each ticket is not needed for the initial workflow unless the product later needs a historical snapshot of the collection policy.

### Queue session

Represents one operating period for a reusable queue. A manager opens a new session when the line begins accepting visitors and closes it when that operating period ends. A session has one queue and retains its own ticket sequence and history.

| Field | Type | Rules and purpose |
|---|---|---|
| `id` | UUID | Internal primary key. |
| `queue_id` | UUID | Required reusable queue configuration. |
| `status` | Enum | Initially `open`, `paused`, or `closed`; only an open session accepts joins. |
| `next_ticket_number` | Integer | Starts at 1 for each new session; allocated atomically for accepted tickets. |
| `next_queue_sequence` | Bigint | Starts at 1 for each new session; stable FIFO order, independent of displayed ticket number. |
| `opened_at` | UTC timestamp | When the session started accepting visitors. |
| `closed_at` | UTC timestamp, nullable | When the session stopped. |
| `created_at`, `updated_at` | UTC timestamps | Audit timestamps. |

Only one non-closed session may exist for a queue at a time. Pausing a session temporarily disables joins but does not end the session or reset numbering. Closing it ends that run; opening the queue again creates a new session and numbering starts again at 1. Existing tickets always remain attached to their original session.

### Ticket

Represents one visitor's admission to a queue.

| Field | Type | Rules and purpose |
|---|---|---|
| `id` | UUID | Internal identifier. |
| `queue_session_id` | UUID | Required operating session; queue and location context are reached through this association. |
| `ticket_number` | Integer | Visitor-facing number, unique within a session. Starts at 1 in every new session; it is not an authorization secret. |
| `queue_sequence` | Bigint | Stable FIFO sequence assigned at join time within the session. Position is derived from this value and current session state, not stored as a mutable counter on each ticket. |
| `status` | Enum | Initially `waiting`, `called`, `serving`, `completed`, `cancelled`, or `no_show`. |
| `first_name` | String, nullable | Required when the queue policy is `name_required`; must be null for `anonymous`. |
| `last_name` | String, nullable | Required when the queue policy is `name_required`; must be null for `anonymous`. |
| `joined_at` | UTC timestamp | When the ticket was admitted. |
| `called_at` | UTC timestamp, nullable | Latest call transition, if any. |
| `started_at` | UTC timestamp, nullable | When service began, if any. |
| `completed_at` | UTC timestamp, nullable | When completed, if any. |
| `cancelled_at` | UTC timestamp, nullable | When cancelled by visitor/staff, if applicable. |
| `inserted_at`, `updated_at` | UTC timestamps | Persistence timestamps. |

Names should be trimmed and validated server-side. Avoid storing a combined full name when separate fields are required. Anonymous tickets have both name fields null. No contact details are included in the first visitor-flow model.

### Ticket event

An append-only record of a ticket transition. This supports status recovery, an audit trail, and later wait-time analysis.

| Field | Type | Rules and purpose |
|---|---|---|
| `id` | UUID | Internal primary key. |
| `ticket_id` | UUID | Required ticket. |
| `from_status` | Enum, nullable | Null for the initial `joined` event. |
| `to_status` | Enum | Status after the transition. |
| `actor_type` | Enum | Initially `visitor`, `staff`, or `system`; a staff user ID can be added with the staff model. |
| `actor_id` | UUID, nullable | Optional reference to an authenticated actor when available. |
| `occurred_at` | UTC timestamp | Event time, assigned by the server. |
| `metadata` | Map/JSONB, nullable | Small non-sensitive operational details only; never place tracking tokens or unnecessary personal data here. |

The ticket's `status` and timestamps are the fast current-state projection. The event rows are the durable history. Update both in one transaction and prohibit arbitrary visitor writes to status.

### Tracking credential

Authorizes access to exactly one ticket's private tracking page.

| Field | Type | Rules and purpose |
|---|---|---|
| `id` | UUID | Internal primary key. |
| `ticket_id` | UUID | Required ticket. |
| `token_digest` | Binary or fixed-length string | Unique digest of a high-entropy random token. Store only the digest, never the raw token. |
| `created_at` | UTC timestamp | Credential creation time. |
| `expires_at` | UTC timestamp, nullable | Optional until a token lifetime is selected. |
| `revoked_at` | UTC timestamp, nullable | Revocation time; a revoked token cannot be used. |

Generate a cryptographically random bearer token with sufficient entropy, show the raw value only in the returned link, and hash it before persistence. Use a constant-time comparison where digest verification is performed in application code. The public ticket number, queue slug, and internal UUID must not substitute for this credential. A visitor can use the same credential to view and, when policy permits, cancel their own ticket.

## State model

```mermaid
stateDiagram-v2
    [*] --> waiting: join accepted
    waiting --> called: staff calls
    waiting --> cancelled: visitor/staff cancels
    waiting --> no_show: staff marks no-show
    called --> serving: service starts
    called --> cancelled: cancellation allowed
    called --> no_show: call expires / staff marks
    serving --> completed: service ends
    serving --> no_show: staff resolves
    completed --> [*]
    cancelled --> [*]
    no_show --> [*]
```

This is a candidate transition graph. The first join story only needs `waiting`; called/serving/completed/no-show transitions depend on staff workflows. A business decision is needed on visitor cancellation after the ticket is called or service begins. Terminal tickets do not count toward active capacity or queue position.

## Derived values

Do not persist values that can be calculated reliably from current tickets:

- **Position**: count eligible active tickets in the same queue session with an earlier `queue_sequence`, applying the defined status rules.
- **Waiting count**: count tickets in position-bearing states.
- **Estimated wait (future nice-to-have)**: out of scope for the initial release. If added later, estimate from active tickets ahead and completed-service duration history; return “estimate unavailable” until there is sufficient input. If computed on demand becomes expensive, cache it only with a clear invalidation rule.
- **Queue availability**: derive joinability from current session status and active-ticket count versus optional capacity within the join transaction.

Define the position-bearing states explicitly alongside the queue transition implementation. At minimum, cancelled, completed, and no-show tickets no longer count. Whether `called` and `serving` count as ahead of another visitor depends on the service model and must be consistent in the staff and visitor views.

## Constraints and indexes

- Foreign keys from queue to location/service, session to queue, ticket to session, and event/credential to ticket.
- Unique index on `queues.public_slug`.
- Unique partial index on `queue_sessions(queue_id)` for sessions whose status is `open` or `paused`, so a queue has at most one current session.
- Unique index on `(tickets.queue_session_id, tickets.ticket_number)`; numbers can repeat across sessions, but not within one session.
- Unique index on `(tickets.queue_session_id, tickets.queue_sequence)`.
- Check constraint or Ash validation ensuring `ticket_number > 0`, `queue_sequence > 0`, and positive `max_active_tickets` when present.
- Check constraint (and domain validation) enforcing name fields: both null for anonymous tickets, both non-empty for name-required tickets. Because PostgreSQL cannot directly enforce a cross-table queue policy with a simple check, enforce policy in the transactional create action; optionally snapshot the policy if database-level enforcement becomes a requirement.
- Index `(tickets.queue_session_id, status, queue_sequence)` for active queue and position lookups.
- Index `(ticket_events.ticket_id, occurred_at)` for ticket history.
- Unique index on `tracking_credentials.token_digest`; index active credentials by `ticket_id`.
- Consider partial indexes for active tickets once query shape and status rules are established.

## Join transaction

Ticket creation must be one server-side operation with the following shape:

1. Resolve the public queue slug and its current session; load the queue's identity policy.
2. Lock the current session row or use an equivalent atomic mechanism to serialize number/sequence allocation and capacity checks.
3. Recheck that the session is open and below capacity while holding the lock.
4. Validate input against the queue identity policy: discard/reject unexpected names for anonymous joins; require normalized first and last names for `name_required`.
5. Allocate the next display number and queue sequence atomically from the session, starting at 1 for a new session.
6. Insert the ticket in `waiting` state and its initial event.
7. Generate a tracking token, store only its digest, and return the raw token once to build the private link.
8. Commit all records together; on any failure, roll back the ticket and both session counters so rejected joins do not consume a number or sequence.

Repeated submit handling needs an idempotency strategy. A short-lived join-attempt key can be unique per queue and request attempt, but must not be used as the tracking credential. Decide whether retries should return the already-created ticket link or ask the visitor to restart if the original response was lost.

## Ash domain and resource boundary

The initial resource scaffold is in place:

- `Kewkew.Business` owns `Location` and `Service`.
- `Kewkew.Queues` owns `Queue`, `QueueSession`, `Ticket`, `TicketEvent`, and `TrackingCredential`.
- AshPostgres persists these resources in PostgreSQL; the initial migration and resource snapshots are generated from their definitions.

This first pass defines the schema and read actions only. It does not yet provide a visitor-facing join action or public tracking interface. Add narrow interfaces such as `get_public_queue`, `join`, `get_by_tracking_token`, and `cancel_by_tracking_token` in focused implementation stories; avoid public generic CRUD actions. The join action must own the transaction and event publication must happen only after commit. Authorization for staff actions belongs in policy/action boundaries; public actions should accept only the public slug, allowed visitor fields, and scoped tracking credential.

## Open decisions

- What staff action or schedule closes a session and opens the next one? The ticket number reset behavior is decided: every new session starts at ticket number 1.
- How long does a tracking link remain valid, and when can it be revoked?
- Should a visitor retry receive the existing ticket or create a new one after an ambiguous network failure?
- Which statuses count as ahead in position and active capacity?
- Can visitors cancel after being called or after service begins?
- If estimated wait is added after the initial release, how many completed durations are required before showing it, and what is the fallback?
- What retention period applies to names and ticket/event records?
- Can a service be offered at multiple locations, or does each location own its own service definitions?

Resolve these as part of the related story before encoding policy in migrations or irreversible actions.
