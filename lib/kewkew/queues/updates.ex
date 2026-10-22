defmodule Kewkew.Queues.Updates do
  @moduledoc "Publishes minimal queue-session update signals after persisted changes."

  @doc "Broadcasts that a queue session changed without including ticket or visitor data."
  def broadcast_session_updated(queue_session_id) when is_binary(queue_session_id) do
    Phoenix.PubSub.broadcast(
      Kewkew.PubSub,
      topic(queue_session_id),
      {:queue_session_updated, queue_session_id}
    )
  end

  @doc "Subscribes a connected staff board to one queue session's update signals."
  def subscribe(queue_session_id) when is_binary(queue_session_id) do
    Phoenix.PubSub.subscribe(Kewkew.PubSub, topic(queue_session_id))
  end

  defp topic(queue_session_id), do: "queue-session:#{queue_session_id}"
end
