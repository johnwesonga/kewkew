defmodule Kewkew.Queues.QueueSchedule do
  @moduledoc "Recurring signup and service times configured for a queue."

  use Ash.Resource,
    otp_app: :kewkew,
    domain: Kewkew.Queues,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "queue_schedules"
    repo Kewkew.Repo

    custom_indexes do
      index [:queue_id], unique: true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:queue_id, :weekdays, :signup_open_time, :service_start_time, :ticket_cap]
    end

    update :update do
      accept [:weekdays, :signup_open_time, :service_start_time, :ticket_cap]
    end

    destroy :delete
  end

  attributes do
    uuid_primary_key :id

    attribute :weekdays, {:array, :integer} do
      allow_nil? false
      public? true
    end

    attribute :signup_open_time, :time do
      allow_nil? false
      public? true
    end

    attribute :service_start_time, :time do
      allow_nil? false
      public? true
    end

    attribute :ticket_cap, :integer do
      constraints min: 1
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :queue, Kewkew.Queues.Queue do
      allow_nil? false
      public? true
    end
  end
end
