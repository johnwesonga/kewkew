# Staff and admin flow user stories

## Goal

Let authorized staff see the active queue and move tickets through service in a reliable order. Queue changes are persisted with an audit event and appear promptly on connected staff and visitor screens.

These stories cover day-to-day queue operations. Queue configuration and operating-session management are specified in [admin-queue-configuration-user-stories.md](admin-queue-configuration-user-stories.md). Organization setup, location and service management, and staff invitations are specified in [organization-location-admin-user-stories.md](organization-location-admin-user-stories.md). Admins can manage staff access; queue operators can perform the queue actions granted to them.

Staff authentication uses [AshAuthentication](https://ash-authentication.hexdocs.pm/readme.html) and its [Phoenix integration](https://ash-authentication-phoenix.hexdocs.pm/) with email and password sign-in. Public self-registration is disabled. The first organization administrator is provisioned by a one-time bootstrap task; administrators provision subsequent staff accounts. AshAuthentication establishes the identity and sign-in session; Kewkew's active membership and location assignments determine which business data that identity can access. Authentication alone does not grant access to business data.

## Roles and shared rules

- **Queue operator**: can view and operate queues at assigned locations.
- **Administrator**: can manage organization membership and queue configuration, and can perform queue operations where assigned.
- Every read and action is scoped to the staff member's organization and permitted locations. Knowing a queue or ticket ID does not grant access.
- The active queue board lists tickets in stable queue-sequence order and identifies each by ticket number. It shows a visitor's name only when the queue collects a name and the staff member is authorized to see it.
- Queue actions are commands, not arbitrary edits to ticket status. Each action validates the current status and writes the ticket change and its `TicketEvent` atomically.
- Updates are published only after commit. Connected staff boards and the affected visitor ticket page receive the new state without exposing another visitor's private tracking credential or unnecessary personal details.
- If a client is disconnected or has stale state, it reloads the persisted queue and ticket state when it reconnects. A stale action is rejected with a clear message and the latest state is shown.

## Stories

**Status tracking** — `Complete` means the story's acceptance criteria are implemented; `In progress` means some criteria remain; `Planned` means implementation has not started. Status tracks implementation in this repository, not production release.

### SF-1: Access assigned queues

**Status** — In progress

**User story** — As a staff member, I want to sign in and see only the queues I am assigned to so that visitor information and queue controls are limited to my work.

**Acceptance criteria**

- A staff member must sign in through the AshAuthentication-based staff flow before opening staff queue screens or invoking queue actions.
- Staff account creation is administrator controlled; public self-registration is disabled.
- A successfully authenticated identity with no active Kewkew staff membership cannot access organization or queue data.
- Staff can access only organizations and locations granted to their membership.
- The staff landing page lists queues only at locations the staff member can access.
- An administrator can grant and revoke staff membership and location access; operators cannot change access unless explicitly granted an admin role. The last active organization administrator cannot be revoked.
- Unauthorized or cross-organization requests reveal no queue or visitor data and cannot change ticket state.

**Dependencies** — Organization/location ownership, staff membership, AshAuthentication plus its Phoenix integration, and role policy. The initial sign-in strategy is email and password; account bootstrap and administrator provisioning are controlled server-side workflows.

### SF-2: Monitor a queue

**Status** — Complete

**User story** — As a queue operator, I want to see waiting visitors and their current states so that I can serve the queue in order.

**Acceptance criteria**

- The queue board shows waiting, called, and serving tickets for the selected active queue session.
- Tickets appear in stable queue order and show the public ticket number, current state, and required visitor name when available to the operator.
- The board distinguishes an empty queue from a queue that is paused or closed.
- The board updates when a visitor joins, leaves, or a staff action changes a ticket.
- On reconnect or manual refresh, the board recovers the latest persisted state.

**Dependencies** — SF-1; active queue sessions and visitor ticket creation.

### SF-3: Call the next visitor

**Status** — Complete

**User story** — As a queue operator, I want to call the next waiting visitor so that service follows queue order.

**Acceptance criteria**

- The action selects the waiting ticket with the lowest queue sequence in the selected session.
- The ticket moves from `waiting` to `called`, the call time and staff actor are recorded, and a history event is written in the same transaction.
- If there is no waiting ticket, the action is unavailable and the board explains that nobody is waiting.
- Concurrent operators cannot call the same ticket twice. Concurrent calls may claim successive waiting tickets; each action selects the earliest ticket still waiting when its transaction runs.
- If the ticket changed since the operator loaded the board, the stale command does not overwrite the newer state.

**Dependencies** — SF-1, SF-2; atomic queue transition actions and ticket history.

### SF-4: Start serving a called visitor

**Status** — Complete

**User story** — As a queue operator, I want to mark a called visitor as being served so the visitor and other staff know service has started.

**Acceptance criteria**

- Only a ticket in `called` state can move to `serving` through this action.
- The start time and staff actor are recorded with the transition event.
- A repeated or stale action cannot create duplicate transition events or move a ticket from a terminal state.
- The queue board and that visitor's private page show the serving state promptly.

**Dependencies** — SF-1 through SF-3; atomic transition actions.

### SF-5: Complete service

**Status** — Complete

**User story** — As a queue operator, I want to complete a visitor's service so their ticket leaves the active queue and the next visitor's position is accurate.

**Acceptance criteria**

- Only a ticket in `serving` state can be completed.
- Completion time and staff actor are recorded with a `serving` to `completed` history event.
- The completed ticket is removed from active queue and position calculations.
- The queue board and visitor page show completion promptly; repeated completion does not create another event.

**Dependencies** — SF-1, SF-2, SF-4; active-ticket and position rules.

### SF-6: Skip a visitor who does not respond

**Status** — Complete

**User story** — As a queue operator, I want to mark a called visitor as a no-show so the queue can continue when they do not respond.

**Acceptance criteria**

- The skip action is available only for a `called` ticket.
- The ticket moves to terminal `no_show` state and a staff-attributed history event is recorded.
- A skipped ticket no longer counts in active capacity or queue position calculations.
- The visitor page shows that the ticket is no longer active; the operator can then call the next waiting visitor.
- Repeating or issuing a stale skip command cannot create another transition or alter a terminal ticket.

**Dependencies** — SF-1 through SF-3; no-show state and terminal ticket handling.

### SF-7: Cancel a ticket as staff

**Status** — Complete

**User story** — As a queue operator, I want to cancel a ticket when a visitor or business circumstance requires it so the queue no longer holds that place.

**Acceptance criteria**

- Staff can cancel a ticket in `waiting` or `called` state and must confirm the action.
- The ticket moves to terminal `cancelled` state, records cancellation time and staff actor, and appends a history event atomically.
- A serving ticket cannot be cancelled through this action; the operator completes service or follows a separately defined exception workflow.
- Cancelled tickets no longer count toward queue capacity or position.
- Repeating or issuing a stale cancellation cannot create duplicate events or overwrite another terminal state.

**Dependencies** — SF-1, SF-2; cancellation transition action and confirmation UI.

### SF-8: See committed changes across connected screens

**Status** — Complete

**User story** — As staff or a visitor with a connected ticket page, I want queue changes to appear promptly so everyone acts on the same state.

**Acceptance criteria**

- After a successful join, call, start, completion, skip, or cancellation commits, connected staff boards update without a manual refresh.
- The affected visitor's private ticket page updates promptly with their own status and position.
- Updates are sent only after the database transaction commits; failed actions do not publish success.
- Broadcast payloads contain only the identifiers and state needed to reload or update a view; they do not include tracking tokens or visitor names unless the receiving staff view is authorized to display that name.
- A disconnected client reloads persisted state on reconnect and does not rely on having received every event.

**Dependencies** — Queue transition stories; Phoenix PubSub or equivalent update delivery; reconnect refresh behavior.

### SF-9: Requeue a returning no-show visitor

**Status** — Complete

**User story** — As a queue operator, I want to requeue a visitor who returns after being marked as a no-show so they can receive service without jumping ahead of visitors already waiting.

**Acceptance criteria**

- The recall action is available only for a `no_show` ticket in the current queue session.
- Recalling moves the ticket from `no_show` to `waiting`, preserves its displayed ticket number, and assigns it a new queue sequence at the end of the line.
- The staff actor and transition are recorded in a `TicketEvent` in the same transaction as the ticket and queue-session updates.
- The recalled ticket counts toward active capacity and queue position again, and appears at the end of the staff board's waiting order.
- The visitor's private page returns to a waiting status and shows its current position; connected staff boards and the visitor page reflect the change promptly.
- Completed and cancelled tickets cannot be recalled. Repeated or stale recall commands cannot change ticket state or create duplicate events.
- Concurrent recalls receive distinct queue sequences and cannot put a returning visitor ahead of a ticket that was already waiting.

**Dependencies** — SF-1, SF-2, SF-6, and SF-8; atomic queue-sequence allocation and ticket transition history.

## Initial transition policy

| Current state | Staff action | Result |
| --- | --- | --- |
| `waiting` | Call next | `called` |
| `waiting` | Cancel | `cancelled` |
| `called` | Start serving | `serving` |
| `called` | Skip | `no_show` |
| `called` | Cancel | `cancelled` |
| `serving` | Complete | `completed` |
| `no_show` | Recall | `waiting` at the end of the line |

Completed and cancelled tickets are terminal for this initial staff flow. A no-show ticket can return to waiting only through SF-9. Cancelling after service starts, call timeouts, and automatically calling the next visitor after a skip are outside these stories unless added as separate requirements.

## Suggested implementation order

1. **Staff access foundation** — SF-1, including AshAuthentication integration, controlled account provisioning, and tenant/location authorization.
2. **Queue board** — SF-2 with persisted ordered state.
3. **Core transitions** — SF-3, SF-4, and SF-5, each as a small transactional domain action and focused UI slice.
4. **Resolve the line** — SF-6 and SF-7, sharing terminal-state and audit behavior.
5. **Live synchronization** — SF-8, publishing committed changes and retaining refresh/reconnect recovery.
6. **Returning visitors** — SF-9, requeueing a no-show at the end of the line with a fresh queue sequence.

Keep each transition independently reviewable and tested. Avoid generic ticket status editing; implement one authorized command per transition.
