defmodule ClawEngine.Skills.ClawHubRunner do
  @moduledoc false

  @behaviour ClawEngine.Skills.Runner

  @impl true
  def search_skills(query, opts) when is_binary(query) do
    args = ["search", query, "--limit", Integer.to_string(search_limit(opts))]

    with {:ok, %{output: output}} <- run_global(args) do
      {:ok, parse_search_output(output)}
    end
  end

  @impl true
  def inspect_skill(slug, opts) when is_binary(slug) do
    args =
      ["inspect", slug, "--json"] ++
        inspect_version_args(opts) ++
        inspect_tag_args(opts)

    with {:ok, %{output: output}} <- run_global(args),
         {:ok, payload} <- Jason.decode(output) do
      {:ok, parse_inspect_payload(payload)}
    else
      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, {:command_failed, "Failed to decode clawhub inspect response"}}
    end
  end

  @impl true
  def install_skill(workspace_path, slug, opts)
      when is_binary(workspace_path) and is_binary(slug) do
    args =
      ["install", slug] ++
        version_args(opts)

    run(workspace_path, args)
  end

  @impl true
  def update_skill(workspace_path, slug, opts)
      when is_binary(workspace_path) and is_binary(slug) do
    args =
      ["update", slug] ++
        version_args(opts) ++
        ["--force"]

    run(workspace_path, args)
  end

  @impl true
  def uninstall_skill(workspace_path, slug) when is_binary(workspace_path) and is_binary(slug) do
    run(workspace_path, ["uninstall", slug, "--yes"])
  end

  defp run_global(args) do
    do_run(nil, args)
  end

  defp run(workspace_path, args) do
    with :ok <- File.mkdir_p(workspace_path) do
      do_run(workspace_path, args)
    end
  end

  defp do_run(workspace_path, args) do
    {command, command_args} = command_parts(args)
    options = system_cmd_options(workspace_path)

    try do
      {output, exit_status} = System.cmd(command, command_args, options)

      case exit_status do
        0 ->
          {:ok, %{output: String.trim(output)}}

        _other ->
          {:error, {:command_failed, format_command_error(command, command_args, output)}}
      end
    rescue
      error in ErlangError ->
        {:error, {:command_failed, Exception.message(error)}}
    end
  end

  defp command_parts(args) do
    case command_prefix() do
      [command | prefix_args] when is_binary(command) ->
        {command, prefix_args ++ args}

      _other ->
        {"pnpm", ["dlx", "clawhub" | args]}
    end
  end

  defp command_prefix do
    Application.get_env(:claw_engine, __MODULE__, [])
    |> Keyword.get(:command_prefix, ["pnpm", "dlx", "clawhub"])
  end

  defp command_env(workspace_path) do
    base = [
      {"CI", "1"},
      {"CLAWHUB_DISABLE_TELEMETRY", "1"}
    ]

    if is_binary(workspace_path) and workspace_path != "" do
      base ++ [{"CLAWHUB_WORKDIR", workspace_path}]
    else
      base
    end
  end

  defp system_cmd_options(workspace_path)
       when is_binary(workspace_path) and workspace_path != "" do
    [
      cd: workspace_path,
      env: command_env(workspace_path),
      stderr_to_stdout: true
    ]
  end

  defp system_cmd_options(_workspace_path) do
    [
      env: command_env(nil),
      stderr_to_stdout: true
    ]
  end

  defp version_args(opts) do
    case Keyword.get(opts, :version) do
      version when is_binary(version) and version != "" -> ["--version", version]
      _other -> []
    end
  end

  defp inspect_version_args(opts) do
    case Keyword.get(opts, :version) do
      version when is_binary(version) and version != "" -> ["--version", version]
      _other -> []
    end
  end

  defp inspect_tag_args(opts) do
    case Keyword.get(opts, :tag) do
      tag when is_binary(tag) and tag != "" -> ["--tag", tag]
      _other -> []
    end
  end

  defp search_limit(opts) do
    case Keyword.get(opts, :limit) do
      value when is_integer(value) and value > 0 -> min(value, 20)
      _other -> 8
    end
  end

  defp parse_search_output(output) when is_binary(output) do
    output
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.reject(&String.starts_with?(&1, "- "))
    |> Enum.map(&parse_search_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_search_line(line) do
    case Regex.named_captures(
           ~r/^(?<slug>\S+)\s{2,}(?<name>.+?)\s{2,}\((?<score>[\d.]+)\)$/,
           line
         ) do
      %{"name" => name, "score" => score, "slug" => slug} ->
        %{
          slug: slug,
          name: name,
          score: parse_score(score),
          summary: nil,
          latest_version: nil,
          installs: nil,
          downloads: nil,
          stars: nil,
          owner_handle: nil,
          owner_name: nil,
          source: "clawhub"
        }

      _other ->
        nil
    end
  end

  defp parse_score(value) do
    case Float.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_inspect_payload(%{"skill" => skill} = payload) when is_map(skill) do
    stats = Map.get(skill, "stats", %{})
    owner = Map.get(payload, "owner", %{})
    latest = Map.get(payload, "latestVersion", %{})

    %{
      slug: map_text(skill, "slug") || "unknown",
      name: map_text(skill, "displayName") || map_text(skill, "slug") || "Unknown",
      score: nil,
      summary: map_text(skill, "summary"),
      latest_version:
        map_text(latest, "version") ||
          map_text(skill, "latestVersion") ||
          latest_tag(skill),
      installs: map_integer(stats, "installsCurrent"),
      downloads: map_integer(stats, "downloads"),
      stars: map_integer(stats, "stars"),
      owner_handle: map_text(owner, "handle"),
      owner_name: map_text(owner, "displayName"),
      source: "clawhub"
    }
  end

  defp parse_inspect_payload(_payload) do
    %{
      slug: "unknown",
      name: "Unknown",
      score: nil,
      summary: nil,
      latest_version: nil,
      installs: nil,
      downloads: nil,
      stars: nil,
      owner_handle: nil,
      owner_name: nil,
      source: "clawhub"
    }
  end

  defp latest_tag(skill) when is_map(skill) do
    skill
    |> Map.get("tags", %{})
    |> map_text("latest")
  end

  defp latest_tag(_skill), do: nil

  defp map_text(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp map_text(_map, _key), do: nil

  defp map_integer(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_integer(value) and value >= 0 -> value
      _ -> nil
    end
  end

  defp map_integer(_map, _key), do: nil

  defp format_command_error(command, args, output) do
    command_line = Enum.join([command | args], " ")
    details = output |> String.trim() |> fallback_error_text()
    "#{command_line} failed: #{details}"
  end

  defp fallback_error_text(""), do: "unknown error"
  defp fallback_error_text(text), do: text
end
