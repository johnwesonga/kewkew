defmodule KewkewWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use KewkewWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :staff?, :boolean, default: false, doc: "whether to render the staff workspace shell"
  attr :staff_email, :string, default: nil, doc: "the signed-in staff member's email"
  attr :location_name, :string, default: nil, doc: "the active location label"
  attr :active_nav, :atom, default: :queues, doc: "the active staff navigation item"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= if @staff? do %>
      <div class="staff-shell">
        <header class="staff-topbar">
          <a href={~p"/staff"} class="staff-brand" aria-label="Kewkew staff home">
            <span class="staff-brand-mark">k</span>
            <span>Kewkew<small>Queue, without the wait</small></span>
          </a>
          <div class="staff-top-actions">
            <.theme_toggle />
            <div :if={@location_name} class="staff-location">
              <.icon name="hero-map-pin" class="size-4" />
              <span>{@location_name}</span>
            </div>
            <span class="staff-avatar" title={@staff_email}>{staff_initials(@staff_email)}</span>
            <.link href="/sign-out" class="staff-sign-out">Sign out</.link>
          </div>
        </header>

        <div class="staff-workspace">
          <aside class="staff-sidebar">
            <p class="staff-side-label">Workspace</p>
            <nav class="staff-nav" aria-label="Staff workspace">
              <.link
                navigate={~p"/staff"}
                class={["staff-nav-link", @active_nav == :queues && "active"]}
              >
                <.icon name="hero-queue-list" class="size-4" /> Live queues
              </.link>
            </nav>
            <div class="staff-help-card">
              <strong>Welcome to Kewkew</strong>
              <p>Choose a queue to keep track of visitors and their place in line.</p>
            </div>
          </aside>

          <main class="staff-main">
            <div class="staff-content">
              {render_slot(@inner_block)}
            </div>
          </main>
        </div>
        <.flash_group flash={@flash} />
      </div>
    <% else %>
      <header class="navbar px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <a href="/" class="flex-1 flex w-fit items-center gap-2">
            <img src={~p"/images/logo.svg"} width="36" />
            <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
          </a>
        </div>
        <div class="flex-none">
          <ul class="flex flex-column px-1 space-x-4 items-center">
            <li>
              <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
            </li>
            <li>
              <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
            </li>
            <li>
              <.theme_toggle />
            </li>
            <li>
              <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
                Get Started <span aria-hidden="true">&rarr;</span>
              </a>
            </li>
          </ul>
        </div>
      </header>

      <main class="px-4 py-20 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-2xl space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
    <% end %>
    """
  end

  defp staff_initials(nil), do: "KW"

  defp staff_initials(email) do
    email
    |> String.split("@", parts: 2)
    |> hd()
    |> String.split(~r/[._-]+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides system, light, and dark theme controls based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div id="theme-toggle" class="theme-toggle" role="group" aria-label="Color theme">
      <div class="theme-toggle-indicator" aria-hidden="true" />

      <button
        id="theme-system"
        type="button"
        class="theme-toggle-button"
        aria-label="Use system theme"
        title="System"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        id="theme-light"
        type="button"
        class="theme-toggle-button"
        aria-label="Use light theme"
        title="Light"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        id="theme-dark"
        type="button"
        class="theme-toggle-button"
        aria-label="Use dark theme"
        title="Dark"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
