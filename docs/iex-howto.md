# IEx how-to

Use IEx to inspect the local development database and call Kewkew's Ash actions while the
application is running.

## Start an interactive server

From the project root, run:

```sh
iex -S mix phx.server
```

The development server uses the database configured in `config/dev.exs` and is available at
`http://localhost:4000` unless you changed its port. If you only need a shell, without starting
Phoenix, run `iex -S mix`.

Load common aliases in IEx:

```elixir
alias Kewkew.Repo
alias Kewkew.Queues.{Queue, QueueSession, Ticket, BrowserTicketClaim}
alias Kewkew.Business.{Location, Service, StaffMembership, StaffLocationAccess}
import Ecto.Query
require Ash.Query
```

## Find a queue and its session

List queues with their public slug, which is the final part of `/q/:slug`:

```elixir
queues = Ash.read!(Queue, domain: Kewkew.Queues)
Enum.map(queues, &{&1.name, &1.public_slug, &1.id})
```

Look up one queue and its latest session:

```elixir
slug = "replace-with-public-slug"
queue = Ash.read_one!(Ash.Query.for_read(Queue, :by_public_slug, %{slug: slug}), domain: Kewkew.Queues)
session = Ash.read_one!(Ash.Query.for_read(QueueSession, :latest_for_queue, %{queue_id: queue.id}), domain: Kewkew.Queues)
```

Inspect tickets in that session. This output leaves visitor names out:

```elixir
Repo.all(
  from ticket in Ticket,
    where: ticket.queue_session_id == ^session.id,
    order_by: ticket.ticket_number,
    select: %{number: ticket.ticket_number, status: ticket.status, joined_at: ticket.joined_at}
)
```

## Check locations, services, and staff access

List locations and services:

```elixir
locations = Ash.read!(Location, domain: Kewkew.Business)
Enum.map(locations, &{&1.name, &1.active?, &1.id})

location_id = "replace-with-location-uuid"
Ash.read!(Service, domain: Kewkew.Business)
|> Enum.filter(&(&1.location_id == location_id))
|> Enum.map(&{&1.name, &1.active?, &1.id})
```

Inspect a staff member's organization membership and assigned locations by user ID:

```elixir
user_id = "replace-with-user-uuid"
memberships =
  Repo.all(
    from membership in StaffMembership,
      where: membership.user_id == ^user_id,
      select: %{id: membership.id, organization_id: membership.organization_id, role: membership.role, active?: membership.active?}
  )

membership_ids = Enum.map(memberships, & &1.id)

location_accesses =
  Repo.all(
    from access in StaffLocationAccess,
      where: access.staff_membership_id in ^membership_ids,
      select: %{membership_id: access.staff_membership_id, location_id: access.location_id}
  )
```

`StaffMembership` represents organization role and active status. `StaffLocationAccess` represents
the locations assigned to each membership.

## Inspect same-browser signup claims

Browser claims store only a SHA-256 digest, not the browser credential itself. Query claim metadata
without selecting the digest:

```elixir
Repo.all(
  from claim in BrowserTicketClaim,
    where: claim.queue_session_id == ^session.id,
    select: %{ticket_id: claim.ticket_id, inserted_at: claim.inserted_at}
)
```

Duplicate signup prevention is disabled in development in `config/dev.exs`, so the same browser can
join a queue repeatedly while retesting. Test and production environments enable it by default.

## Useful commands

- Apply pending local database migrations: `mix ecto.migrate`
- Recompile after changing Elixir code: `recompile()`
- Exit IEx: `Ctrl+C` twice or `System.halt()`

Treat direct database updates and deletes as destructive: they bypass the application's validations,
authorization checks, and transition history. Prefer calling the corresponding `Kewkew` action from
IEx when changing application data.
