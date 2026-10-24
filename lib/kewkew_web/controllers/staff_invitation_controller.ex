defmodule KewkewWeb.StaffInvitationController do
  use KewkewWeb, :controller

  alias Kewkew.Accounts.StaffInvitations

  def show(conn, %{"token" => token}) do
    case StaffInvitations.invitation(token) do
      {:ok, invitation} ->
        render_form(conn, invitation, %{"password" => "", "password_confirmation" => ""}, [])

      {:error, _} ->
        conn |> put_status(:gone) |> render(:invalid)
    end
  end

  def accept(conn, %{"token" => token, "invitation" => params}) do
    case StaffInvitations.accept(
           token,
           Map.get(params, "password"),
           Map.get(params, "password_confirmation")
         ) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Your invitation was accepted. Sign in to access your workspace.")
        |> redirect(to: ~p"/sign-in")

      {:error, :invalid_password} ->
        case StaffInvitations.invitation(token) do
          {:ok, invitation} ->
            render_form(conn, invitation, params, [
              "Use a password of at least 12 characters and confirm it."
            ])
            |> put_status(:unprocessable_entity)

          {:error, _} ->
            conn |> put_status(:gone) |> render(:invalid)
        end

      {:error, _} ->
        conn |> put_status(:gone) |> render(:invalid)
    end
  end

  def accept(conn, _params), do: conn |> put_status(:gone) |> render(:invalid)

  defp render_form(conn, invitation, params, errors) do
    render(conn, :accept,
      layout: {KewkewWeb.Layouts, :root},
      invitation: invitation,
      token: conn.path_params["token"],
      form: Phoenix.Component.to_form(params, as: :invitation),
      errors: errors
    )
  end
end
