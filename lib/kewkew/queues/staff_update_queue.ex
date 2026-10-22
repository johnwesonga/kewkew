defmodule Kewkew.Queues.StaffUpdateQueue do
  @moduledoc "Updates editable queue configuration for organization administrators."

  import Ecto.Query

  alias Kewkew.Business.{Location, Service, StaffMembership}
  alias Kewkew.Queues.{Queue, StaffCreateQueue}
  alias Kewkew.Repo

  @doc "Loads a queue's editable details for an administrator in its organization."
  def fetch_queue(user_id, queue_id) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, queue_id} <- Ecto.UUID.cast(queue_id),
         %{queue: _queue} = context <- queue_context(user_id, queue_id, false) do
      {:ok, context}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Updates only the queue name, visitor identity policy, and active capacity."
  def update_queue(user_id, queue_id, params)
      when is_binary(user_id) and is_binary(queue_id) and is_map(params) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, queue_id} <- Ecto.UUID.cast(queue_id),
         {:ok, configuration} <- StaffCreateQueue.validate_configuration(params) do
      case Repo.transaction(fn ->
             context = queue_context(user_id, queue_id, true) || Repo.rollback(:not_found)

             case Ash.update(context.queue, configuration,
                    action: :update_configuration,
                    domain: Kewkew.Queues,
                    authorize?: false
                  ) do
               {:ok, queue} -> queue
               {:error, _error} -> Repo.rollback(:invalid_queue)
             end
           end) do
        {:ok, queue} -> {:ok, queue}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_params, errors} -> {:error, :invalid_params, errors}
      _ -> {:error, :not_found}
    end
  end

  def update_queue(_user_id, _queue_id, _params), do: {:error, :not_found}

  defp queue_context(user_id, queue_id, lock?) do
    query =
      from queue in Queue,
        join: location in Location,
        on: location.id == queue.location_id,
        join: service in Service,
        on: service.id == queue.service_id and service.location_id == location.id,
        join: membership in StaffMembership,
        on: membership.organization_id == location.organization_id,
        where:
          queue.id == ^queue_id and membership.user_id == ^user_id and membership.active? and
            membership.role == :admin,
        select: %{queue: queue, location: location, service: service},
        limit: 1

    query = if lock?, do: lock(query, "FOR UPDATE"), else: query

    Repo.one(query)
  end
end
