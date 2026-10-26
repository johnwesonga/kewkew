defmodule Kewkew.Queues.BrowserTicketClaims do
  @moduledoc "Maintains browser-to-active-ticket claims."

  import Ecto.Query

  alias Kewkew.Queues.BrowserTicketClaim
  alias Kewkew.Repo

  def release_for_ticket(ticket_id) do
    Repo.delete_all(from claim in BrowserTicketClaim, where: claim.ticket_id == ^ticket_id)
  end

  def release_for_session(session_id) do
    Repo.delete_all(
      from claim in BrowserTicketClaim, where: claim.queue_session_id == ^session_id
    )
  end
end
