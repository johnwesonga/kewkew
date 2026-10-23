# Organization and location administration user stories

## Goal

Let organization administrators manage their business profile, operating locations, services, and staff access while keeping every record within the correct organization. A location or service can be made unavailable without deleting queue or visitor history.

These stories cover the business setup and administration foundation. Queue configuration and operating sessions are in [admin-queue-configuration-user-stories.md](admin-queue-configuration-user-stories.md). Day-to-day queue operations are in [staff-admin-flow-user-stories.md](staff-admin-flow-user-stories.md).

## Actors and shared rules

- **Organization administrator**: manages the organization, its locations and services, and staff memberships. An administrator has organization-wide access.
- **Queue operator**: can operate queues only at locations assigned to their active membership. Operators cannot manage organization setup or staff access.
- **Kewkew platform operator**: performs the initial trusted organization bootstrap. This is not a public self-signup flow.
- A user's authenticated identity is separate from their membership in an organization. One user may have memberships in more than one organization.
- Every read and write is authorized on the server and scoped to the current organization. Hiding a control in the UI does not enforce access.
- Locations and services that have queues or operational history are deactivated rather than physically deleted. Deactivation preserves their queues, sessions, tickets, and events.
- Deactivating a location or service blocks new public joins and opening new sessions that depend on it. Authorized staff may continue to resolve tickets in an already-open session.
- There are two initial staff roles: `admin` and `operator`. Operators must have one or more location assignments. Administrators have access to all locations in their organization.

## Stories

**Status tracking** — `Complete` means the story's acceptance criteria are implemented; `In progress` means some criteria remain; `Planned` means implementation has not started. Status tracks implementation in this repository, not production release.

### OLA-1: Bootstrap an organization and its first administrator

**Status** — Complete

**User story** — As a Kewkew platform operator, I want to initialize an organization, its first location, and its first administrator so the business can securely begin setup.

**Acceptance criteria**

- The trusted bootstrap creates the organization, initial location, administrator identity, and active admin membership as one operation.
- Bootstrap is only available while the installation has not yet been initialized; repeated or concurrent attempts cannot create another initial organization.
- The initial administrator signs in through the normal staff authentication flow after bootstrap.
- Bootstrap credentials are supplied through a trusted setup process and are not exposed in a public registration form or committed source code.
- A failed bootstrap leaves no partial organization, location, user, or membership behind.

**Dependencies** — SF-1; AshAuthentication and trusted account provisioning.

### OLA-2: View the organization and its locations

**Status** — Complete

**User story** — As an organization administrator, I want to see my organization's profile and locations so I can manage the correct business and understand which sites are operating.

**Acceptance criteria**

- The administrator sees only organizations where they have an active admin membership.
- The organization view lists each location, its active or inactive state, its timezone, and its configured services and queues.
- Operators see only the locations assigned to them and do not receive organization-management controls.
- An organization with no locations or services has a clear next step to create them.
- Requests for an organization outside the signed-in user's memberships reveal no data.

**Dependencies** — OLA-1; SF-1; organization, location, service, and staff membership records.

### OLA-3: Update organization details

**Status** — Complete

**User story** — As an organization administrator, I want to update my organization's name so that staff and operational pages use the current business name.

**Acceptance criteria**

- An administrator can update the organization name with server-side validation.
- The saved name appears in organization and staff-facing pages that identify the business.
- An update does not alter location, service, queue, session, ticket, or membership records.
- Operators and users outside the organization cannot update its details.

**Dependencies** — OLA-2; organization-scoped authorization.

### OLA-4: Create and update a location

**Status** — In progress

**Status note** — Administrator-only location creation and editing are implemented. Timezone values are validated and stored, but no location-specific event times are displayed yet, so timezone-aware presentation remains for the first relevant time display.

**User story** — As an organization administrator, I want to add a location and maintain its name and timezone so queues can be organized around where service is provided.

**Acceptance criteria**

- An administrator can create a location with a required name and a valid timezone; the location belongs to the administrator's organization.
- The administrator can update a location's name and timezone.
- A location cannot be moved between organizations through an edit action.
- Changing a timezone affects how future location-specific times are displayed; stored event timestamps remain UTC and are not rewritten.
- Operators cannot create or update locations.

**Dependencies** — OLA-1 and OLA-2; organization-scoped authorization.

### OLA-5: Deactivate or reactivate a location

**Status** — Complete

**Status note** — Organization admins can deactivate or reactivate a location. Public discovery and visitor joins already reject inactive locations, and opening a new session checks location availability. Existing session actions remain authorized; toggling availability broadcasts queue updates without closing sessions or changing tickets.

**User story** — As an organization administrator, I want to temporarily deactivate a location so visitors cannot join services at a site that is not operating.

**Acceptance criteria**

- Deactivating a location removes its queues from public service discovery and prevents new visitors from joining any queue at that location.
- An inactive location cannot open new queue sessions.
- Deactivation preserves services, queues, sessions, tickets, and event history. It does not silently close a session or cancel tickets.
- Authorized staff can continue to call, serve, complete, or otherwise resolve tickets in an existing session.
- Reactivating the location restores public access only when the service, queue, and queue session also permit joining.
- Only an organization administrator can change location availability.

