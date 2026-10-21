defmodule KewkewWeb.Router do
  use KewkewWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KewkewWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", KewkewWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/q/:slug", VisitorQueueController, :show
    get "/q/:slug/join", VisitorQueueController, :join
    post "/q/:slug/join", VisitorQueueController, :create_join
    get "/locations/:location_id/services", VisitorQueueController, :services
    get "/t/:token", VisitorQueueController, :track
    get "/t/:token/status", VisitorQueueController, :track_status
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
