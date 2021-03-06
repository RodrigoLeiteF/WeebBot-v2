defmodule Admin.Alerts do
  require Logger

  @moduledoc """
  The Alerts context.
  """

  import Ecto.Query, warn: false
  alias Admin.Repo

  alias Admin.Alerts.Alert
  alias Admin.Guilds.Setting

  @in_progress_pattern ~r/【開催中】(\d+)時\s(.+)/
  @upcoming_pattern ~r/^(\d+)時\s\[予告\](.+)\s*(?:#PSO2)*/m

  @pso2_eq_alert_type "pso2_eq_alert_jp"

  @doc """
  Returns the list of alerts.

  ## Examples

      iex> list_alerts()
      [%Alert{}, ...]

  """
  def list_alerts do
    Repo.all(Alert)
  end

  @doc """
  Creates a alert.

  ## Examples

      iex> create_alert(%{field: value})
      {:ok, %Alert{}}

      iex> create_alert(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_alert(content, id, type) do
    Logger.info("New alert of type #{type} and ID #{id} created")

    %Alert{}
    |> Alert.changeset(%{content: content, type: type})
    |> Repo.insert()

    Admin.Cache.set(type, id)

    Phoenix.PubSub.broadcast(Admin.PubSub, "alerts", {type, content})
  end

  def check_twitter() do
    Admin.Cache.get(@pso2_eq_alert_type) |> process_alert()
  end

  defp process_alert(last_tweet_id) do
    eq_tweet =
      ExTwitter.user_timeline(screen_name: "pso2_emg_hour", count: 1)
      |> List.first()

    if is_nil(last_tweet_id) || eq_tweet.id_str != last_tweet_id do
      format_eq_data(eq_tweet)
    end
  end

  defp format_eq_data(tweet) do
    tweet
    |> Map.fetch!(:text)
    |> String.split("\n")
    |> Enum.map(fn x ->
      x
      |> String.replace("#PSO2", "")
      |> String.trim()
      |> handle_eq_line(tweet)
    end)
    |> Enum.reject(&is_nil/1)
    |> create_alert(tweet.id_str, @pso2_eq_alert_type)
  end

  defp handle_eq_line(line, tweet) do
    cond do
      String.match?(line, @in_progress_pattern) -> process_in_progress_eq(line, tweet.created_at)
      String.match?(line, @upcoming_pattern) -> process_upcoming_eq(line, tweet.created_at)
      true -> nil
    end
  end

  def process_upcoming_eq(line, date) do
    [_, hour, name] = @upcoming_pattern |> Regex.run(line)

    hour =
      if hour == "00" do
        "24"
      else
        hour
      end

    tweet_creation_time =
      date
      |> Timex.parse!("%a %b %d %T %z %Y", :strftime)

    jp_date =
      tweet_creation_time
      |> Timex.Timezone.convert("Asia/Tokyo")

    hours_to_add =
      jp_date
      |> Map.fetch!(:hour)
      |> Kernel.-(String.to_integer(hour))
      |> Timex.Duration.from_hours()

    is_next_day = String.to_integer(hour) < Map.fetch!(jp_date, :hour)

    eq_date =
      if is_next_day do
        jp_date
        |> Timex.add(Timex.Duration.from_days(1))
        |> Timex.subtract(hours_to_add)
      else
        jp_date
        |> Timex.add(hours_to_add)
      end

    difference_granularity =
      if Timex.diff(eq_date, jp_date, :hours) != 0 do
        :hours
      else
        :minutes
      end

    difference = Timex.diff(eq_date, jp_date, difference_granularity) |> abs()

    %{
      # Remove [Notice]
      name:
        name
        |> String.replace("[予告\]", "")
        |> String.replace(" #PSO2", "")
        |> Admin.Alerts.EQTranslations.get_english_name(),
      inProgress: false,
      date: %{
        JP: eq_date |> Timex.to_unix(),
        UTC: eq_date |> Timex.Timezone.convert("Etc/UTC") |> Timex.to_unix(),
        difference: "In #{difference} #{difference_granularity |> Atom.to_string()}"
      }
    }
  end

  def process_in_progress_eq(line, date) do
    [full_line, hour, name] = @in_progress_pattern |> Regex.run(line)

    tweet_creation_time =
      date
      |> Timex.parse!("%a %b %d %T %z %Y", :strftime)

    %{
      # Remove [Notice]
      name: name |> String.replace("[予告\]", "") |> Admin.Alerts.EQTranslations.get_english_name(),
      inProgress: true,
      date: %{
        JP:
          tweet_creation_time
          |> Timex.Timezone.convert("Asia/Tokyo")
          |> Timex.to_unix(),
        UTC: tweet_creation_time |> Timex.to_unix(),
        difference: 0
      }
    }
  end
end
