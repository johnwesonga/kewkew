defmodule Mix.Tasks.Kewkew.BootstrapAdmin do
  @moduledoc "Bootstraps the first Kewkew organization administrator from environment variables."
  @shortdoc "Create the initial organization administrator"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    email = required_env!("KEWKEW_ADMIN_EMAIL")
    password = required_env!("KEWKEW_ADMIN_PASSWORD")
    organization_name = required_env!("KEWKEW_ORGANIZATION_NAME")
    location_name = required_env!("KEWKEW_LOCATION_NAME")

    case Kewkew.Accounts.StaffProvisioning.bootstrap_initial_admin(
           email,
           password,
           organization_name,
           location_name
         ) do
      {:ok, %{organization: organization, location: location}} ->
        Mix.shell().info(
          "Created the initial Kewkew administrator for #{organization.name} at #{location.name}."
        )

      {:error, :already_initialized} ->
        Mix.raise("Kewkew already has an organization or staff user; bootstrap is disabled.")

      {:error, reason} ->
        Mix.raise("Could not create the initial Kewkew administrator: #{inspect(reason)}")
    end
  end

  defp required_env!(key) do
    System.get_env(key) || Mix.raise("Set #{key} before bootstrapping the first administrator.")
  end
end
