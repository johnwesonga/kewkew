defmodule Kewkew.Accounts.StaffProvisioning do
  @moduledoc "Creates staff identities through trusted administrator workflows."

  alias Kewkew.Accounts.User
  alias Kewkew.Business.{Location, Organization, StaffAccess, StaffMembership}
  alias Kewkew.Repo

  def bootstrap_initial_admin(email, password, organization_name, location_name)
      when is_binary(email) and is_binary(password) and is_binary(organization_name) and
             is_binary(location_name) do
    Repo.transaction(fn ->
      # Serialize concurrent first-run tasks so only one can pass the empty-database check.
      Repo.query!("SELECT pg_advisory_xact_lock($1)", [7_747_767_301])

      if Repo.exists?(User) or Repo.exists?(Organization), do: Repo.rollback(:already_initialized)
      validate_password!(password)

      organization =
        Ash.create!(Organization, %{name: organization_name},
          domain: Kewkew.Business,
          authorize?: false
        )

      location =
        Ash.create!(
          Location,
          %{name: location_name, organization_id: organization.id},
          domain: Kewkew.Business,
          authorize?: false
        )

      user = create_user!(email, password)

      membership =
        Ash.create!(
          StaffMembership,
          %{user_id: user.id, organization_id: organization.id, role: :admin},
          action: :grant,
          domain: Kewkew.Business,
          authorize?: false
        )

      %{user: user, organization: organization, location: location, membership: membership}
    end)
  end

  def bootstrap_initial_admin(_email, _password, _organization_name, _location_name),
    do: {:error, :invalid_bootstrap_details}

  def provision_staff(actor_id, email, password, organization_id, role, location_ids \\ [])

  def provision_staff(actor_id, email, password, organization_id, role, location_ids)
      when is_binary(email) and is_binary(password) and role in [:admin, :operator] and
             is_list(location_ids) do
    Repo.transaction(fn ->
      unless StaffAccess.can_manage_organization?(actor_id, organization_id),
        do: Repo.rollback(:forbidden)

      validate_password!(password)
      user = create_user!(email, password)

      case StaffAccess.grant_membership(actor_id, user.id, organization_id, role, location_ids) do
        {:ok, membership} -> %{user: user, membership: membership}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def provision_staff(_actor_id, _email, _password, _organization_id, _role, _location_ids),
    do: {:error, :invalid_staff_details}

  defp create_user!(email, password) do
    Ash.create!(User, %{email: email, password: password},
      action: :provision_staff_user,
      domain: Kewkew.Accounts,
      authorize?: false
    )
  end

  defp validate_password!(password) when byte_size(password) >= 12, do: :ok
  defp validate_password!(_password), do: Repo.rollback(:password_too_short)
end
