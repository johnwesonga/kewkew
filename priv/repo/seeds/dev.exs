if Mix.env() != :dev do
  raise "The development seed script can only run in the dev environment"
end

require Ash.Query

alias Kewkew.Accounts.User
alias Kewkew.Business
alias Kewkew.Business.Location
alias Kewkew.Business.Organization
alias Kewkew.Business.StaffMembership
alias Kewkew.Business.Service
alias Kewkew.Queues
alias Kewkew.Queues.{Queue, QueueSession}

organization =
  Ash.read_one!(
    Ash.Query.filter(Organization, name == ^"Kewkew Organization"),
    domain: Business,
    authorize?: false
  ) ||
    Ash.create!(Organization, %{name: "Kewkew Organization"},
      domain: Business,
      authorize?: false
    )

location =
  Ash.read_one!(
    Ash.Query.filter(
      Location,
      name == ^"Riverside Community Hub" and organization_id == ^organization.id
    ),
    domain: Business
  ) ||
    Ash.create!(
      Location,
      %{
        name: "Riverside Community Hub",
        timezone: "Africa/Nairobi",
        organization_id: organization.id
      },
      domain: Business
    )

staff_email = System.get_env("KEWKEW_DEV_STAFF_EMAIL") || "admin@kewkew.local"
staff_password = System.get_env("KEWKEW_DEV_STAFF_PASSWORD") || "kewkew-local-admin-password"

staff_user =
  Ash.read_one!(
    Ash.Query.filter(User, email == ^staff_email),
    domain: Kewkew.Accounts,
    authorize?: false
  ) ||
    Ash.create!(
      User,
      %{email: staff_email, password: staff_password},
      action: :provision_staff_user,
      domain: Kewkew.Accounts,
      authorize?: false
    )

staff_membership =
  Ash.read_one!(
    Ash.Query.filter(
      StaffMembership,
      user_id == ^staff_user.id and organization_id == ^organization.id
    ),
    domain: Business,
    authorize?: false
  )

if is_nil(staff_membership) do
  Ash.create!(
    StaffMembership,
    %{user_id: staff_user.id, organization_id: organization.id, role: :admin},
    action: :grant,
    domain: Business,
    authorize?: false
  )
end

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

anonymous_service =
  Ash.read_one!(
    Ash.Query.filter(Service, location_id == ^location.id and name == ^"General enquiries"),
    domain: Business
  ) ||
    Ash.create!(
      Service,
      %{
        name: "General enquiries",
        description: "Get help with general questions",
        location_id: location.id
      },
      domain: Business
    )

anonymous_queue =
  Ash.read_one!(
    Ash.Query.filter(Queue, public_slug == ^"riverside-general-enquiries"),
    domain: Queues
  ) ||
    Ash.create!(
      Queue,
      %{
        name: "General enquiries",
        public_slug: "riverside-general-enquiries",
        identity_policy: :anonymous,
        location_id: location.id,
        service_id: anonymous_service.id
      },
      domain: Queues
    )

anonymous_latest_session =
  Ash.read_one!(
    Ash.Query.for_read(QueueSession, :latest_for_queue, %{queue_id: anonymous_queue.id}),
    domain: Queues
  )

if is_nil(anonymous_latest_session) or anonymous_latest_session.status == :closed do
  Ash.create!(QueueSession, %{queue_id: anonymous_queue.id}, domain: Queues)
end

IO.puts("Name-required demo queue: /q/#{queue.public_slug}")
IO.puts("Anonymous demo queue: /q/#{anonymous_queue.public_slug}")
IO.puts("Local staff sign-in email: #{staff_email}")
