defmodule Kewkew.Business do
  @moduledoc """
  Business context resources needed to describe a visitor-facing queue.

  Organization ownership and staff membership will be added with the business
  foundation stories.
  """

  use Ash.Domain

  resources do
    resource Kewkew.Business.Location
    resource Kewkew.Business.Service
  end
end
