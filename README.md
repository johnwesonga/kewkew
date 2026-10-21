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

2. Start the server:

   ```sh
   mix phx.server
   ```

   Or start an interactive shell with the server:

   ```sh
   iex -S mix phx.server
   ```

3. Visit [http://localhost:4000](http://localhost:4000).

## Development

- Run the test suite with `mix test`.
- Run the project checks and formatter with `mix precommit` before committing changes.
- Store design documents in [`docs/`](docs/).
- Scope each feature as a user story with reviewable acceptance criteria, and keep changes small and testable.

## Repository

[github.com/johnwesonga/kewkew](https://github.com/johnwesonga/kewkew)
