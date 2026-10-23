# Admin queue configuration and management user stories

## Goal

Let organization administrators configure reusable queues at their locations and let authorized staff control when a queue accepts visitors. Queue configuration persists across operating sessions; ticket numbers and line sequence restart for each new session.

These stories assume an organization, locations, services, staff memberships, and location assignments already exist. Their setup and administration are defined in [organization-location-admin-user-stories.md](organization-location-admin-user-stories.md). Staff authentication and queue authorization are defined in [staff-admin-flow-user-stories.md](staff-admin-flow-user-stories.md). Visitor-facing behavior is defined in [visitor-flow-user-stories.md](visitor-flow-user-stories.md).

## Shared rules

- A **queue** is reusable configuration tied to one location and one service. A **queue session** is one operating period for that queue. Closing a session and opening another starts ticket numbering and line sequence at 1; pausing and resuming the same session does not reset either.
- Only an organization administrator may create or change queue configuration. Queue operators may view and operate queues at assigned locations but may not change configuration unless granted the administrator role.
- All queue and session operations enforce organization and location access on the server. Hiding a control in the interface is not authorization.
- Configuration changes do not rewrite existing tickets. Capacity applies to active tickets (`waiting`, `called`, or `serving`) in the current session. A no-show does not occupy capacity; recalling one makes it active again.
- Queue settings and operating state are distinct. Deactivating a queue prevents new joins; pausing a session temporarily stops joins; closing a session ends that operating period.
- A queue's public link and QR code identify the reusable queue, not a specific session. The same link can be reused for future sessions.

## Stories

**Status tracking** — `Complete` means the story's acceptance criteria are implemented; `In progress` means some criteria remain; `Planned` means implementation has not started. Status tracks implementation in this repository, not production release.

### AQ-1: View queues for an organization

**Status** — Complete

**User story** — As an organization administrator, I want to see queues grouped by location and service so I can understand what is configured and manage the right queue.

**Acceptance criteria**

- The administrator sees queues only for their organization and can identify each queue's location, service, configuration status, and current session state.
- The list distinguishes a queue that is inactive, has no session, is open, paused, or closed.
- An operator sees only queues at locations they are assigned to and does not receive configuration controls.
- Empty locations provide a clear way for an administrator to create a queue.

**Dependencies** — SF-1; organization, location, service, and staff-access records.

### AQ-2: Create a queue

**Status** — Complete

**User story** — As an organization administrator, I want to create a queue for a service at a location so visitors can join that service's line.

**Acceptance criteria**

- The administrator provides a queue name, location, service, visitor identity policy, and optional maximum active capacity.
- The available service choices belong to the selected location. The server rejects a mismatched or inaccessible location/service pair.
- Identity policy is either anonymous or requires both first and last name; the visitor form follows that policy (VF-4 and VF-5).
- Capacity is either unlimited or a positive whole number. When set, it limits active tickets in the current session; completed, cancelled, and no-show tickets do not consume a place.
- Creating a queue does not implicitly open a queue session. The administrator or authorized operator explicitly opens one when ready to accept visitors.
- Only administrators can create queues; unauthorized or invalid submissions create no queue.

**Dependencies** — AQ-1; staff roles; location/service records; VF-4 and VF-5.

### AQ-3: Edit queue configuration

**Status** — Complete

**User story** — As an organization administrator, I want to update a queue's name, identity policy, service details, or capacity so the visitor flow reflects current business needs.

**Acceptance criteria**

- An administrator can edit the queue name, identity policy, and maximum active capacity. A queue's location and service are fixed at creation; a different service gets its own queue.
- Changes apply to future joins and capacity checks after save; existing tickets keep their ticket number, status, sequence, and collected name.
- Reducing capacity below the current active-ticket count is allowed but does not cancel tickets or prevent staff from serving them; new joins remain blocked until active count falls below the limit.
- Removing the capacity limit permits joins subject to session availability.
- A configuration change does not reset ticket numbering or alter the current session.
- Operators cannot make these changes unless they also have administrator privileges.

**Dependencies** — AQ-2; active-ticket counting and visitor join validation.

### AQ-4: Share a queue link and QR code

**Status** — Complete

