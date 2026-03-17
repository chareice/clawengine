defmodule ClawEngine.Skills.ClawHubRunnerTest do
  use ExUnit.Case, async: true

  alias ClawEngine.Skills.ClawHubRunner

  test "search_skills parses slug name and score from clawhub output" do
    script_path = tmp_script_path("search")

    File.write!(
      script_path,
      """
      #!/usr/bin/env bash
      if [ "$1" = "search" ]; then
        cat <<'EOF'
      - Searching
      weather  Weather  (3.861)
      google-weather  Google Weather  (3.528)
      EOF
        exit 0
      fi

      echo "unexpected command" >&2
      exit 1
      """
    )

    File.chmod!(script_path, 0o755)

    original_config = Application.get_env(:claw_engine, ClawHubRunner, [])

    Application.put_env(:claw_engine, ClawHubRunner, command_prefix: [script_path])

    on_exit(fn ->
      Application.put_env(:claw_engine, ClawHubRunner, original_config)
      File.rm_rf(script_path)
    end)

    assert {:ok, skills} = ClawHubRunner.search_skills("weather", limit: 5)

    assert skills == [
             %{
               slug: "weather",
               name: "Weather",
               score: 3.861,
               summary: nil,
               latest_version: nil,
               installs: nil,
               downloads: nil,
               stars: nil,
               owner_handle: nil,
               owner_name: nil,
               source: "clawhub"
             },
             %{
               slug: "google-weather",
               name: "Google Weather",
               score: 3.528,
               summary: nil,
               latest_version: nil,
               installs: nil,
               downloads: nil,
               stars: nil,
               owner_handle: nil,
               owner_name: nil,
               source: "clawhub"
             }
           ]
  end

  defp tmp_script_path(label) do
    Path.join(
      System.tmp_dir!(),
      "clawengine-clawhub-runner-#{label}-#{System.unique_integer([:positive])}"
    )
  end
end
