defmodule KewkewWeb.StaffController do
  @moduledoc "Authenticated staff landing page."

  use KewkewWeb, :controller

  @doc "Shows the locations assigned to the authenticated staff member."
  def index(conn, _params) do
    locations = Kewkew.Business.StaffAccess.locations_for_user(conn.assigns.current_user.id)
    queues = Kewkew.Business.StaffAccess.queues_for_user(conn.assigns.current_user.id)

    location_list =
      Enum.map_join(locations, "", fn location ->
        name = Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(location.name))
        "<li>#{name}</li>"
      end)

    queue_list =
      Enum.map_join(queues, "", fn %{queue: queue, location: location} ->
        queue_name = Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(queue.name))
        location_name = Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(location.name))
        "<li>#{queue_name} <span>at #{location_name}</span></li>"
      end)

    email =
      conn.assigns.current_user.email
      |> to_string()
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    html(conn, """
    <main id="staff-home">
      <h1>Staff access</h1>
      <p>Signed in as #{email}</p>
      <h2>Assigned locations</h2>
      <ul>#{location_list}</ul>
      <h2>Queues you can access</h2>
      <ul id="staff-queues">#{queue_list}</ul>
    </main>
    """)
  end
end