**User story** — As an organization administrator, I want a reusable visitor link and QR code for each queue so people can reach the correct join page in person or remotely.

**Acceptance criteria**

- The queue management page provides a copyable public URL and a QR code that resolves to that same URL.
- The URL and QR code remain valid across queue sessions and identify only the queue; they do not grant access to staff screens or visitor ticket tracking pages.
- An administrator can print or download the QR code in a usable form.
- If public access to a queue is disabled, its link shows an unavailable page and cannot create tickets.

**Dependencies** — AQ-2; VF-1; public queue URL and QR rendering.

### AQ-5: Deactivate or reactivate a queue

**Status** — Complete

**User story** — As an organization administrator, I want to temporarily disable a queue without deleting its history so visitors cannot join a service that is unavailable.

**Acceptance criteria**

- Deactivating a queue prevents new visitors from joining through its public link and location service listing.
- Deactivation preserves the queue, session, tickets, and history. It does not silently cancel active tickets.
- Staff can still view and work existing tickets at an authorized location while the queue is inactive.
- Reactivating restores public access if the location, service, and session also permit joining.
- Only an administrator can change this setting; a stale or unauthorized request cannot change it.

**Dependencies** — AQ-1 and AQ-2; VF-2; queue availability checks.

### AQ-6: Open a queue session

**Status** — Complete

**User story** — As an administrator or authorized queue operator, I want to open a session when a queue is ready so visitors can join and receive tickets.

**Acceptance criteria**

- An authorized staff member can open a session only when the queue, location, and service are active and the queue has no open or paused session.
- A new session starts with ticket number 1 and queue sequence 1.
- Opening a session on an inactive queue is rejected with a clear explanation.
- Concurrent attempts cannot create multiple open sessions for one queue.
- The staff board and public page show that the queue is open after the operation commits.

**Dependencies** — AQ-1, AQ-2, AQ-5; queue-session persistence and VF-2.

### AQ-7: Pause and resume a queue session

**Status** — Complete

**User story** — As an authorized queue operator, I want to pause and resume the current session so staff can temporarily stop arrivals while keeping the line intact.

**Acceptance criteria**

- An open session can be paused; a paused session can be resumed. Invalid or repeated transitions are rejected safely.
- While paused, visitors cannot join, but staff can continue to call and serve tickets already in the session.
- Resuming restores visitor joins without changing existing ticket numbers, queue sequence, or ticket statuses.
- Public and staff views show the committed paused or open state promptly.
- Only administrators and operators assigned to the queue's location can change session state.

**Dependencies** — AQ-6; SF-1, SF-2, and SF-8; VF-2.

### AQ-8: Close a queue session and start the next one

**Status** — Complete

**User story** — As an authorized queue operator, I want to close a session when service ends so the next operating period starts with fresh ticket numbers and a clean line.

**Acceptance criteria**

- Only an open or paused session can be closed; a closed session cannot be reopened.
- Closing ends visitor joins for that session and preserves its tickets and event history.
- A session cannot be closed while tickets remain in `waiting`, `called`, or `serving` state. Staff must complete or cancel eligible tickets first; no-show tickets may remain in the preserved history.
- Opening the next session creates a new session with ticket number and queue sequence reset to 1; old visitor tracking pages continue to show their original session's final ticket state.
- Only administrators and operators assigned to the queue's location can close or open sessions.

**Dependencies** — AQ-6 and AQ-7; ticket history and staff transitions SF-3 through SF-9.

## Suggested implementation order

1. **Queue discovery and configuration** — AQ-1 through AQ-3, including authorization and validation.
2. **Public access and availability** — AQ-4 and AQ-5 with visitor-side unavailable states.
3. **Session lifecycle** — AQ-6 through AQ-8, with explicit state transitions and ticket-number reset at new sessions.

Keep each story independently reviewable. Queue configuration edits, queue activation, and session lifecycle changes should be separate actions so an administrator can change future behavior without unintentionally modifying tickets already in progress.

## Decisions to settle before implementation

- Whether queue configuration changes need an immutable audit log with before/after values and the administrator actor.
- Whether a new session opens automatically after closing or always requires an explicit staff action.
