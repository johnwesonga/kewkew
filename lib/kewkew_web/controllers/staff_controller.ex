defmodule KewkewWeb.StaffController do
  @moduledoc "Authenticated staff landing page."

  use KewkewWeb, :controller

  alias Kewkew.Business.StaffUpdateOrganization
  alias Kewkew.Business.StaffLocationAdministration
  alias Kewkew.Business.StaffSetLocationAvailability
  alias Kewkew.Business.StaffServiceAdministration
  alias Kewkew.Business.StaffSetServiceAvailability
  alias Kewkew.Business.StaffAccess
  alias Kewkew.Accounts.StaffInvitations
  alias Kewkew.Queues.StaffCreateQueue
  alias Kewkew.Queues.StaffSetQueueAvailability
  alias Kewkew.Queues.StaffUpdateQueue

  @doc "Shows only the live queues available to the signed-in staff member."
  def index(conn, _params) do
    user_id = conn.assigns.current_user.id
    queues = StaffAccess.queues_for_user(user_id)
    can_setup? = Enum.any?(StaffAccess.organizations_for_user(user_id), &(&1.role == :admin))

    render(conn, :index,
      page_title: "Live queues",
      staff_email: to_string(conn.assigns.current_user.email),
      queues: queues,
      queue_count: length(queues),
      can_setup?: can_setup?
    )
  end

  @doc "Shows setup tools to staff with at least one active administrator membership."
  def setup(conn, _params) do
    user_id = conn.assigns.current_user.id

    with {:ok, data} <- load_setup_data(user_id) do
      render(conn, :setup,
        page_title: "Workspace setup",
        staff_email: to_string(conn.assigns.current_user.email),
        organizations: data.organizations,
        organization_count: length(data.organizations),
        location_count: length(data.locations),
        service_count: length(data.services),
        queue_count: length(data.queues),
        member_count:
          Enum.reduce(data.members_by_organization, 0, fn {_id, members}, count ->
            count + length(members)
          end),
        can_setup?: true
      )
    else
      :forbidden -> setup_forbidden(conn)
    end
  end

  def setup_locations(conn, _params) do
    with {:ok, data} <- load_setup_data(conn.assigns.current_user.id) do
      rows =
        Enum.map(data.locations, fn location ->
          services = Enum.filter(data.services, &(&1.location_id == location.id))
          queues = Enum.filter(data.queues, &(&1.location.id == location.id))

          organization =
            Enum.find_value(
              data.organizations,
              &(&1.organization.id == location.organization_id && &1.organization)
            )

          %{
            location: location,
            organization: organization,
            services: services,
            queue_count: length(queues)
          }
        end)

      render(conn, :setup_locations,
        page_title: "Locations",
        staff_email: to_string(conn.assigns.current_user.email),
        organizations: data.organizations,
        location_rows: rows,
        can_setup?: true
      )
    else
      :forbidden -> setup_forbidden(conn)
    end
  end

  def setup_services(conn, %{"location_id" => location_id}) do
    user_id = conn.assigns.current_user.id

    with {:ok, data} <- load_setup_data(user_id),
         {:ok, %{location: location, organization: organization}} <-
           StaffLocationAdministration.fetch_location(user_id, location_id) do
      services = Enum.filter(data.services, &(&1.location_id == location.id))

      render(conn, :setup_services,
        page_title: "Services · #{location.name}",
        staff_email: to_string(conn.assigns.current_user.email),
        location: location,
        organization: organization,
        services: services,
        can_setup?: true
      )
    else
      :forbidden ->
        setup_forbidden(conn)

      _ ->
        conn
        |> put_flash(:error, "That location is unavailable.")
        |> redirect(to: ~p"/staff/setup/locations")
    end
  end

  def setup_services(conn, _params),
    do:
      conn |> put_flash(:error, "Choose a location.") |> redirect(to: ~p"/staff/setup/locations")

  def setup_services_index(conn, _params) do
    with {:ok, data} <- load_setup_data(conn.assigns.current_user.id) do
      location_groups =
        Enum.map(data.locations, fn location ->
          organization =
            Enum.find_value(data.organizations, fn entry ->
              if entry.organization.id == location.organization_id, do: entry.organization
            end)

          %{
            location: location,
            organization: organization,
            services: Enum.filter(data.services, &(&1.location_id == location.id))
          }
        end)

      render(conn, :setup_all_services,
        page_title: "Services",
        staff_email: to_string(conn.assigns.current_user.email),
        location_groups: location_groups,
        can_setup?: true
      )
    else
      :forbidden -> setup_forbidden(conn)
    end
  end

  def setup_queues(conn, _params) do
    with {:ok, data} <- load_setup_data(conn.assigns.current_user.id) do
      render(conn, :setup_queues,
        page_title: "Queue setup",
        staff_email: to_string(conn.assigns.current_user.email),
        queues: data.queues,
        locations: data.locations,
        organization_names:
          Map.new(data.organizations, fn entry ->
            {entry.organization.id, entry.organization.name}
          end),
        can_setup?: true
      )
    else
      :forbidden -> setup_forbidden(conn)
    end
  end

  def setup_staff(conn, _params) do
    with {:ok, data} <- load_setup_data(conn.assigns.current_user.id) do
      organization_groups =
        Enum.map(data.organizations, fn %{organization: organization} ->
          %{
            organization: organization,
            members: Map.get(data.members_by_organization, organization.id, [])
          }
        end)

      render(conn, :setup_staff,
        page_title: "Staff access",
        staff_email: to_string(conn.assigns.current_user.email),
        organization_groups: organization_groups,
        can_setup?: true
      )
    else
      :forbidden -> setup_forbidden(conn)
    end
  end

  defp load_setup_data(user_id) do
    organizations =
      StaffAccess.organizations_for_user(user_id)
      |> Enum.filter(&(&1.role == :admin))

    if organizations == [] do
      :forbidden
    else
      locations =
        Enum.flat_map(organizations, fn %{organization: organization} ->
          StaffLocationAdministration.locations_for_organization(organization.id)
        end)

      services = StaffAccess.services_for_locations(Enum.map(locations, & &1.id))
      organization_ids = Enum.map(organizations, & &1.organization.id)

      queues =
        StaffAccess.queues_for_user(user_id)
        |> Enum.filter(&(&1.location.organization_id in organization_ids))

      members_by_organization =
        Map.new(organizations, fn %{organization: organization} ->
          {organization.id, StaffAccess.memberships_for_organization(user_id, organization.id)}
        end)

      {:ok,
       %{
         organizations: organizations,
         locations: locations,
         services: services,
         queues: queues,
         members_by_organization: members_by_organization
       }}
    end
  end

  defp setup_forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> text("Setup access is available to active organization administrators only.")
  end

  def new_staff_invitation(conn, %{"organization_id" => organization_id}) do
    case StaffUpdateOrganization.fetch_organization(conn.assigns.current_user.id, organization_id) do
      {:ok, organization} ->
        locations =
          Kewkew.Business.StaffLocationAdministration.locations_for_organization(organization.id)

        render(conn, :new_staff_invitation,
          page_title: "Invite staff",
          staff_email: to_string(conn.assigns.current_user.email),
          organization: organization,
          locations: locations,
          params: %{"email" => "", "role" => "operator", "location_ids" => []},
          form:
            Phoenix.Component.to_form(%{"email" => "", "role" => "operator"}, as: :invitation),
          errors: []
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to invite staff to that organization.")
        |> redirect(to: ~p"/staff")
    end
  end

  def create_staff_invitation(conn, %{
        "organization_id" => organization_id,
        "invitation" => params
      }) do
    base_url = KewkewWeb.Endpoint.url()

    case StaffInvitations.invite(conn.assigns.current_user.id, organization_id, params, base_url) do
      {:ok, _invitation} ->
        conn
        |> put_flash(:info, "Invitation sent to #{String.trim(params["email"])}.")
        |> redirect(to: ~p"/staff/setup/staff")

      {:error, reason} ->
        case StaffUpdateOrganization.fetch_organization(
               conn.assigns.current_user.id,
               organization_id
             ) do
          {:ok, organization} ->
            locations =
              Kewkew.Business.StaffLocationAdministration.locations_for_organization(
                organization.id
              )

            message = invitation_error(reason)

            render(conn, :new_staff_invitation,
              status: :unprocessable_entity,
              page_title: "Invite staff",
              staff_email: to_string(conn.assigns.current_user.email),
              organization: organization,
              locations: locations,
              params: params,
              form: Phoenix.Component.to_form(params, as: :invitation),
              errors: [message]
            )

          {:error, :not_found} ->
            conn
            |> put_flash(
              :error,
              "You do not have permission to invite staff to that organization."
            )
            |> redirect(to: ~p"/staff")
        end
    end
  end

  def create_staff_invitation(conn, _params),
    do:
      conn
      |> put_flash(:error, "The invitation details were incomplete.")
      |> redirect(to: ~p"/staff")

  defp invitation_error(:forbidden),
    do: "You do not have permission to invite staff to this organization."

  defp invitation_error(:invalid_location_assignment),
    do: "Select at least one valid location for an operator."

  defp invitation_error(:delivery_failed),
    do: "The invitation could not be delivered. Please try again."

  defp invitation_error(_), do: "Enter a valid email and role."

  def update_staff_membership(conn, %{
        "organization_id" => organization_id,
        "membership_id" => membership_id,
        "active" => active
      })
      when active in ["true", "false"] do
    active? = active == "true"

    case StaffAccess.set_membership_active(
           conn.assigns.current_user.id,
           organization_id,
           membership_id,
           active?
         ) do
      {:ok, _membership} ->
        conn
        |> put_flash(
          :info,
          if(active?, do: "Staff access restored.", else: "Staff access suspended.")
        )
        |> redirect(to: ~p"/staff/setup/staff")

      {:error, :last_active_admin} ->
        conn
        |> put_flash(:error, "Add or restore another administrator before suspending this one.")
        |> redirect(to: ~p"/staff/setup/staff")

      {:error, _} ->
        conn
        |> put_flash(
          :error,
          "You do not have permission to change staff access in that organization."
        )
        |> redirect(to: ~p"/staff")
    end
  end

  def update_staff_membership(conn, _params),
    do:
      conn
      |> put_flash(:error, "The staff access change was incomplete.")
      |> redirect(to: ~p"/staff")

  def edit_staff_membership(conn, %{
        "organization_id" => organization_id,
        "membership_id" => membership_id
      }) do
    case StaffAccess.staff_membership_for_admin(
           conn.assigns.current_user.id,
           organization_id,
           membership_id
         ) do
      {:ok, %{membership: membership, email: email, location_ids: location_ids}} ->
        case StaffLocationAdministration.fetch_organization(
               conn.assigns.current_user.id,
               organization_id
             ) do
          {:ok, organization} ->
            render_staff_membership_form(
              conn,
              organization,
              membership,
              email,
              %{"role" => Atom.to_string(membership.role), "location_ids" => location_ids},
              [],
              []
            )

          {:error, :not_found} ->
            redirect_staff_access_denied(conn)
        end

      {:error, :not_found} ->
        redirect_staff_access_denied(conn)
    end
  end

  def update_staff_membership_access(conn, %{
        "organization_id" => organization_id,
        "membership_id" => membership_id,
        "membership" => params
      }) do
    role = parse_staff_role(Map.get(params, "role"))
    location_ids = Map.get(params, "location_ids", [])
    location_ids = if is_list(location_ids), do: location_ids, else: []

    case StaffAccess.update_membership_access(
           conn.assigns.current_user.id,
           organization_id,
           membership_id,
           role,
           location_ids
         ) do
      {:ok, _membership} ->
        conn
        |> put_flash(:info, "Staff role and location access updated.")
        |> redirect(to: ~p"/staff/setup/staff")

      {:error, :last_active_admin} ->
        render_membership_access_error(
          conn,
          organization_id,
          membership_id,
          params,
          "Add or promote another active administrator before changing this role."
        )

      {:error, :invalid_location_assignment} ->
        render_membership_access_error(
          conn,
          organization_id,
          membership_id,
          params,
          "Choose at least one location in this organization for an operator."
        )

      {:error, :not_found} ->
        redirect_staff_access_denied(conn)

      {:error, _reason} ->
        render_membership_access_error(
          conn,
          organization_id,
          membership_id,
          params,
          "The staff role and location access could not be updated."
        )
    end
  end

  def update_staff_membership_access(conn, _params),
    do:
      conn
      |> put_flash(:error, "The staff access details were incomplete.")
      |> redirect(to: ~p"/staff/setup/staff")

  defp render_membership_access_error(conn, organization_id, membership_id, params, error) do
    render_staff_membership_form(
      conn,
      organization_id,
      membership_id,
      normalize_membership_params(params),
      [error],
      status: :unprocessable_entity
    )
  end

  defp render_staff_membership_form(
         conn,
         organization,
         membership,
         email,
         params,
         errors,
         opts
       )

  defp render_staff_membership_form(
         conn,
         %Kewkew.Business.Organization{} = organization,
         membership,
         email,
         params,
         errors,
         opts
       ) do
    locations = StaffLocationAdministration.locations_for_organization(organization.id)

    render(conn, :staff_membership_form,
      page_title: "Edit staff access",
      staff_email: to_string(conn.assigns.current_user.email),
      organization: organization,
      membership: membership,
      email: email,
      locations: locations,
      params: normalize_membership_params(params),
      form: Phoenix.Component.to_form(normalize_membership_params(params), as: :membership),
      errors: errors,
      status: Keyword.get(opts, :status, :ok)
    )
  end

  defp render_staff_membership_form(
         conn,
         organization_id,
         membership_id,
         params,
         errors,
         opts
       ) do
    case StaffAccess.staff_membership_for_admin(
           conn.assigns.current_user.id,
           organization_id,
           membership_id
         ) do
      {:ok, %{membership: membership, email: email}} ->
        case StaffLocationAdministration.fetch_organization(
               conn.assigns.current_user.id,
               organization_id
             ) do
          {:ok, organization} ->
            render_staff_membership_form(
              conn,
              organization,
              membership,
              email,
              params,
              errors,
              opts
            )

          {:error, :not_found} ->
            redirect_staff_access_denied(conn)
        end

      {:error, :not_found} ->
        redirect_staff_access_denied(conn)
    end
  end

  defp normalize_membership_params(params) do
    location_ids = Map.get(params, "location_ids", [])

    Map.put(params, "location_ids", if(is_list(location_ids), do: location_ids, else: []))
  end

  defp parse_staff_role("admin"), do: :admin
  defp parse_staff_role("operator"), do: :operator
  defp parse_staff_role(_), do: nil

  defp redirect_staff_access_denied(conn) do
    conn
    |> put_flash(
      :error,
      "You do not have permission to change staff access in that organization."
    )
    |> redirect(to: ~p"/staff")
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
        |> redirect(to: ~p"/staff/setup")

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
        |> redirect(to: ~p"/staff/setup/locations")

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
        |> redirect(to: ~p"/staff/setup/locations")

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
        |> redirect(to: ~p"/staff/setup/locations")

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

  @doc "Shows the service creation form to an administrator of the location's organization."
  def new_service(conn, %{"location_id" => location_id}) do
    case StaffServiceAdministration.fetch_location(conn.assigns.current_user.id, location_id) do
      {:ok, location} ->
        render_service_form(conn, location, nil, %{"name" => "", "description" => ""}, [])

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to add services at that location.")
        |> redirect(to: ~p"/staff")
    end
  end

  def new_service(conn, _params) do
    conn
    |> put_flash(:error, "Choose a location before adding a service.")
    |> redirect(to: ~p"/staff")
  end

  @doc "Creates a service at a location the user actively administers."
  def create_service(conn, %{"location_id" => location_id, "service" => params}) do
    case StaffServiceAdministration.create_service(
           conn.assigns.current_user.id,
           location_id,
           params
         ) do
      {:ok, service} ->
        conn
        |> put_flash(:info, "Service #{service.name} was created.")
        |> redirect(to: ~p"/staff/setup/locations/#{location_id}/services")

      {:error, :invalid_params, errors} ->
        case StaffServiceAdministration.fetch_location(conn.assigns.current_user.id, location_id) do
          {:ok, location} ->
            render_service_form(conn, location, nil, params, Enum.map(errors, &elem(&1, 1)),
              status: :unprocessable_entity
            )

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "You do not have permission to add services at that location.")
            |> redirect(to: ~p"/staff")
        end

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to add services at that location.")
        |> redirect(to: ~p"/staff")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "The service could not be created.")
        |> redirect(to: ~p"/staff")
    end
  end

  def create_service(conn, _params) do
    conn
    |> put_flash(:error, "The service details were incomplete.")
    |> redirect(to: ~p"/staff")
  end

  @doc "Shows the service editor to an administrator of its location's organization."
  def edit_service(conn, %{"service_id" => service_id}) do
    case StaffServiceAdministration.fetch_service(conn.assigns.current_user.id, service_id) do
      {:ok, %{service: service, location: location}} ->
        params = %{"name" => service.name, "description" => service.description || ""}
        render_service_form(conn, location, service, params, [])

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to edit that service.")
        |> redirect(to: ~p"/staff")
    end
  end

  def edit_service(conn, _params) do
    conn
    |> put_flash(:error, "Choose a service to edit.")
    |> redirect(to: ~p"/staff")
  end

  @doc "Updates a service's details without permitting a location change."
  def update_service(conn, %{"service_id" => service_id, "service" => params}) do
    case StaffServiceAdministration.update_service(
           conn.assigns.current_user.id,
           service_id,
           params
         ) do
      {:ok, service} ->
        conn
        |> put_flash(:info, "Service #{service.name} was updated.")
        |> redirect(to: ~p"/staff/setup/locations/#{service.location_id}/services")

      {:error, :invalid_params, errors} ->
        render_service_update_error(conn, service_id, params, Enum.map(errors, &elem(&1, 1)))

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to edit that service.")
        |> redirect(to: ~p"/staff")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "The service could not be updated.")
        |> redirect(to: ~p"/staff")
    end
  end

  def update_service(conn, _params) do
    conn
    |> put_flash(:error, "The service details were incomplete.")
    |> redirect(to: ~p"/staff")
  end

  @doc "Activates or deactivates a service for an authorized organization administrator."
  def update_service_availability(conn, %{"service_id" => service_id, "active" => active})
      when active in ["true", "false"] do
    active? = active == "true"

    case StaffSetServiceAvailability.set_active(
           conn.assigns.current_user.id,
           service_id,
           active?
         ) do
      {:ok, service} ->
        message =
          if active?, do: "#{service.name} is active.", else: "#{service.name} is inactive."

        conn
        |> put_flash(:info, message)
        |> redirect(to: ~p"/staff/setup/locations/#{service.location_id}/services")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to change that service.")
        |> redirect(to: ~p"/staff")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "The service availability could not be changed.")
        |> redirect(to: ~p"/staff")
    end
  end

  def update_service_availability(conn, _params) do
    conn
    |> put_flash(:error, "The service availability setting was invalid.")
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
        |> redirect(to: ~p"/staff/setup/queues")

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
        |> redirect(to: ~p"/staff/setup/queues")

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
        |> redirect(to: ~p"/staff/setup/queues")

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

  defp render_service_form(conn, location, service, params, errors, opts \\ []) do
    {form_action, method, submit_label, page_title} =
      case service do
        nil ->
          {~p"/staff/locations/#{location.id}/services", "post", "Add service", "Add service"}

        service ->
          {~p"/staff/services/#{service.id}", "put", "Save changes", "Edit service"}
      end

    render(conn, :service_form,
      page_title: page_title,
      staff_email: to_string(conn.assigns.current_user.email),
      location: location,
      service: service,
      form_action: form_action,
      method: method,
      submit_label: submit_label,
      form: Phoenix.Component.to_form(params, as: :service),
      errors: errors,
      status: Keyword.get(opts, :status, :ok)
    )
  end

  defp render_service_update_error(conn, service_id, params, errors) do
    case StaffServiceAdministration.fetch_service(conn.assigns.current_user.id, service_id) do
      {:ok, %{service: service, location: location}} ->
        render_service_form(conn, location, service, params, errors,
          status: :unprocessable_entity
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have permission to edit that service.")
        |> redirect(to: ~p"/staff")
    end
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
