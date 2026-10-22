defmodule KewkewWeb.StaffController do
  @moduledoc "Authenticated staff landing page."

  use KewkewWeb, :controller

  @doc "Shows the locations and queues available to the authenticated staff member."
  def index(conn, _params) do
    locations = Kewkew.Business.StaffAccess.locations_for_user(conn.assigns.current_user.id)
    queues = Kewkew.Business.StaffAccess.queues_for_user(conn.assigns.current_user.id)

    render(conn, :index,
      page_title: "Staff queues",
      staff_email: to_string(conn.assigns.current_user.email),
      locations: locations,
      queues: queues
    )
  end
end
