defmodule KewkewWeb.StaffController do
  @moduledoc "Authenticated staff landing page."

  use KewkewWeb, :controller

  alias Kewkew.Business.StaffAccess
  alias Kewkew.Queues.StaffCreateQueue
  alias Kewkew.Queues.StaffUpdateQueue

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

  @doc "Shows an administrator the editable configuration for a queue."
  def edit(conn, %{"queue_id" => queue_id}) do
    case StaffUpdateQueue.fetch_queue(conn.assigns.current_user.id, queue_id) do
      {:ok, context} ->
        params = %{
          "name" => context.queue.name,
          "identity_policy" => Atom.to_string(context.queue.identity_policy),
          "max_active_tickets" => capacity_value(context.queue.max_active_tickets)
        }

        public_url = unverified_url(conn, "/q/#{context.queue.public_slug}")
        render_edit_form(conn, context, params, public_url, [])

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to edit that queue.")
        |> redirect(to: ~p"/staff")
    end
  end

  def edit(conn, _params) do
    conn
    |> put_flash(:error, "Choose a queue to edit.")
    |> redirect(to: ~p"/staff")
  end

  @doc "Updates the editable settings for an authorized administrator's queue."
  def update(conn, %{"queue_id" => queue_id, "queue" => params}) do
    case StaffUpdateQueue.update_queue(conn.assigns.current_user.id, queue_id, params) do
      {:ok, queue} ->
        conn
        |> put_flash(
          :info,
          "Settings for #{queue.name} were saved. Existing tickets are unchanged."
        )
        |> redirect(to: ~p"/staff")

      {:error, :invalid_params, errors} ->
        render_edit_error(conn, queue_id, params, errors)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to edit that queue.")
        |> redirect(to: ~p"/staff")

      {:error, _reason} ->
        render_edit_error(conn, queue_id, params, [
          {:queue, "The queue settings could not be saved. Check the details and try again."}
        ])
    end
  end

  def update(conn, _params) do
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

  defp render_edit_error(conn, queue_id, params, errors) do
    case StaffUpdateQueue.fetch_queue(conn.assigns.current_user.id, queue_id) do
      {:ok, context} ->
        public_url = unverified_url(conn, "/q/#{context.queue.public_slug}")

        render_edit_form(conn, context, params, public_url, errors, status: :unprocessable_entity)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to edit that queue.")
        |> redirect(to: ~p"/staff")
    end
  end

  defp render_edit_form(conn, context, params, public_url, errors, opts \\ []) do
    render(conn, :edit,
      page_title: "Edit queue",
      staff_email: to_string(conn.assigns.current_user.email),
      context: context,
      form: Phoenix.Component.to_form(params, as: :queue),
      public_url_form: Phoenix.Component.to_form(%{"url" => public_url}, as: :public),
      public_url: public_url,
      errors: errors,
      status: Keyword.get(opts, :status, :ok)
    )
  end

  defp capacity_value(nil), do: ""
  defp capacity_value(value), do: to_string(value)
end
