defmodule OpenClawZalify.Skills.ClawHubRunner do
  @moduledoc false

  @behaviour OpenClawZalify.Skills.Runner

  @impl true
  def install_skill(workspace_path, slug, opts)
      when is_binary(workspace_path) and is_binary(slug) do
    args =
      ["install", slug] ++
        version_args(opts) ++
        []

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

  defp run(workspace_path, args) do
    with :ok <- File.mkdir_p(workspace_path),
         {command, command_args} <- command_parts(args) do
      do_run(workspace_path, command, command_args)
    end
  end

  defp do_run(workspace_path, command, command_args) do
    try do
      {output, exit_status} =
        System.cmd(command, command_args,
          cd: workspace_path,
          env: [
            {"CI", "1"},
            {"CLAWHUB_DISABLE_TELEMETRY", "1"},
            {"CLAWHUB_WORKDIR", workspace_path}
          ],
          stderr_to_stdout: true
        )

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
    Application.get_env(
      :openclaw_zalify,
      __MODULE__,
      []
    )
    |> Keyword.get(:command_prefix, ["pnpm", "dlx", "clawhub"])
  end

  defp version_args(opts) do
    case Keyword.get(opts, :version) do
      version when is_binary(version) and version != "" -> ["--version", version]
      _other -> []
    end
  end

  defp format_command_error(command, args, output) do
    command_line = Enum.join([command | args], " ")
    details = output |> String.trim() |> fallback_error_text()
    "#{command_line} failed: #{details}"
  end

  defp fallback_error_text(""), do: "unknown error"
  defp fallback_error_text(text), do: text
end
