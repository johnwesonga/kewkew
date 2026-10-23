defmodule Kewkew.Accounts.StaffInvitations do
  @moduledoc "Creates, delivers, and accepts one-time staff invitations."

  import Ecto.Query

  alias Kewkew.Accounts.User
  alias Kewkew.Business.{Location, Organization, StaffAccess, StaffInvitation}
  alias Kewkew.Repo
  alias Kewkew.Mailer
  alias Swoosh.Email

  @expires_in_seconds 7 * 24 * 60 * 60

  def invite(actor_id, organization_id, attrs, base_url) do
    email = Map.get(attrs, "email", "")
    email = if is_binary(email), do: email |> String.trim() |> String.downcase(), else: ""
    role = parse_role(Map.get(attrs, "role"))
    location_ids = Map.get(attrs, "location_ids", [])
    location_ids = if is_list(location_ids), do: Enum.uniq(location_ids), else: []

    with true <- (is_binary(email) and email != "") || {:error, :invalid_invitation},
         role when not is_nil(role) <- role || {:error, :invalid_invitation},
         {:ok, token, invitation} <-
           insert_invitation(actor_id, organization_id, email, role, location_ids),
         :ok <- deliver(invitation, token, base_url),
         {:ok, _} <- mark_delivered(invitation.id) do
      {:ok, invitation}
    end
  end

  def invitation(token) when is_binary(token) do
    with {:ok, hash} <- decode_token(token),
         invitation when not is_nil(invitation) <- valid_invitation(hash) do
      {:ok, invitation}
    else
      _ -> {:error, :invalid_or_expired}
    end
  end

  def invitation(_), do: {:error, :invalid_or_expired}

  def accept(token, password, confirmation) do
    with {:ok, hash} <- decode_token(token),
         {:ok, password} <- validate_password(password, confirmation) do
      Repo.transaction(fn ->
        invitation =
          Repo.one(
            from invitation in StaffInvitation,
              where: invitation.token_hash == ^hash and not is_nil(invitation.delivered_at),
              lock: "FOR UPDATE"
          ) || Repo.rollback(:invalid_or_expired)

        unless invitation.accepted_at == nil and invitation.revoked_at == nil and
                 DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :gt do
          Repo.rollback(:invalid_or_expired)
        end

        user =
          Repo.one(
            from user in User, where: fragment("lower(?) = ?", user.email, ^invitation.email)
          )

        user =
          if user do
            user
          else
            case Ash.create(User, %{email: invitation.email, password: password},
                   action: :provision_staff_user,
                   domain: Kewkew.Accounts,
                   authorize?: false
                 ) do
              {:ok, user} -> user
              {:error, _} -> Repo.rollback(:account_creation_failed)
            end
          end

        # Existing identities keep their current password; this flow never resets credentials.
        case grant_invited_membership(
               user.id,
               invitation.organization_id,
               invitation.role,
               invitation.location_ids
             ) do
          {:ok, membership} -> membership
          {:error, reason} -> Repo.rollback(reason)
        end

        invitation
        |> Ecto.Changeset.change(accepted_at: DateTime.utc_now())
        |> Repo.update!()

        user
      end)
    end
  end

  defp grant_invited_membership(user_id, organization_id, role, location_ids) do
    Repo.transaction(fn ->
      unless Repo.exists?(from org in Organization, where: org.id == ^organization_id),
        do: Repo.rollback(:organization_not_found)

      membership =
        Repo.one(
          from membership in Kewkew.Business.StaffMembership,
            where:
              membership.user_id == ^user_id and
                membership.organization_id == ^organization_id,
            lock: "FOR UPDATE"
        )

      membership =
        case membership do
          nil ->
            Ash.create!(
              Kewkew.Business.StaffMembership,
              %{user_id: user_id, organization_id: organization_id, role: role},
              action: :grant,
              domain: Kewkew.Business,
              authorize?: false
            )

          existing ->
            existing |> Ecto.Changeset.change(role: role, active?: true) |> Repo.update!()
        end

      Repo.delete_all(
        from access in Kewkew.Business.StaffLocationAccess,
          where: access.staff_membership_id == ^membership.id
      )

      if role == :operator do
        Enum.each(location_ids, fn location_id ->
          Ash.create!(
            Kewkew.Business.StaffLocationAccess,
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

  defp insert_invitation(actor_id, organization_id, email, role, location_ids) do
    with {:ok, actor_id} <- Ecto.UUID.cast(actor_id),
         {:ok, organization_id} <- Ecto.UUID.cast(organization_id),
         true <-
           StaffAccess.can_manage_organization?(actor_id, organization_id) || {:error, :forbidden},
         :ok <- validate_locations(organization_id, role, location_ids) do
      token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      hash = :crypto.hash(:sha256, token)
      now = DateTime.utc_now()

      result =
        Repo.transaction(fn ->
          Repo.update_all(
            from(invitation in StaffInvitation,
              where:
                invitation.organization_id == ^organization_id and invitation.email == ^email and
                  is_nil(invitation.accepted_at) and is_nil(invitation.revoked_at)
            ),
            set: [revoked_at: now]
          )

          %StaffInvitation{}
          |> StaffInvitation.changeset(%{
            email: email,
            role: role,
            token_hash: hash,
            expires_at: DateTime.add(now, @expires_in_seconds, :second),
            organization_id: organization_id,
            invited_by_id: actor_id
          })
          |> Ecto.Changeset.put_change(:location_ids, location_ids)
          |> Repo.insert()
          |> case do
            {:ok, invitation} -> invitation
            {:error, _} -> Repo.rollback(:invalid_invitation)
          end
        end)

      with {:ok, invitation} <- result, do: {:ok, token, invitation}
    else
      false -> {:error, :forbidden}
      {:error, _} = error -> error
      _ -> {:error, :invalid_invitation}
    end
  end

  defp validate_locations(_organization_id, :admin, _ids), do: :ok

  defp validate_locations(organization_id, :operator, ids) when ids != [] do
    valid =
      Repo.all(
        from location in Location,
          where: location.organization_id == ^organization_id and location.id in ^ids,
          select: location.id
      )

    if Enum.sort(valid) == Enum.sort(ids), do: :ok, else: {:error, :invalid_location_assignment}
  end

  defp validate_locations(_, _, _), do: {:error, :invalid_location_assignment}

  defp valid_invitation(hash) do
    now = DateTime.utc_now()

    Repo.one(
      from invitation in StaffInvitation,
        join: organization in Organization,
        on: organization.id == invitation.organization_id,
        where:
          invitation.token_hash == ^hash and is_nil(invitation.accepted_at) and
            is_nil(invitation.revoked_at) and not is_nil(invitation.delivered_at) and
            invitation.expires_at > ^now,
        select: %{
          id: invitation.id,
          email: invitation.email,
          role: invitation.role,
          location_ids: invitation.location_ids,
          organization_id: invitation.organization_id,
          invited_by_id: invitation.invited_by_id,
          expires_at: invitation.expires_at,
          accepted_at: invitation.accepted_at,
          revoked_at: invitation.revoked_at,
          delivered_at: invitation.delivered_at,
          organization_name: organization.name
        }
    )
  end

  defp mark_delivered(invitation_id) do
    {count, _} =
      Repo.update_all(
        from(invitation in StaffInvitation, where: invitation.id == ^invitation_id),
        set: [delivered_at: DateTime.utc_now()]
      )

    if count == 1, do: {:ok, count}, else: {:error, :delivery_failed}
  end

  defp deliver(invitation, token, base_url) do
    link = base_url <> "/staff/invitations/#{token}"

    email =
      Email.new()
      |> Email.to(invitation.email)
      |> Email.from({"Kewkew", "no-reply@kewkew.app"})
      |> Email.subject("Invitation to join Kewkew")
      |> Email.text_body(
        "You have been invited to join Kewkew. Accept your invitation within 7 days: #{link}"
      )

    case Mailer.deliver(email) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :delivery_failed}
    end
  end

  defp decode_token(token) do
    with {:ok, raw} <- Base.url_decode64(token, padding: false),
         true <- byte_size(raw) == 32 do
      {:ok, :crypto.hash(:sha256, token)}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp validate_password(password, confirmation)
       when is_binary(password) and password == confirmation and byte_size(password) >= 12,
       do: {:ok, password}

  defp validate_password(_, _), do: {:error, :invalid_password}

  defp parse_role("admin"), do: :admin
  defp parse_role("operator"), do: :operator
  defp parse_role(_), do: nil
end
