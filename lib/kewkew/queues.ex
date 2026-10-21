defmodule Kewkew.Queues do
  @moduledoc "Queue configuration, operating sessions, visitor tickets, and ticket history."

  use Ash.Domain

  resources do
    resource Kewkew.Queues.Queue
    resource Kewkew.Queues.QueueSession
    resource Kewkew.Queues.Ticket
    resource Kewkew.Queues.TicketEvent
    resource Kewkew.Queues.TrackingCredential
  end
end
