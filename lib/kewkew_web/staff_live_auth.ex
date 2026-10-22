defmodule KewkewWeb.StaffLiveAuth do
  @moduledoc "Requires an active staff membership for staff LiveViews."

  alias Kewkew.Business.StaffAccess

  def on_mount(:require_membership, _params, _session, socket) do
    case socket.assigns[:current_user] do
      %{id: user_id} when is_binary(user_id) ->
        if StaffAccess.has_active_membership?(user_id) do
          {:cont, socket}
        else
          {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
        end

      _ ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/sign-in")}
    end
  end
end
