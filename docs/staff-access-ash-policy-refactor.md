# Staff access updates through Ash policies

## Goal

Refactor the OLA-9 role and location-assignment update flow so Ash enforces who may change staff access. Keep the current administrator and operator behavior, organization boundaries, and transactional guarantees.

## User story

As an organization administrator, I want staff role and location changes to be authorized by the business resources so access rules are enforced consistently wherever those actions are called.

## Current behavior

- `StaffMembership` and `StaffLocationAccess` use `Ash.Policy.Authorizer`, but their policies currently forbid all actions.
- `StaffAccess.update_membership_access/5` manually checks administrator access, changes the membership with `authorize?: false`, deletes assignment rows through `Repo.delete_all/2`, and creates assignments with `authorize?: false`.
- The flow already validates organization-local locations, requires an operator to have a location, clears location assignments for administrators, and prevents demoting the last active administrator while holding database locks.

## Scope

- Add action-level Ash authorization for changing a membership role and assigning or removing a member's location access.
- Pass the authenticated user as the Ash actor and run the relevant actions with authorization enabled.
- Keep the membership update and assignment replacement inside one database transaction. A failed action must roll back all changes.
- Preserve the existing validation and invariants:
  - Only an active administrator of the membership's organization can make the change.
  - Every operator location belongs to that same organization.
  - An operator retains at least one location assignment.
  - An administrator receives organization-wide access and has no individual location assignments.
  - The last active administrator cannot be demoted.
  - A suspended membership stays suspended when its role or assignments are edited.
- Return authorization failures without disclosing memberships or locations outside the administrator's organization.

## Out of scope

- Changing the OLA-9 staff access form or its successful behavior.
- Refactoring invitation acceptance, membership suspension/restoration, bootstrap provisioning, queue authorization, or all `authorize?: false` calls in the application.
- Adding new roles, audit requirements, or staff-access features.
- Moving aggregate invariants such as “last active administrator” into a policy if doing so weakens the existing transaction lock and concurrency protection.

## Acceptance criteria

- An organization administrator can change a member between administrator and operator and replace operator location assignments with the same results as today.
- An operator or non-member cannot perform these actions, including by calling the Ash actions directly.
- An assignment to a location in another organization is rejected; submitting no locations for an operator is rejected.
- Changing a member to administrator removes individual location assignments, and changing an administrator to operator grants only the submitted locations.
- A role or assignment action failure leaves both the membership and all location assignments unchanged.
- A suspended membership remains suspended after its role or assignments are edited.
- Concurrent role changes cannot leave an organization without an active administrator.
- The web form continues to show clear errors for invalid assignments and a success message after a committed update.

## Implementation outline

1. Define the authorization checks for active administrator membership and organization-scoped location assignment on the relevant Ash actions. Keep policy checks close to the resources/actions they protect; avoid calling mutation workflows from a policy check.
2. Add an explicit Ash action for removing a location assignment if needed, then replace direct assignment deletion with authorized Ash actions.
3. Update `StaffAccess.update_membership_access/5` to pass an actor and call Ash with authorization enabled while retaining its transaction and lock ordering.
4. Exercise both the controller workflow and direct Ash actions in focused tests, including cross-organization access, operator restrictions, assignment replacement, rollback, and concurrent last-admin changes.
5. Remove only the `authorize?: false` bypasses made unnecessary in this OLA-9 path. Leave unrelated provisioning and invitation flows for separate work.

## Design constraints and open implementation choice

Ash policy checks need the acting user and the organization associated with the target membership or assignment. The implementation should use an actor-aware custom check or an equivalent Ash-supported policy expression. Confirm the exact Ash APIs against the versions pinned in `mix.lock` before coding; do not broaden access by weakening the current deny-by-default policies globally.
