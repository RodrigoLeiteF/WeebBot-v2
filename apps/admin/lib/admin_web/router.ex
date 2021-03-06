defmodule AdminWeb.Router do
  use AdminWeb, :router

  import AdminWeb.UserAuth
  import Redirect

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {AdminWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_user)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  redirect(
    "/invite",
    "https://discord.com/oauth2/authorize?client_id=198479757900251136&scope=bot&permissions=412736",
    :permanent
  )

  scope "/", AdminWeb do
    pipe_through(:browser)

    live("/", HomeLive, :index)
    live("/help", HelpLive, :index)
  end

  scope "/user", AdminWeb do
    pipe_through([:browser, :require_authenticated_user])

    live("/settings", PageLive, :index)
  end

  # Other scopes may use custom stacks.
  # scope "/api", AdminWeb do
  #   pipe_through :api
  # end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through(:browser)
      live_dashboard("/dashboard", metrics: AdminWeb.Telemetry)
    end
  end

  ## Authentication routes

  scope "/", AdminWeb do
    pipe_through([:browser, :redirect_if_user_is_authenticated])
    get("/auth/:provider", UserOauthController, :request)
    get("/auth/:provider/callback", UserOauthController, :callback)
  end

  scope "/", AdminWeb do
    pipe_through([:browser, :redirect_if_user_is_authenticated])

    get("/users/register", UserRegistrationController, :new)
    post("/users/register", UserRegistrationController, :create)
    get("/users/log_in", UserSessionController, :new)
    post("/users/log_in", UserSessionController, :create)
  end

  scope "/", AdminWeb do
    pipe_through([:browser, :require_authenticated_user])

    get("/users/settings", UserSettingsController, :edit)
    put("/users/settings", UserSettingsController, :update)
    get("/users/settings/confirm_email/:token", UserSettingsController, :confirm_email)
  end

  scope "/", AdminWeb do
    pipe_through([:browser])

    delete("/users/log_out", UserSessionController, :delete)
    get("/users/confirm", UserConfirmationController, :new)
    post("/users/confirm", UserConfirmationController, :create)
    get("/users/confirm/:token", UserConfirmationController, :confirm)
  end
end
