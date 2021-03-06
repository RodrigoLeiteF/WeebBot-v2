defmodule AdminWeb.PageLive do
  use AdminWeb, :live_view

  @impl true
  def mount(_params, %{"user_token" => user_token, "guilds" => guilds}, socket) do
    user = Admin.Accounts.get_user_by_session_token(user_token)

    admin_guilds =
      guilds
      |> Enum.filter(fn x ->
        x
        |> Map.fetch!(:permissions)
        |> Nostrum.Permission.from_bitset()
        |> Enum.member?(:manage_guild)
      end)

    first_guild = admin_guilds |> List.first()
    guild_channels = get_guild_channels(first_guild.id)

    {:ok,
     assign(socket,
       query: "",
       results: %{},
       current_user: user,
       guilds: admin_guilds,
       current_guild: first_guild,
       guild_channels: guild_channels,
       guild_settings: Admin.Guilds.get_guild_settings!(first_guild.id),
       available_settings: Admin.Guilds.list_available_settings()
     )}
  end

  @impl true
  def handle_event("select_guild", values, socket) do
    guild =
      socket.assigns.guilds
      |> Enum.find(fn guild -> guild.id == values["guild"] end)

    {:noreply,
     socket
     |> assign(
       current_guild: guild,
       guild_channels: get_guild_channels(guild.id),
       guild_settings: Admin.Guilds.get_guild_settings!(guild.id)
     )}
  end

  @impl true
  def handle_event("save", values, socket) do
    values |> Admin.Guilds.upsert_settings(socket.assigns.current_guild)

    {:noreply, socket}
  end

  defp search(query) do
    if not AdminWeb.Endpoint.config(:code_reloader) do
      raise "action disabled when not in development"
    end

    for {app, desc, vsn} <- Application.started_applications(),
        app = to_string(app),
        String.starts_with?(app, query) and not List.starts_with?(desc, ~c"ERTS"),
        into: %{},
        do: {app, vsn}
  end

  def get_guild_channels(guild_id) do
    headers = [Authorization: "Bot #{Application.get_env(:nostrum, :token)}"]

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <-
           HTTPoison.get("https://discord.com/api/guilds/#{guild_id}/channels", headers),
         guilds when is_list(guilds) <- Poison.decode!(body) do
      guilds |> Enum.filter(fn guild -> guild["type"] == 0 end)
    else
      {:ok, %HTTPoison.Response{}} -> nil
      %{message: "Missing Access", code: 50001} -> nil
    end
  end
end
