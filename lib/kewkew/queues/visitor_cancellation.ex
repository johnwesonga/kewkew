defmodule Kewkew.Queues.VisitorCancellation do
  @moduledoc "Cancels a visitor's ticket using its private tracking credential."

  import Ecto.Query

  alias Kewkew.Queues.{Ticket, TicketEvent, TrackingCredential}
  alias Kewkew.Repo

  def cancel_by_tracking_token(token) when is_binary(token) do
    token_digest = digest(token)

    Repo.transaction(fn ->
      with %TrackingCredential{} = credential <- find_credential(token_digest),
           :ok <- credential_is_valid(credential),
           %Ticket{} = ticket <- lock_ticket(credential.ticket_id) do
        cancel_ticket(ticket)
      else
        _ -> Repo.rollback(:unavailable)
      end
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  def cancel_by_tracking_token(_token), do: {:error, :unavailable}

  defp find_credential(token_digest) do
    Repo.one(
      from credential in TrackingCredential,
        where: credential.token_digest == ^token_digest,
        lock: "FOR UPDATE"
    )
  end

  defp lock_ticket(ticket_id) do
    Repo.one(from ticket in Ticket, where: ticket.id == ^ticket_id, lock: "FOR UPDATE")
  end

  defp credential_is_valid(%TrackingCredential{revoked_at: revoked_at})
       when not is_nil(revoked_at),
       do: {:error, :unavailable}

  defp credential_is_valid(%TrackingCredential{expires_at: expires_at})
       when not is_nil(expires_at) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt,
      do: :ok,
      else: {:error, :unavailable}
  end

  defp credential_is_valid(_credential), do: :ok

  defp cancel_ticket(%Ticket{status: :cancelled}), do: :already_cancelled

  defp cancel_ticket(%Ticket{status: status}) when status != :waiting,
    do: Repo.rollback(:not_allowed)

  defp cancel_ticket(%Ticket{} = ticket) do
    now = DateTime.utc_now()

    ticket
    |> Ecto.Changeset.change(status: :cancelled, cancelled_at: now)
    |> Repo.update!()

    Ash.create!(
      TicketEvent,
      %{
        ticket_id: ticket.id,
        from_status: :waiting,
        to_status: :cancelled,
        actor_type: :visitor,
        occurred_at: now
      },
      action: :record_transition,
      domain: Kewkew.Queues
    )

    :cancelled
  end

  defp digest(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
end
