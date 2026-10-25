defmodule KewkewWeb.Router do
  use KewkewWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KewkewWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :staff_members_only do
    plug KewkewWeb.Plugs.RequireStaffMembership
  end

  scope "/", KewkewWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {KewkewWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {KewkewWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {KewkewWeb.LiveUserAuth, :live_no_user}
    end
  end

  scope "/", KewkewWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/q/:slug", VisitorQueueController, :show
    get "/q/:slug/join", VisitorQueueController, :join
    post "/q/:slug/join", VisitorQueueController, :create_join
    post "/t/:token/cancel", VisitorQueueController, :cancel_ticket
    get "/locations/:location_id/services", VisitorQueueController, :services
    get "/t/:token", VisitorQueueController, :track
    auth_routes AuthController, Kewkew.Accounts.User, path: "/auth"
    get "/staff/invitations/:token", StaffInvitationController, :show
    post "/staff/invitations/:token", StaffInvitationController, :accept

    sign_out_route AuthController, "/sign-out",
      overrides: [KewkewWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.DaisyUI]

    sign_in_route auth_routes_prefix: "/auth",
                  on_mount: [{KewkewWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    KewkewWeb.AuthOverrides,
                    AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]
  end

  scope "/staff", KewkewWeb do
    pipe_through [:browser, :staff_members_only]

    get "/", StaffController, :index
    get "/setup", StaffController, :setup
    get "/setup/locations", StaffController, :setup_locations
    get "/setup/services", StaffController, :setup_services_index
    get "/setup/locations/:location_id/services", StaffController, :setup_services
    get "/setup/queues", StaffController, :setup_queues
    get "/setup/staff", StaffController, :setup_staff
    get "/organizations/:organization_id/edit", StaffController, :edit_organization
    get "/organizations/:organization_id/staff/new", StaffController, :new_staff_invitation

    get "/organizations/:organization_id/staff/:membership_id/edit",
        StaffController,
        :edit_staff_membership

    put "/organizations/:organization_id/staff/:membership_id/access",
        StaffController,
        :update_staff_membership_access

    post "/organizations/:organization_id/staff/invitations",
         StaffController,
         :create_staff_invitation

    put "/organizations/:organization_id/staff/:membership_id/availability",
        StaffController,
        :update_staff_membership

    put "/organizations/:organization_id", StaffController, :update_organization
    get "/organizations/:organization_id/locations/new", StaffController, :new_location
    post "/organizations/:organization_id/locations", StaffController, :create_location
    get "/locations/:location_id/edit", StaffController, :edit_location
    put "/locations/:location_id", StaffController, :update_location
    put "/locations/:location_id/availability", StaffController, :update_location_availability
    get "/locations/:location_id/services/new", StaffController, :new_service
    post "/locations/:location_id/services", StaffController, :create_service
    get "/services/:service_id/edit", StaffController, :edit_service
    put "/services/:service_id", StaffController, :update_service
    put "/services/:service_id/availability", StaffController, :update_service_availability
    get "/queues/new/:location_id", StaffController, :new
    post "/queues/new/:location_id", StaffController, :create
    get "/queues/:queue_id/edit", StaffController, :edit
    put "/queues/:queue_id", StaffController, :update
    put "/queues/:queue_id/availability", StaffController, :update_availability
    delete "/queues/:queue_id", StaffController, :delete_queue
  end

  scope "/staff", KewkewWeb do
    pipe_through :browser

    ash_authentication_live_session :staff_routes,
      on_mount: [
        {KewkewWeb.LiveUserAuth, :live_user_required},
        {KewkewWeb.StaffLiveAuth, :require_membership}
      ] do
      live "/queues/:queue_id", StaffQueueLive, :show
    end
  end

  scope "/t", KewkewWeb do
    pipe_through :api

    get "/:token/status", VisitorQueueController, :track_status
  end

  scope "/q", KewkewWeb do
    pipe_through :api

    get "/:slug/status", VisitorQueueController, :availability_status
  end

  # Other scopes may use custom stacks.
  # scope "/api", KewkewWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:kewkew, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KewkewWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
