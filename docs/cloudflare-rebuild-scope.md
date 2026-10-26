# Kewkew Cloudflare rebuild: high-level scope

## Purpose

Build a new Kewkew application as a separate project using TypeScript, SvelteKit, Cloudflare
Workers, and D1 (SQLite). This is a product rebuild, not a line-by-line port of the Phoenix/Ash
implementation. Existing user stories and operating rules are the product baseline; the new
application should preserve their behavior while using platform-appropriate persistence,
authorization, and request handling.

**New project repository** — [`johnwesonga/kewkew-cf`](https://github.com/johnwesonga/kewkew-cf).
Create and maintain the Cloudflare implementation in that repository. This repository remains the
Phoenix reference implementation and product-story source during the rebuild.

The first deliverable is a usable, secure queue workflow for one organization. The current Phoenix
application remains the reference implementation while the new project is developed. Do not switch
the public application or migrate live data until feature parity, operational readiness, and a
cutover plan are separately approved.

## Proposed system shape

- **SvelteKit + TypeScript** serves visitor pages, staff pages, and server-side form actions/API
  routes. Deploy through SvelteKit's Cloudflare adapter as a Worker.
- **D1** is the persistent source of truth for organizations, locations, services, queues, sessions,
  memberships, tickets, ticket history, visitor credentials, and later notification intents.
- **Workers bindings** provide D1 and any optional Cloudflare Queues or Durable Object namespaces.
  Keep provider APIs and platform bindings behind small modules so domain rules do not depend on
  global runtime state.
- **D1 migrations** are reviewed SQL files committed with the application. Use foreign keys,
  unique constraints, check constraints, and indexes to enforce invariants in SQLite as well as in
  TypeScript. D1 supports ordered SQL migrations and atomic sequential batches; queue mutations
  should use conditional writes and transactions instead of relying on PostgreSQL row locks.
- **Durable Objects** are a later real-time coordination option for staff boards and connected
  visitor pages. D1 remains authoritative. A Durable Object may publish committed changes, but it
  must not be the only place ticket state is stored.
- **Cloudflare Queues** are a later delivery mechanism for notifications or other slow external
  work. Persist a notification outbox intent in D1 with the queue transition, then dispatch it
  asynchronously. Consumers must tolerate at-least-once delivery and use idempotency keys.

Cloudflare's current SvelteKit guide uses `create-cloudflare` and the Cloudflare adapter. D1 batches
execute statements sequentially as one transaction, while each D1 database is single-threaded and
has a finite per-database size and throughput. The first build should therefore minimize round trips,
index hot queries, and validate queue-write throughput before considering any sharding strategy.
These are design constraints to account for, not reasons to introduce a distributed architecture
up front. See the [SvelteKit Workers guide](https://developers.cloudflare.com/workers/framework-guides/web-apps/sveltekit/),
[D1 migrations](https://developers.cloudflare.com/d1/reference/migrations/),
[D1 batch API](https://developers.cloudflare.com/d1/worker-api/d1-database/),
[D1 limits](https://developers.cloudflare.com/d1/platform/limits/), and
[Cloudflare Queues delivery guarantees](https://developers.cloudflare.com/queues/reference/delivery-guarantees/).

## Product baseline to preserve

The existing stories remain authoritative for detailed behavior:

- [Visitor flow](visitor-flow-user-stories.md): public queue links, availability, service choice,
  anonymous or name-required joins, private ticket tracking, called/completed states, and visitor
  cancellation.
- [Organization and location administration](organization-location-admin-user-stories.md):
  organization boundaries, locations, services, staff invitations, roles, location assignments,
  suspension, and audit history.
- [Queue configuration](admin-queue-configuration-user-stories.md): queue setup, public QR/link,
  activation, sessions, capacity, and deletion limits.
- [Staff operations](staff-admin-flow-user-stories.md): assigned queue access, board operations,
  ticket transitions, requeue, and updates across connected screens.
- [Queue scheduling](queue-scheduling-user-stories.md): recurring signup windows, capacity, and
  service start times.

Avoid copying Ash-specific module boundaries as a requirement. Port the domain invariants and
acceptance criteria, then choose TypeScript modules and SQL boundaries that fit the new app.

## Delivery slices

### CF-0: Establish the independent project foundation

**User story** — As a developer, I want a separate SvelteKit Workers project with a local D1
workflow so I can build and validate the replacement without disturbing the running Phoenix app.

**Acceptance criteria**

- The app is created in `johnwesonga/kewkew-cf` with TypeScript, SvelteKit, the Cloudflare adapter,
  and Wrangler configuration.
- The application source, deployment configuration, and D1 migrations live in the
  `johnwesonga/kewkew-cf` repository, independently of the Phoenix repository.
- `wrangler dev` runs the app locally against a local D1 database; preview and production use
  separately named D1 databases and bindings.
- The project has committed migration scripts, generated Worker binding types, and documented
  local setup, migration, test, and deploy-preview commands.
- A minimal health page can read from D1 in local development and in a preview deployment.
- No production domain or existing Phoenix data is changed by the initial setup.

### CF-1: Model organization data and enforce tenant access

**User story** — As an organization administrator, I want to manage my business and its staff in an
isolated organization so only authorized people can see or change its information.

**Acceptance criteria**

- D1 schema supports organizations, users, memberships, locations, services, and location access.
- Server-side actions authorize organization and location reads and writes; UI hiding alone is not
  authorization.
- The first administrator can be bootstrapped through a trusted setup flow; public business
  self-registration is not added by default.
- Staff invitation, acceptance, role updates, location assignment, suspension, and audit history
  preserve the current OLA acceptance criteria.
- Database constraints prevent invalid role values, duplicate membership, and cross-organization
  location assignments where representable in SQL; server validation covers relational checks that
  SQLite constraints cannot express directly.

### CF-2: Configure queues and operating sessions

**User story** — As an organization administrator, I want to configure a queue for a service and
control when visitors can join so the queue matches the service's operating rules.

**Acceptance criteria**

- Staff can create, edit, activate, and deactivate queues; queues belong to a location and service.
- Queue identity policy supports anonymous tickets and required first/last name.
- Capacity, manual sessions, and recurring signup/service schedules preserve AQ and queue-scheduling
  story behavior.
- Public links and QR targets resolve to a queue without exposing internal identifiers.
- Pausing/resuming preserves session ticket numbering; closing and reopening starts a new session
  with a new sequence.

### CF-3: Complete public join and private tracking

**User story** — As a visitor, I want to join an available queue from my phone and keep a private
link to my ticket so I can wait without creating an account or installing an app.

**Acceptance criteria**

- A visitor can open a queue link and see the organization/location, service, and current
  availability before entering details.
- The server enforces queue identity policy, availability, capacity, and ticket-number allocation.
- Each successful join and its event history are persisted atomically; retries and simultaneous
  submissions do not allocate duplicate tickets for one join attempt.
- The visitor gets an opaque, revocable private tracking credential stored as a digest, separate
  from ticket number and database IDs.
- Tracking shows persisted status and position, updates after staff transitions, supports
  cancellation under the established policy, and does not reveal another visitor's data.
- Same-browser repeat-join prevention is implemented with a separate opaque browser credential,
  scoped to one queue session, with the development bypass retained.

### CF-4: Operate queues from the staff workspace

**User story** — As a queue operator, I want to monitor my assigned queues and advance visitors
through valid states so service stays orderly.

**Acceptance criteria**

- Staff can only access queues allowed by active organization membership and location assignment.
- Staff can call next, start serving, complete, cancel, skip, and requeue according to the current
  transition rules.
- Every transition is conditional on current persisted state and records actor, time, and history.
- Competing operations cannot call or advance the same ticket twice or corrupt queue order.
- Staff pages remain usable on mobile as well as desktop.

### CF-5: Synchronize connected views

**User story** — As staff or a waiting visitor, I want connected pages to reflect committed queue
changes promptly so displayed status does not become stale.

**Acceptance criteria**

- Staff boards and affected visitor pages receive only the minimum event needed to refresh.
- Sensitive names, contact details, tracking credentials, and other visitors' private records are
  not broadcast to public clients.
- D1 remains the authority; reconnecting or refreshing reconstructs the current view from D1.
- If a Durable Object and WebSockets are used, messages are emitted only after the D1 transition
  commits, and missed messages are recovered by reading D1.

### CF-6: Add optional visitor notifications

**User story** — As a visitor, I want to opt into a message when staff call my ticket so I can step
away from the page while waiting.

**Acceptance criteria**

- Channel, consent language, opt-out, retention, and provider are selected in a separate story
  before collecting phone numbers or email addresses.
- Joining anonymously remains possible without providing contact details.
- A durable D1 outbox intent is committed with the triggering transition; provider delivery runs
  asynchronously and cannot delay or undo the queue action.
- Retries are bounded and idempotent; permanent failures are observable to authorized staff or
  operators without exposing message content unnecessarily.

## Initial MVP boundary

The first usable milestone is **CF-0 through CF-4**, with visitor polling or explicit refresh as the
initial synchronization method. This gets organization setup, queue configuration, public joining,
private tracking, and staff operations working end to end. CF-5 and CF-6 follow as separately
reviewable increments; notifications are not a prerequisite for queue correctness.

## Data and cutover approach

- Treat the new D1 schema as a clean, purpose-designed model. Map the current PostgreSQL resources
  to SQLite tables through reviewed migrations rather than attempting to translate Ash snapshots.
- Preserve stable identifiers and historical records only if a real data migration is required.
  The default scope assumes the new project starts with fresh data; importing current organizations,
  staff, or tickets needs its own inventory, mapping, validation, and rollback plan.
- Keep the Phoenix application available as the behavioral reference during development. Use the
  current user stories and important existing test scenarios to define parity checks.
- Do not change DNS, move the production domain, or deactivate the Phoenix app as part of the
  feature implementation slices. A separate cutover plan must define a freeze window, final export,
  import verification, rollback path, and ownership of any tickets created during transition.

## Decisions before implementation

- Whether the first release starts with clean data or imports existing organizations and staff.
- Authentication and invitation delivery strategy for staff on Workers.
- Whether D1 remains one shared database initially or a measured tenant-sharding plan is needed
  later. Begin shared; revisit only with production workload evidence.
- Whether staff/visitor real-time updates are needed in the first rollout or polling is sufficient
  while validating the product.
- First notification channel, consent and opt-out policy, provider, and delivery cost model.
- Data retention rules for names, ticket history, tracking credentials, and notification records.

## Explicitly out of scope for this first scope

- Porting existing Elixir/Ash code or preserving Phoenix module structure.
- Running Phoenix and SvelteKit as a single hybrid application.
- Automatic import of production data, production DNS cutover, or customer migration.
- Billing, plan management, analytics dashboards, advanced routing, multi-region tenant sharding,
  and guaranteed message delivery across providers.

