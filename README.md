# Kewkew

Kewkew is a virtual queue management system for businesses. Visitors join a queue from their phones without installing an app, follow their position, and receive updates while staff manage the line. Estimated wait is planned as a nice-to-have for a later release.

Planned capabilities include service selection, staff routing, waiting-room displays, notifications, analytics, and support for multiple locations. Queue configuration will let businesses choose whether visitors join anonymously or provide identifying information such as first and last name.

Kewkew is being built with Phoenix, LiveView, Ash, and PostgreSQL as a modular web application. See the [high-level architecture](docs/architecture.md) for the proposed system boundaries and incremental delivery plan.

## Status

The repository currently contains the Phoenix/Ash application foundation. Product features are being scoped and delivered incrementally as user stories.

The initial implementation focus is the [visitor flow](docs/visitor-flow-user-stories.md), from opening a queue link through joining and tracking a ticket. Its proposed [data model](docs/visitor-flow-data-model.md) is documented alongside the stories.

## Getting started

Requirements: Elixir and Erlang/OTP compatible with the versions in `mix.exs`, PostgreSQL, and the asset tooling installed by the setup task.

1. Install dependencies and set up the database and assets:

   ```sh
   mix setup
   ```

2. The development seed creates a local administrator account. Sign in at `/sign-in` with:

   ```text
   Email:    admin@kewkew.local
   Password: kewkew-local-admin-password
   ```

   To choose different seed credentials, set `KEWKEW_DEV_STAFF_EMAIL` and `KEWKEW_DEV_STAFF_PASSWORD` before running `mix setup`. This account and password are for local development only. The staff landing page is at `/staff`.

3. Start the server:

   ```sh
   mix phx.server
   ```

   Or start an interactive shell with the server:

   ```sh
   iex -S mix phx.server
   ```

4. Visit [http://localhost:4000](http://localhost:4000).

## First organization setup

For a fresh non-development installation, apply database migrations, then run the trusted bootstrap task with these environment variables set:

```text
KEWKEW_ADMIN_EMAIL
KEWKEW_ADMIN_PASSWORD
KEWKEW_ORGANIZATION_NAME
KEWKEW_LOCATION_NAME
```

```sh
mix kewkew.bootstrap_admin
```

The task creates the organization, its first location, the administrator account, and the active admin membership together. It can only run before any organization or staff account exists; use the normal staff sign-in flow afterward. Keep the password in your deployment's secret or environment configuration. The development seed credentials above are only for local development and are separate from this bootstrap task.

The implementation and acceptance criteria are tracked in [OLA-1](docs/organization-location-admin-user-stories.md#ola-1-bootstrap-an-organization-and-its-first-administrator).

## Development

- Run the test suite with `mix test`.
- Run the project checks and formatter with `mix precommit` before committing changes.
- Store design documents in [`docs/`](docs/).
- Scope each feature as a user story with reviewable acceptance criteria, and keep changes small and testable.

## Repository

[github.com/johnwesonga/kewkew](https://github.com/johnwesonga/kewkew)
