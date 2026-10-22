defmodule KewkewWeb.Plugs.RequireStaffMembership do
  @moduledoc "Requires an authenticated user with at least one active staff membership."

  import Plug.Conn
  import Phoenix.Controller

  alias Kewkew.Accounts.User
  alias Kewkew.Business.StaffAccess

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{current_user: %User{id: user_id}}} = conn, _opts) do
    if StaffAccess.has_active_membership?(user_id) do
      conn
    else
      conn
      |> send_resp(:forbidden, "Staff access is not enabled for this account.")
      |> halt()
    end
  end

  def call(conn, _opts) do
    conn
    |> put_session(:return_to, current_path(conn))
    |> redirect(to: "/sign-in")
    |> halt()
  end
end
