defmodule OpenClawZalify.Skills do
  @moduledoc """
  Workspace skill management backed by ClawHub-compatible skill folders.
  """

  alias OpenClawZalify.Agents

  @type skill_entry :: %{
          slug: String.t(),
          name: String.t(),
          description: String.t() | nil,
          version: String.t() | nil,
          source: String.t()
        }

  @spec list_workspace_skills(String.t()) :: {:ok, [skill_entry()]} | {:error, term()}
  def list_workspace_skills(workspace_id) when is_binary(workspace_id) do
    with {:ok, workspace_path} <- ensure_workspace_ready(workspace_id) do
      {:ok, do_list_workspace_skills(workspace_path)}
    end
  end

  @spec install_workspace_skill(String.t(), String.t(), map() | keyword()) ::
          {:ok, skill_entry()} | {:error, term()}
  def install_workspace_skill(workspace_id, slug, opts \\ [])
      when is_binary(workspace_id) and is_binary(slug) and (is_map(opts) or is_list(opts)) do
    with {:ok, normalized_slug} <- required_slug(slug),
         {:ok, workspace_path} <- ensure_workspace_ready(workspace_id),
         :ok <- ensure_skill_not_installed(workspace_path, normalized_slug),
         {:ok, _result} <-
           runner().install_skill(
             workspace_path,
             normalized_slug,
             version: option_text(opts, :version)
           ),
         {:ok, skill} <- fetch_workspace_skill(workspace_path, normalized_slug) do
      {:ok, skill}
    end
  end

  @spec update_workspace_skill(String.t(), String.t(), map() | keyword()) ::
          {:ok, skill_entry()} | {:error, term()}
  def update_workspace_skill(workspace_id, slug, opts \\ [])
      when is_binary(workspace_id) and is_binary(slug) and (is_map(opts) or is_list(opts)) do
    with {:ok, normalized_slug} <- required_slug(slug),
         {:ok, workspace_path} <- ensure_workspace_ready(workspace_id),
         {:ok, _existing} <- fetch_workspace_skill(workspace_path, normalized_slug),
         {:ok, _result} <-
           runner().update_skill(
             workspace_path,
             normalized_slug,
             version: option_text(opts, :version)
           ),
         {:ok, skill} <- fetch_workspace_skill(workspace_path, normalized_slug) do
      {:ok, skill}
    end
  end

  @spec uninstall_workspace_skill(String.t(), String.t()) ::
          {:ok, %{slug: String.t()}} | {:error, term()}
  def uninstall_workspace_skill(workspace_id, slug)
      when is_binary(workspace_id) and is_binary(slug) do
    with {:ok, normalized_slug} <- required_slug(slug),
         {:ok, workspace_path} <- ensure_workspace_ready(workspace_id),
         {:ok, _existing} <- fetch_workspace_skill(workspace_path, normalized_slug),
         {:ok, _result} <- runner().uninstall_skill(workspace_path, normalized_slug) do
      {:ok, %{slug: normalized_slug}}
    end
  end

  defp ensure_workspace_ready(workspace_id) do
    with {:ok, workspace_path} <- resolve_workspace_path(workspace_id),
         :ok <- File.mkdir_p(workspace_path),
         :ok <- File.mkdir_p(skills_root(workspace_path)) do
      {:ok, workspace_path}
    end
  end

  defp resolve_workspace_path(workspace_id) do
    workspace_id = String.trim(workspace_id)

    case resolve_workspace_path_from_space(workspace_id) do
      {:ok, workspace_path} ->
        {:ok, workspace_path}

      {:error, _reason} ->
        resolve_workspace_path_from_agent(workspace_id)
    end
  end

  defp resolve_workspace_path_from_space(workspace_id) do
    spaces_service = spaces_service()

    if function_exported?(spaces_service, :get_space, 1) do
      case spaces_service.get_space(workspace_id) do
        {:ok, %{workspace_path: workspace_path}} when is_binary(workspace_path) ->
          {:ok, workspace_path}

        {:ok, nil} ->
          {:error, {:not_found, :workspace}}

        {:ok, _space_without_path} ->
          {:error, {:not_found, :workspace}}

        {:error, :not_found} ->
          {:error, {:not_found, :workspace}}

        {:error, {:not_found, _type}} = error ->
          error

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:not_found, :workspace}}
    end
  end

  defp resolve_workspace_path_from_agent(workspace_id) do
    case agents_service().get_workspace_agent(workspace_id) do
      {:ok, %{workspace_path: workspace_path}} when is_binary(workspace_path) ->
        {:ok, workspace_path}

      {:ok, nil} ->
        {:error, {:not_found, :workspace}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_skill_not_installed(workspace_path, slug) do
    case fetch_workspace_skill(workspace_path, slug) do
      {:ok, _skill} -> {:error, {:validation, %{slug: ["already installed"]}}}
      {:error, :not_found} -> :ok
    end
  end

  defp fetch_workspace_skill(workspace_path, slug) do
    workspace_path
    |> do_list_workspace_skills()
    |> Enum.find(&(&1.slug == slug))
    |> case do
      nil -> {:error, :not_found}
      skill -> {:ok, skill}
    end
  end

  defp do_list_workspace_skills(workspace_path) do
    lock_index = read_lock_index(workspace_path)

    workspace_path
    |> skills_root()
    |> Path.join("*/SKILL.md")
    |> Path.wildcard()
    |> Enum.map(&skill_from_path(&1, lock_index))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  defp skill_from_path(skill_md_path, lock_index) do
    slug =
      skill_md_path
      |> Path.dirname()
      |> Path.basename()

    with {:ok, content} <- File.read(skill_md_path) do
      frontmatter = parse_frontmatter(content)
      lock_entry = Map.get(lock_index, slug, %{})

      %{
        slug: slug,
        name: map_text(frontmatter, "name") || map_text(lock_entry, "name") || slug,
        description: map_text(frontmatter, "description") || map_text(lock_entry, "description"),
        version:
          map_text(lock_entry, "version") ||
            nested_text(lock_entry, ["manifest", "version"]) ||
            map_text(frontmatter, "version"),
        source: if(map_size(lock_entry) > 0, do: "clawhub", else: "workspace")
      }
    else
      _ -> nil
    end
  end

  defp read_lock_index(workspace_path) do
    lock_path = Path.join([workspace_path, ".clawhub", "lock.json"])

    with {:ok, content} <- File.read(lock_path),
         {:ok, payload} <- Jason.decode(content) do
      extract_lock_entries(payload)
    else
      _ -> %{}
    end
  end

  defp extract_lock_entries(%{"entries" => entries}) when is_map(entries), do: entries

  defp extract_lock_entries(%{"entries" => entries}) when is_list(entries) do
    Enum.reduce(entries, %{}, &put_lock_entry/2)
  end

  defp extract_lock_entries(%{"skills" => entries}) when is_map(entries), do: entries

  defp extract_lock_entries(%{"skills" => entries}) when is_list(entries) do
    Enum.reduce(entries, %{}, &put_lock_entry/2)
  end

  defp extract_lock_entries(entries) when is_list(entries) do
    Enum.reduce(entries, %{}, &put_lock_entry/2)
  end

  defp extract_lock_entries(_payload), do: %{}

  defp put_lock_entry(entry, acc) when is_map(entry) do
    case map_text(entry, "slug") || map_text(entry, "name") do
      nil -> acc
      slug -> Map.put(acc, slug, entry)
    end
  end

  defp put_lock_entry(_entry, acc), do: acc

  defp parse_frontmatter(content) when is_binary(content) do
    case Regex.run(~r/\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)/s, content, capture: :all_but_first) do
      [frontmatter] ->
        frontmatter
        |> String.split(~r/\r?\n/, trim: true)
        |> Enum.reduce(%{}, fn line, acc ->
          case String.split(line, ":", parts: 2) do
            [key, value] ->
              key = String.trim(key)

              if key == "" do
                acc
              else
                Map.put(acc, key, strip_quotes(value))
              end

            _other ->
              acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp parse_frontmatter(_content), do: %{}

  defp strip_quotes(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
    |> String.trim_leading("'")
    |> String.trim_trailing("'")
  end

  defp required_slug(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, {:validation, %{slug: ["can't be blank"]}}}
      slug -> {:ok, slug}
    end
  end

  defp required_slug(_value), do: {:error, {:validation, %{slug: ["can't be blank"]}}}

  defp option_text(opts, key) when is_list(opts) do
    value = Keyword.get(opts, key) || Keyword.get(opts, String.to_atom(to_string(key)))
    normalize_text(value)
  end

  defp option_text(opts, key) when is_map(opts) do
    value = Map.get(opts, key) || Map.get(opts, to_string(key))
    normalize_text(value)
  end

  defp option_text(_opts, _key), do: nil

  defp map_text(map, key) when is_map(map) do
    normalize_text(Map.get(map, key))
  end

  defp map_text(_map, _key), do: nil

  defp nested_text(map, [key | rest]) when is_map(map) do
    case Map.get(map, key) do
      value when rest == [] -> normalize_text(value)
      value when is_map(value) -> nested_text(value, rest)
      _other -> nil
    end
  end

  defp nested_text(_map, _path), do: nil

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_text(nil), do: nil

  defp normalize_text(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_text()

  defp normalize_text(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_text(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 1)
  defp normalize_text(_value), do: nil

  defp skills_root(workspace_path) do
    Path.join(workspace_path, "skills")
  end

  defp agents_service do
    Application.get_env(:openclaw_zalify, :agents_service, Agents)
  end

  defp spaces_service do
    Application.get_env(:openclaw_zalify, :spaces_service, OpenClawZalify.Spaces)
  end

  defp runner do
    Application.get_env(
      :openclaw_zalify,
      :skills_runner,
      OpenClawZalify.Skills.ClawHubRunner
    )
  end
end
