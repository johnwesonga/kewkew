defmodule KewkewWeb.StaffController do
  @moduledoc "Authenticated staff landing page."

  use KewkewWeb, :controller

  alias Kewkew.Business.StaffUpdateOrganization
  alias Kewkew.Business.StaffLocationAdministration
  alias Kewkew.Business.StaffSetLocationAvailability
  alias Kewkew.Business.StaffAccess
  alias Kewkew.Queues.StaffCreateQueue
  alias Kewkew.Queues.StaffSetQueueAvailability
  alias Kewkew.Queues.StaffUpdateQueue

  @doc "Shows organizations, permitted locations, services, and queues for authenticated staff."
  def index(conn, _params) do
    user_id = conn.assigns.current_user.id
    organizations = StaffAccess.organizations_for_user(user_id)
    locations = StaffAccess.locations_for_user(user_id)
    services = StaffAccess.services_for_locations(Enum.map(locations, & &1.id))
    queues = StaffAccess.queues_for_user(user_id)

    organization_groups =
      Enum.map(organizations, fn %{organization: organization, role: role} ->
        organization_locations = Enum.filter(locations, &(&1.organization_id == organization.id))

        %{
          organization: organization,
          role: role,
          can_manage?: role == :admin,
          locations:
            Enum.map(organization_locations, fn location ->
              %{
                location: location,
                services: Enum.filter(services, &(&1.location_id == location.id)),
                queues: Enum.filter(queues, &(&1.location.id == location.id))
              }
            end)
        }
      end)

    render(conn, :index,
      page_title: "Staff queues",
      staff_email: to_string(conn.assigns.current_user.email),
      organization_groups: organization_groups,
      queue_count: length(queues)
    )
  end

  @doc "Shows the organization name editor to an active organization administrator."
  def edit_organization(conn, %{"organization_id" => organization_id}) do
    case StaffUpdateOrganization.fetch_organization(
           conn.assigns.current_user.id,
           organization_id
         ) do
      {:ok, organization} ->
        render_organization_form(conn, organization, organization.name, [])

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to edit that organization.")
        |> redirect(to: ~p"/staff")
    end
  end

  def edit_organization(conn, _params) do
    conn
    |> put_flash(:error, "Choose an organization to edit.")
    |> redirect(to: ~p"/staff")
  end

  @doc "Updates the organization name after rechecking organization admin access."
  def update_organization(conn, %{"organization_id" => organization_id, "organization" => params}) do
    case StaffUpdateOrganization.update_name(
           conn.assigns.current_user.id,
           organization_id,
           Map.get(params, "name", "")
         ) do
      {:ok, organization} ->
        conn
        |> put_flash(:info, "Organization name updated to #{organization.name}.")
        |> redirect(to: ~p"/staff")

      {:error, :invalid_name} ->
        case StaffUpdateOrganization.fetch_organization(
               conn.assigns.current_user.id,
               organization_id
             ) do
          {:ok, organization} ->
            render_organization_form(
              conn,
              organization,
              Map.get(params, "name", ""),
              ["Enter an organization name between 1 and 120 characters."],
              status: :unprocessable_entity
            )

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "You do not have permission to edit that organization.")
            |> redirect(to: ~p"/staff")
        end

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to edit that organization.")
        |> redirect(to: ~p"/staff")
    end
  end

  def update_organization(conn, _params) do
    conn
    |> put_flash(:error, "The organization details were incomplete.")
    |> redirect(to: ~p"/staff")
  end

  @doc "Shows the location creation form to an organization administrator."
  def new_location(conn, %{"organization_id" => organization_id}) do
    case StaffLocationAdministration.fetch_organization(
           conn.assigns.current_user.id,
           organization_id
         ) do
      {:ok, organization} ->
        render_location_form(
          conn,
          organization,
          nil,
          %{"name" => "", "timezone" => "Etc/UTC"},
          []
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to add locations to that organization.")
        |> redirect(to: ~p"/staff")
    end
  end

  def new_location(conn, _params) do
    conn
    |> put_flash(:error, "Choose an organization before adding a location.")
    |> redirect(to: ~p"/staff")
  end

  @doc "Creates a location in an organization the user actively administers."
  def create_location(conn, %{"organization_id" => organization_id, "location" => params}) do
    case StaffLocationAdministration.create_location(
           conn.assigns.current_user.id,
           organization_id,
           params
         ) do
      {:ok, location} ->
        conn
        |> put_flash(:info, "Location #{location.name} was created.")
        |> redirect(to: ~p"/staff")

      {:error, :invalid_params, errors} ->
        case StaffLocationAdministration.fetch_organization(
               conn.assigns.current_user.id,
               organization_id
             ) do
          {:ok, organization} ->
            render_location_form(conn, organization, nil, params, Enum.map(errors, &elem(&1, 1)),
              status: :unprocessable_entity
            )

          {:error, :not_found} ->
            conn
            |> put_flash(
              :error,
              "You do not have permission to add locations to that organization."
            )
            |> redirect(to: ~p"/staff")
        end

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to add locations to that organization.")
        |> redirect(to: ~p"/staff")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "The location could not be created.")
        |> redirect(to: ~p"/staff")
    end
  end

  def create_location(conn, _params) do
    conn
    |> put_flash(:error, "The location details were incomplete.")
    |> redirect(to: ~p"/staff")
  end

  @doc "Shows the location editor to an administrator of its organization."
  def edit_location(conn, %{"location_id" => location_id}) do
    case StaffLocationAdministration.fetch_location(conn.assigns.current_user.id, location_id) do
      {:ok, %{location: location, organization: organization}} ->
        params = %{"name" => location.name, "timezone" => location.timezone}
        render_location_form(conn, organization, location, params, [])

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to edit that location.")
        |> redirect(to: ~p"/staff")
    end
  end

  def edit_location(conn, _params) do
    conn
    |> put_flash(:error, "Choose a location to edit.")
    |> redirect(to: ~p"/staff")
  end

  @doc "Updates a location's name and timezone without permitting an organization change."
  def update_location(conn, %{"location_id" => location_id, "location" => params}) do
    case StaffLocationAdministration.update_location(
           conn.assigns.current_user.id,
           location_id,
           params
         ) do
      {:ok, location} ->
        conn
        |> put_flash(:info, "Location #{location.name} was updated.")
        |> redirect(to: ~p"/staff")

      {:error, :invalid_params, errors} ->
        render_location_update_error(conn, location_id, params, errors)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to edit that location.")
        |> redirect(to: ~p"/staff")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "The location could not be updated.")
        |> redirect(to: ~p"/staff")
    end
  end

  def update_location(conn, _params) do
    conn
    |> put_flash(:error, "The location details were incomplete.")
    |> redirect(to: ~p"/staff")
  end

  @doc "Activates or deactivates a location for an authorized organization administrator."
  def update_location_availability(conn, %{"location_id" => location_id, "active" => active})
      when active in ["true", "false"] do
    active? = active == "true"

    case StaffSetLocationAvailability.set_active(
           conn.assigns.current_user.id,
           location_id,
           active?
         ) do
      {:ok, location} ->
        message =
          if active?, do: "#{location.name} is active.", else: "#{location.name} is inactive."

        conn
        |> put_flash(:info, message)
        |> redirect(to: ~p"/staff")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to change that location.")
        |> redirect(to: ~p"/staff")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "The location availability could not be changed.")
        |> redirect(to: ~p"/staff")
    end
  end

  def update_location_availability(conn, _params) do
    conn
    |> put_flash(:error, "The location availability setting was invalid.")
    |> redirect(to: ~p"/staff")
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

        public_url = request_url(conn, "/q/#{context.queue.public_slug}")
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

  @doc "Activates or deactivates a queue for an authorized organization administrator."
  def update_availability(conn, %{"queue_id" => queue_id, "active" => active})
      when active in ["true", "false"] do
    active? = active == "true"

    case StaffSetQueueAvailability.set_active(conn.assigns.current_user.id, queue_id, active?) do
      {:ok, queue} ->
        message = if active?, do: "#{queue.name} is active.", else: "#{queue.name} is inactive."

        conn
        |> put_flash(:info, message)
        |> redirect(to: ~p"/staff")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to change that queue.")
        |> redirect(to: ~p"/staff")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "The queue availability could not be changed.")
        |> redirect(to: ~p"/staff")
    end
  end

  def update_availability(conn, _params) do
    conn
    |> put_flash(:error, "The queue availability setting was invalid.")
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

  defp render_organization_form(conn, organization, name, errors, opts \\ []) do
    render(conn, :edit_organization,
      page_title: "Organization details",
      staff_email: to_string(conn.assigns.current_user.email),
      organization: organization,
      form: Phoenix.Component.to_form(%{"name" => name}, as: :organization),
      errors: errors,
      status: Keyword.get(opts, :status, :ok)
    )
  end

  defp render_location_form(conn, organization, location, params, errors, opts \\ []) do
    {form_action, method, submit_label, page_title} =
      case location do
        nil ->
          {~p"/staff/organizations/#{organization.id}/locations", "post", "Add location",
           "Add location"}

        location ->
          {~p"/staff/locations/#{location.id}", "put", "Save changes", "Edit location"}
      end

    render(conn, :location_form,
      page_title: page_title,
      staff_email: to_string(conn.assigns.current_user.email),
      organization: organization,
      location: location,
      form_action: form_action,
      method: method,
      submit_label: submit_label,
      form: Phoenix.Component.to_form(params, as: :location),
      errors: errors,
      status: Keyword.get(opts, :status, :ok)
    )
  end

  defp render_location_update_error(conn, location_id, params, errors) do
    case StaffLocationAdministration.fetch_location(conn.assigns.current_user.id, location_id) do
      {:ok, %{location: location, organization: organization}} ->
        render_location_form(conn, organization, location, params, Enum.map(errors, &elem(&1, 1)),
          status: :unprocessable_entity
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to edit that location.")
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
        public_url = request_url(conn, "/q/#{context.queue.public_slug}")

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

  defp request_url(conn, path) do
    uri = URI.parse(Plug.Conn.request_url(conn))
    URI.to_string(%{uri | path: path, query: nil, fragment: nil})
  end
end