**Dependencies** — OLA-2 and OLA-4; AQ-5 through AQ-8; visitor availability checks.

### OLA-6: Manage services at a location

**Status** — Complete

**Status note** — Organization admins can create services at an authorized location and edit a service's name and optional description. Service edits cannot change its location; operator access is rejected by the server-side administration service.

**User story** — As an organization administrator, I want to create and update services at a location so visitors can choose the kind of help they need.

**Acceptance criteria**

- An administrator can create a service with a required name and optional description at a location in their organization.
- An administrator can update a service's name and description; the service remains attached to its location.
- A service cannot be moved to another location once it has queues or operational history. A different location can have its own service definition.
- Operators cannot create or edit services unless they also have an administrator membership.
- Service lists and queue setup show only services at locations the administrator can manage.

**Dependencies** — OLA-2 and OLA-4; AQ-1 and AQ-2.

### OLA-7: Deactivate or reactivate a service

**Status** — Planned

**User story** — As an organization administrator, I want to deactivate a service temporarily so visitors cannot join queues for a service that is unavailable.

**Acceptance criteria**

- Deactivating a service prevents new joins and prevents opening new sessions for queues attached to it.
- Deactivation preserves the service, its queues, sessions, tickets, and event history.
- Authorized staff can continue working tickets in an existing session for that service.
- Reactivating the service restores public availability only when its location, queue, and session are also available.
- Only an organization administrator can change service availability.

**Dependencies** — OLA-6; AQ-5 through AQ-8; visitor availability checks.

### OLA-8: Invite a staff member and grant initial access

**Status** — Planned

**User story** — As an organization administrator, I want to invite a staff member with an initial role and location access so they can securely use Kewkew for their assigned work.

**Acceptance criteria**

- An administrator can invite a staff member by email and choose `admin` or `operator`.
- An operator invitation must include at least one location in the administrator's organization; an administrator receives organization-wide access.
- The invitation is bound to the intended email and organization, expires, and can be accepted only once. Raw invitation secrets are not stored.
- An invited person establishes their own credentials through the invitation flow; public self-registration remains disabled.
- An existing Kewkew identity can accept organization access without creating a duplicate identity.
- Invitation acceptance creates or activates one membership and its location assignments atomically. Failed or expired invitations grant no access.
- The inviter and invitee receive clear confirmation of the invitation state; sensitive credentials are not sent in plaintext.

**Dependencies** — SF-1; AshAuthentication; secure invitation token and email delivery; OLA-2, OLA-4, and OLA-6.

### OLA-9: Change staff roles and location assignments

**Status** — In progress

**User story** — As an organization administrator, I want to update a staff member's role and location assignments so their access follows their responsibilities.

**Acceptance criteria**

- An administrator can change an active member between `admin` and `operator` and can replace an operator's location assignments.
- Every operator assignment refers to a location in the same organization as the membership; an operator must retain at least one location assignment.
- An administrator's access is organization-wide; stale operator assignments do not grant access outside the role's rules.
- Changes take effect on the next request or LiveView authorization check. A removed assignment prevents further access to that location's queues.
- Operators cannot change their own or another member's role or assignments.
- A role or assignment update does not alter queue sessions or ticket state.

**Dependencies** — OLA-8; SF-1; organization and location authorization.

### OLA-10: Suspend or remove staff access

**Status** — In progress

**User story** — As an organization administrator, I want to suspend a staff member's organization membership so they immediately lose access when they leave or change roles.

**Acceptance criteria**

- An administrator can deactivate a membership without deleting the user's authentication identity or historical queue events.
- A deactivated member cannot access that organization's staff pages, queues, or actions. Memberships in other organizations remain unaffected.
- Reactivating a membership restores access according to its current role and location assignments.
- The last active administrator for an organization cannot be deactivated or demoted until another active administrator exists.
- A membership audit record captures the actor, member, organization, change, and time.
- Operators cannot suspend or restore staff memberships.

**Dependencies** — OLA-8 and OLA-9; SF-1; membership audit records.

## Suggested implementation order

1. OLA-1 and OLA-2: organization bootstrap, scoped reads, and administrator overview.
2. OLA-3: organization profile editing.
3. OLA-4 and OLA-5: location creation, editing, and availability.
4. OLA-6 and OLA-7: service management and availability.
5. OLA-8 through OLA-10: staff invitations, access changes, and membership lifecycle.

Keep each story independently reviewable. Do not bundle location or service management with queue configuration, and do not make deactivation cascade into ticket or session deletion.

## Out of scope for this initial administration flow

- Public self-service business registration or paid plan selection.
- Physical deletion of locations, services, memberships, queues, or ticket history.
- Opening hours, holidays, addresses, maps, geofencing, and per-location branding.
- Fine-grained permissions beyond administrator and location-assigned operator.
- Bulk imports, organization mergers, or transferring locations between organizations.
- Billing, plan limits, and organization-level analytics.

## Decisions to settle before implementation

- Invitation expiry duration, resend/revocation behavior, and whether email must be verified before accepting.
- How to handle an invitation when the email already belongs to an identity with a different email-verification state.
- Whether location names must be unique within an organization and service names unique within a location.
- Which fields beyond name and timezone should be collected for a location or organization.
- Whether membership changes need a dedicated append-only audit resource or can initially use structured application audit events.
