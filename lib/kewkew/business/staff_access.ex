defmodule Kewkew.Business.StaffAccess do
  @moduledoc "Checks staff membership and manages organization/location assignments."

  import Ecto.Query

  alias Kewkew.Business.{
    Location,
    Organization,
    Service,
    StaffLocationAccess,
    StaffMembership,
    StaffMembershipAudit
  }

  alias Kewkew.Queues.{Queue, QueueSession}
  alias Kewkew.Repo

  def has_active_membership?(user_id) do
    Repo.exists?(
      from membership in StaffMembership,
        where: membership.user_id == ^user_id and membership.active?
    )
  end

  def can_access_location?(user_id, location_id) do
    Repo.exists?(
      from membership in StaffMembership,
        join: location in Location,
        on: location.organization_id == membership.organization_id,
        left_join: assignment in StaffLocationAccess,
        on:
          assignment.staff_membership_id == membership.id and
            assignment.location_id == location.id,
        where:
          membership.user_id == ^user_id and membership.active? and location.id == ^location_id,
        where: membership.role == :admin or not is_nil(assignment.id)
    )
  end

  def can_manage_organization?(user_id, organization_id) do
    Repo.exists?(
      from membership in StaffMembership,
        where:
          membership.user_id == ^user_id and membership.organization_id == ^organization_id and
            membership.active? and membership.role == :admin
    )
  end

  def organizations_for_user(user_id) do
    Repo.all(
      from membership in StaffMembership,
        join: organization in Organization,
        on: organization.id == membership.organization_id,
        where: membership.user_id == ^user_id and membership.active?,
        order_by: [asc: organization.name],
        select: %{organization: organization, role: membership.role}
    )
  end

  def admin_location_for_user(user_id, location_id) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, location_id} <- Ecto.UUID.cast(location_id) do
      Repo.one(
        from location in Location,
          join: membership in StaffMembership,
          on: membership.organization_id == location.organization_id,
          where:
            location.id == ^location_id and membership.user_id == ^user_id and
              membership.active? and membership.role == :admin,
          limit: 1
      )
    else
      _ -> nil
    end
  end

  def locations_for_user(user_id) do
    Repo.all(
      from location in Location,
        join: membership in StaffMembership,
        on: membership.organization_id == location.organization_id,
        left_join: assignment in StaffLocationAccess,
        on:
          assignment.staff_membership_id == membership.id and
            assignment.location_id == location.id,
        where:
          membership.user_id == ^user_id and membership.active? and
            (membership.role == :admin or not is_nil(assignment.id)),
        order_by: [asc: location.name],
        distinct: true
    )
  end

  def services_for_locations([]), do: []

  def services_for_locations(location_ids) do
    Repo.all(
      from service in Service,
        where: service.location_id in ^location_ids,
        order_by: [asc: service.name]
    )
  end

  def queues_for_user(user_id) do
    queues =
      Repo.all(
        from queue in Queue,
          join: service in Service,
          on: service.id == queue.service_id,
          join: location in Location,
          on: location.id == queue.location_id and service.location_id == location.id,
          join: organization in Organization,
          on: organization.id == location.organization_id,
          join: membership in StaffMembership,
          on: membership.organization_id == location.organization_id,
          left_join: assignment in StaffLocationAccess,
          on:
            assignment.staff_membership_id == membership.id and
              assignment.location_id == location.id,
          where:
            membership.user_id == ^user_id and membership.active? and
              (membership.role == :admin or not is_nil(assignment.id)),
          order_by: [asc: location.name, asc: queue.name],
          distinct: true,
          select: %{
            queue: queue,
            location: location,
            service: service,
            organization: organization
          }
      )

    sessions_by_queue = latest_sessions_by_queue(queues)

    Enum.map(queues, fn entry ->
      Map.put(entry, :session, Map.get(sessions_by_queue, entry.queue.id))
    end)
  end

  defp latest_sessions_by_queue([]), do: %{}

  defp latest_sessions_by_queue(queues) do
    queue_ids = Enum.map(queues, & &1.queue.id)

    QueueSession
    |> where([session], session.queue_id in ^queue_ids)
    |> distinct([session], session.queue_id)
    |> order_by([session],
      asc: session.queue_id,
      desc: session.opened_at,
      desc: session.inserted_at
    )
    |> Repo.all()
    |> Map.new(&{&1.queue_id, &1})
  end

  def queue_for_user(user_id, queue_id) do
    with {:ok, queue_id} <- Ecto.UUID.cast(queue_id),
         {:ok, user_id} <- Ecto.UUID.cast(user_id) do
      Repo.one(
        from queue in Queue,
          join: service in Service,
          on: service.id == queue.service_id,
          join: location in Location,
          on: location.id == queue.location_id and service.location_id == location.id,
          join: organization in Organization,
          on: organization.id == location.organization_id,
          join: membership in StaffMembership,
          on: membership.organization_id == location.organization_id,
          left_join: assignment in StaffLocationAccess,
          on:
            assignment.staff_membership_id == membership.id and
              assignment.location_id == location.id,
          where:
            queue.id == ^queue_id and membership.user_id == ^user_id and membership.active? and
              (membership.role == :admin or not is_nil(assignment.id)),
          select: %{
            queue: queue,
            location: location,
            service: service,
            organization: organization
          },
          limit: 1
      )
    else
      _ -> nil
    end
  end

  def grant_membership(actor_id, user_id, organization_id, role, location_ids \\ [])

  def grant_membership(actor_id, user_id, organization_id, role, location_ids)
      when role in [:admin, :operator] and is_list(location_ids) do
    Repo.transaction(fn ->
      ensure_organization_admin!(actor_id, organization_id)
      ensure_user!(user_id)
      ensure_role_locations!(organization_id, role, location_ids)

      membership =
        Repo.one(
          from membership in StaffMembership,
            where:
              membership.user_id == ^user_id and
                membership.organization_id == ^organization_id,
            lock: "FOR UPDATE"
        )

      membership =
        case membership do
          nil ->
            Ash.create!(
              StaffMembership,
              %{user_id: user_id, organization_id: organization_id, role: role},
              action: :grant,
              domain: Kewkew.Business,
              authorize?: false
            )

          existing ->
            existing
            |> Ecto.Changeset.change(role: role, active?: true)
            |> Repo.update!()
        end

      Repo.delete_all(
        from assignment in StaffLocationAccess,
          where: assignment.staff_membership_id == ^membership.id
      )

      if role == :operator do
        Enum.each(location_ids, fn location_id ->
          Ash.create!(
            StaffLocationAccess,
            %{staff_membership_id: membership.id, location_id: location_id},
            action: :assign,
            domain: Kewkew.Business,
            authorize?: false
          )
        end)
      end

      membership
    end)
  end

  def grant_membership(_actor_id, _user_id, _organization_id, _role, _location_ids),
    do: {:error, :invalid_membership}

  def revoke_membership(actor_id, membership_id) do
    set_membership_active(actor_id, membership_id, false)
  end

  def set_membership_active(actor_id, membership_id, active?) when is_boolean(active?) do
    set_membership_active(actor_id, nil, membership_id, active?)
  end

  def set_membership_active(_actor_id, _membership_id, _active?),
    do: {:error, :invalid_membership}

  def set_membership_active(actor_id, organization_id, membership_id, active?)
      when is_boolean(active?) do
    Repo.transaction(fn ->
      membership =
        Repo.one(
          from membership in StaffMembership,
            where:
              membership.id == ^membership_id and
                (is_nil(^organization_id) or membership.organization_id == ^organization_id),
            lock: "FOR UPDATE"
        ) || Repo.rollback(:membership_not_found)

      Repo.one!(
        from organization in Organization,
          where: organization.id == ^membership.organization_id,
          lock: "FOR UPDATE"
      )

      ensure_organization_admin!(actor_id, membership.organization_id)

      if membership.active? and membership.role == :admin and
           active_admin_count(membership.organization_id) == 1 do
        Repo.rollback(:last_active_admin)
      end

      if membership.active? != active? do
        membership = membership |> Ecto.Changeset.change(active?: active?) |> Repo.update!()

        %StaffMembershipAudit{
          actor_id: actor_id,
          member_id: membership.user_id,
          organization_id: membership.organization_id,
          membership_id: membership.id,
          change: if(active?, do: :restored, else: :suspended),
          occurred_at: DateTime.utc_now()
        }
        |> Repo.insert!()

        membership
      else
        membership
      end
    end)
  end

  def set_membership_active(_actor_id, _organization_id, _membership_id, _active?),
    do: {:error, :invalid_membership}

  def memberships_for_organization(actor_id, organization_id) do
    with {:ok, actor_id} <- Ecto.UUID.cast(actor_id),
         {:ok, organization_id} <- Ecto.UUID.cast(organization_id),
         true <- can_manage_organization?(actor_id, organization_id) do
      Repo.all(
        from membership in StaffMembership,
          join: user in Kewkew.Accounts.User,
          on: user.id == membership.user_id,
          where: membership.organization_id == ^organization_id,
          order_by: [asc: user.email],
          select: %{membership: membership, email: user.email}
      )
    else
      _ -> {:error, :not_found}
    end
  end

  def staff_membership_for_admin(actor_id, organization_id, membership_id) do
    with {:ok, actor_id} <- Ecto.UUID.cast(actor_id),
         {:ok, organization_id} <- Ecto.UUID.cast(organization_id),
         {:ok, membership_id} <- Ecto.UUID.cast(membership_id),
         true <- can_manage_organization?(actor_id, organization_id),
         %{membership: %StaffMembership{}} = result <-
           Repo.one(
             from membership in StaffMembership,
               join: user in Kewkew.Accounts.User,
               on: user.id == membership.user_id,
               where:
                 membership.id == ^membership_id and
                   membership.organization_id == ^organization_id,
               select: %{membership: membership, email: user.email}
           ) do
      location_ids =
        Repo.all(
          from assignment in StaffLocationAccess,
            where: assignment.staff_membership_id == ^membership_id,
            select: assignment.location_id
        )

      {:ok, Map.put(result, :location_ids, location_ids)}
    else
      _ -> {:error, :not_found}
    end
  end

  def update_membership_access(actor_id, organization_id, membership_id, role, location_ids)
      when role in [:admin, :operator] and is_list(location_ids) do
    with {:ok, actor_id} <- Ecto.UUID.cast(actor_id),
         {:ok, organization_id} <- Ecto.UUID.cast(organization_id),
         {:ok, membership_id} <- Ecto.UUID.cast(membership_id),
         {:ok, location_ids} <- cast_location_ids(location_ids) do
      Repo.transaction(fn ->
        membership =
          Repo.one(
            from membership in StaffMembership,
              where:
                membership.id == ^membership_id and
                  membership.organization_id == ^organization_id,
              lock: "FOR UPDATE"
          ) || Repo.rollback(:not_found)

        Repo.one!(
          from organization in Organization,
            where: organization.id == ^organization_id,
            lock: "FOR UPDATE"
        )

        ensure_organization_admin!(actor_id, organization_id)
        ensure_role_locations!(organization_id, role, location_ids)

        if membership.active? and membership.role == :admin and role == :operator and
             active_admin_count(organization_id) == 1 do
          Repo.rollback(:last_active_admin)
        end

        updated_membership =
          case Ash.update(membership, %{role: role},
                 action: :change_role,
                 domain: Kewkew.Business,
                 actor: %Kewkew.Accounts.User{id: actor_id}
               ) do
            {:ok, updated_membership} -> updated_membership
            {:error, _} -> Repo.rollback(:invalid_membership)
          end

        Repo.delete_all(
          from assignment in StaffLocationAccess,
            where: assignment.staff_membership_id == ^membership_id
        )

        if role == :operator do
          Enum.each(location_ids, fn location_id ->
            Ash.create!(
              StaffLocationAccess,
              %{staff_membership_id: membership_id, location_id: location_id},
              action: :assign,
              domain: Kewkew.Business,
              authorize?: false
            )
          end)
        end

        updated_membership
      end)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_membership}
    end
  end

  def update_membership_access(_actor_id, _organization_id, _membership_id, _role, _location_ids),
    do: {:error, :invalid_membership}

  defp ensure_organization_admin!(actor_id, organization_id) do
    unless can_manage_organization?(actor_id, organization_id),
      do: Repo.rollback(:forbidden)
  end

  defp ensure_user!(user_id) do
    unless Repo.exists?(from user in Kewkew.Accounts.User, where: user.id == ^user_id),
      do: Repo.rollback(:user_not_found)
  end

  defp ensure_role_locations!(organization_id, :admin, _location_ids) do
    unless Repo.exists?(from org in Organization, where: org.id == ^organization_id),
      do: Repo.rollback(:organization_not_found)
  end

  defp ensure_role_locations!(organization_id, :operator, location_ids) do
    valid_ids =
      Repo.all(
        from location in Location,
          where: location.organization_id == ^organization_id and location.id in ^location_ids,
          select: location.id
      )

    if location_ids == [] or Enum.sort(valid_ids) != Enum.sort(Enum.uniq(location_ids)),
      do: Repo.rollback(:invalid_location_assignment)
  end

  defp cast_location_ids(location_ids) do
    cast_ids = Enum.map(location_ids, &Ecto.UUID.cast/1)

    if Enum.all?(cast_ids, &match?({:ok, _}, &1)) do
      {:ok,
       cast_ids
       |> Enum.map(fn {:ok, id} -> id end)
       |> Enum.uniq()}
    else
      {:error, :invalid_location_assignment}
    end
  end

  defp active_admin_count(organization_id) do
    Repo.aggregate(
      from(membership in StaffMembership,
        where:
          membership.organization_id == ^organization_id and membership.active? and
            membership.role == :admin
      ),
      :count
    )
  end
end
