defmodule KewkewWeb.StaffController do
  @moduledoc "Authenticated staff landing page."

  use KewkewWeb, :controller

  alias Kewkew.Business.StaffAccess
  alias Kewkew.Queues.StaffCreateQueue

  @doc "Shows the locations and queues available to the authenticated staff member."
  def index(conn, _params) do
    user_id = conn.assigns.current_user.id
    locations = StaffAccess.locations_for_user(user_id)
    queues = StaffAccess.queues_for_user(user_id)

    queue_groups =
      Enum.map(locations, fn location ->
        location_queues = Enum.filter(queues, &(&1.location.id == location.id))

        %{
          location: location,
          queues: location_queues,
          can_manage?: StaffAccess.can_manage_organization?(user_id, location.organization_id)
        }
      end)

    render(conn, :index,
      page_title: "Staff queues",
      staff_email: to_string(conn.assigns.current_user.email),
      queue_groups: queue_groups,
      queue_count: length(queues)
    )
  end

  @doc "Shows the queue creation form for an administrator's location."
  def new(conn, %{"location_id" => location_id}) do
    user_id = conn.assigns.current_user.id

    case StaffCreateQueue.services_for_location(user_id, location_id) do
      {:ok, %{location: location, services: services}} ->
        render_create_form(conn, location, services, %{"identity_policy" => "anonymous"}, [])

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to create a queue at that location.")
        |> redirect(to: ~p"/staff")
    end
  end

  def new(conn, _params) do
    conn
    |> put_flash(:error, "Choose an organization location before creating a queue.")
    |> redirect(to: ~p"/staff")
  end

  @doc "Creates a queue after rechecking administrator access and submitted settings."
  def create(conn, %{"location_id" => location_id, "queue" => params}) do
    user_id = conn.assigns.current_user.id

    case StaffCreateQueue.create_queue(user_id, location_id, params) do
      {:ok, queue} ->
        conn
        |> put_flash(:info, "Queue #{queue.name} was created.")
        |> redirect(to: ~p"/staff")

      {:error, :invalid_params, errors} ->
        render_create_error(conn, user_id, location_id, params, errors)

      {:error, :invalid_service} ->
        render_create_error(conn, user_id, location_id, params, [
          {:service_id, "Choose an active service at this location."}
        ])

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to create a queue at that location.")
        |> redirect(to: ~p"/staff")

      {:error, _reason} ->
        render_create_error(conn, user_id, location_id, params, [
          {:queue, "The queue could not be created. Check the details and try again."}
        ])
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "The queue details were incomplete.")
    |> redirect(to: ~p"/staff")
  end

  defp render_create_error(conn, user_id, location_id, params, errors) do
    case StaffCreateQueue.services_for_location(user_id, location_id) do
      {:ok, %{location: location, services: services}} ->
        render_create_form(conn, location, services, params, errors,
          status: :unprocessable_entity
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to create a queue at that location.")
        |> redirect(to: ~p"/staff")
    end
  end

  defp render_create_form(conn, location, services, params, errors, opts \\ []) do
    render(conn, :new,
      page_title: "Create queue",
      staff_email: to_string(conn.assigns.current_user.email),
      location: location,
      services: services,
      form: Phoenix.Component.to_form(params, as: :queue),
      errors: errors,
      status: Keyword.get(opts, :status, :ok)
    )
  end
end
