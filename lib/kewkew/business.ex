defmodule Kewkew.Business do
  @moduledoc """
  Business organizations, locations, services, and staff authorization.
  """

  use Ash.Domain

  resources do
    resource Kewkew.Business.Organization
    resource Kewkew.Business.Location
    resource Kewkew.Business.Service
    resource Kewkew.Business.StaffMembership
    resource Kewkew.Business.StaffLocationAccess
  end
end
