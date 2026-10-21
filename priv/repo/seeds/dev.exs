if Mix.env() != :dev do
  raise "The development seed script can only run in the dev environment"
end

require Ash.Query

alias Kewkew.Business
alias Kewkew.Business.Location
alias Kewkew.Business.Service
alias Kewkew.Queues
alias Kewkew.Queues.{Queue, QueueSession}

location =
  Ash.read_one!(Ash.Query.filter(Location, name == ^"Riverside Community Hub"),
    domain: Business
  ) ||
    Ash.create!(Location, %{name: "Riverside Community Hub", timezone: "Africa/Nairobi"},
      domain: Business
    )

service =
  Ash.read_one!(
    Ash.Query.filter(
      Service,
      location_id == ^location.id and name == ^"Community food support"
    ),
    domain: Business
  ) ||
    Ash.create!(
      Service,
      %{
        name: "Community food support",
        description: "Food bank collection and support",
        location_id: location.id
      },
      domain: Business
    )

queue =
  Ash.read_one!(
    Ash.Query.filter(Queue, public_slug == ^"riverside-food-support"),
    domain: Queues
  ) ||
    Ash.create!(
      Queue,
      %{
        name: "Food support",
        public_slug: "riverside-food-support",
        identity_policy: :name_required,
        location_id: location.id,
        service_id: service.id
      },
      domain: Queues
    )

latest_session =
  Ash.read_one!(
    Ash.Query.for_read(QueueSession, :latest_for_queue, %{queue_id: queue.id}),
    domain: Queues
  )

if is_nil(latest_session) or latest_session.status == :closed do
  Ash.create!(QueueSession, %{queue_id: queue.id}, domain: Queues)
end

IO.puts("Development queue is available at /q/#{queue.public_slug}")
