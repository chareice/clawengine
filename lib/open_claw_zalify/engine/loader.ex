defmodule OpenClawZalify.Engine.Loader do
  @moduledoc """
  Loads the self-hosted engine config directory into an in-memory snapshot.
  """

  alias OpenClawZalify.Config
  alias OpenClawZalify.Engine.Instance
  alias OpenClawZalify.Engine.ModelProfile
  alias OpenClawZalify.Engine.Space
  alias OpenClawZalify.Engine.Snapshot
  alias OpenClawZalify.Engine.TemplateRenderer

  @default_agent_name_template "{{instance.id}}-{{space.slug}}"
  @default_workspace_path_template "{{openclaw.workspace_root}}/{{instance.id}}/{{space.slug}}"

  @spec load(String.t()) :: {:ok, Snapshot.t()} | {:error, term()}
  def load(root) when is_binary(root) do
    root = Path.expand(root)

    with :ok <- ensure_directory(root),
         {:ok, instance_attrs} <- read_yaml(Path.join(root, "instance.yaml")),
         {:ok, model_profiles} <- load_model_profiles(root),
         {:ok, spaces} <- load_spaces(root, build_instance(instance_attrs, root), model_profiles) do
      instance = build_instance(instance_attrs, root)

      {:ok,
       %Snapshot{
         config_root: root,
         instance: instance,
         spaces: spaces,
         model_profiles: model_profiles,
         loaded_at: DateTime.utc_now()
       }}
    end
  end

  defp ensure_directory(path) do
    if File.dir?(path), do: :ok, else: {:error, {:config_root_not_found, path}}
  end

  defp build_instance(attrs, root) do
    defaults = fetch_map(attrs, "defaults")
    agent = fetch_map(attrs, "agent")

    %Instance{
      id: text_value(attrs, "id") || Path.basename(root),
      name: text_value(attrs, "name") || "Business Instance",
      agent_name_template: text_value(agent, "name_template") || @default_agent_name_template,
      workspace_path_template:
        text_value(agent, "workspace_path_template") || @default_workspace_path_template,
      default_template_set: text_value(defaults, "template_set"),
      default_model_profile_id: text_value(defaults, "model_profile"),
      default_tool_profile_id: text_value(defaults, "tool_profile"),
      default_memory_enabled: boolean_value(defaults, "memory_enabled", true),
      config_root: root
    }
  end

  defp load_model_profiles(root) do
    root
    |> Path.join("models")
    |> yaml_files()
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, acc} ->
      case read_yaml(path) do
        {:ok, attrs} ->
          profile = build_model_profile(attrs, path)
          {:cont, {:ok, Map.put(acc, profile.id, profile)}}

        {:error, reason} ->
          {:halt, {:error, {:invalid_model_profile, path, reason}}}
      end
    end)
  end

  defp build_model_profile(attrs, path) do
    %ModelProfile{
      id: text_value(attrs, "id") || basename_without_ext(path),
      label: text_value(attrs, "label"),
      model_ref: text_value(attrs, "model_ref"),
      reasoning_level: text_value(attrs, "reasoning_level"),
      timeout_ms: positive_integer_value(attrs, "timeout_ms"),
      raw: attrs
    }
  end

  defp load_spaces(root, %Instance{} = instance, model_profiles) do
    root
    |> Path.join("spaces")
    |> yaml_files()
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, acc} ->
      case read_yaml(path) do
        {:ok, attrs} ->
          space = build_space(attrs, path, root, instance, model_profiles)
          {:cont, {:ok, Map.put(acc, space.id, space)}}

        {:error, reason} ->
          {:halt, {:error, {:invalid_space_config, path, reason}}}
      end
    end)
  end

  defp build_space(attrs, path, root, %Instance{} = instance, model_profiles) do
    agent = fetch_map(attrs, "agent")
    variables = fetch_map(attrs, "variables")

    id = text_value(attrs, "id") || basename_without_ext(path)
    name = text_value(attrs, "name") || id
    slug = normalize_identifier(text_value(attrs, "slug") || name, "space")
    model_profile_id = text_value(agent, "model_profile") || instance.default_model_profile_id
    model_profile = model_profiles[model_profile_id]
    template_set = text_value(agent, "template_set") || instance.default_template_set
    tool_profile_id = text_value(agent, "tool_profile") || instance.default_tool_profile_id
    memory_enabled = boolean_value(agent, "memory_enabled", instance.default_memory_enabled)

    context = %{
      "instance" => %{"id" => instance.id, "name" => instance.name},
      "space" => %{
        "id" => id,
        "name" => name,
        "slug" => slug,
        "display_name" => text_value(agent, "display_name") || "#{name} Assistant"
      },
      "model" => %{
        "profile_id" => model_profile_id,
        "model_ref" => model_profile && model_profile.model_ref
      },
      "vars" => variables,
      "openclaw" => %{"workspace_root" => Config.openclaw_workspace_root()}
    }

    identity_md =
      text_value(fetch_map(attrs, "templates"), "identity_md") ||
        render_template_file(root, template_set, "IDENTITY.md", context, fn ->
          """
          # Identity

          - Instance: #{instance.name}
          - Space ID: #{id}
          - Space Name: #{name}
          - Display Name: #{context["space"]["display_name"]}
          """
        end)

    soul_md =
      text_value(fetch_map(attrs, "templates"), "soul_md") ||
        render_template_file(root, template_set, "SOUL.md", context, fn ->
          """
          # Soul

          You are the AI operator for #{name}.
          Keep answers concise, operational, and grounded in business tools.
          """
        end)

    user_md =
      text_value(fetch_map(attrs, "templates"), "user_md") ||
        render_template_file(root, template_set, "USER.md", context, fn ->
          """
          # User

          The current space is #{id}.
          Use the configured tools before making assumptions about business data.
          """
        end)

    rendered_agent_name =
      text_value(agent, "name") ||
        TemplateRenderer.render(instance.agent_name_template, context)

    rendered_workspace_path =
      text_value(agent, "workspace_path") ||
        TemplateRenderer.render(instance.workspace_path_template, context)

    %Space{
      id: id,
      name: name,
      slug: slug,
      display_name: context["space"]["display_name"],
      agent_name: normalize_identifier(rendered_agent_name, slug),
      workspace_path: rendered_workspace_path,
      template_set: template_set,
      model_profile_id: model_profile_id,
      tool_profile_id: tool_profile_id,
      model_ref: text_value(agent, "model_ref") || (model_profile && model_profile.model_ref),
      reasoning_level:
        text_value(agent, "reasoning_level") || (model_profile && model_profile.reasoning_level),
      timeout_ms:
        positive_integer_value(agent, "timeout_ms") || (model_profile && model_profile.timeout_ms),
      role_prompt: text_value(agent, "role_prompt"),
      memory_enabled: memory_enabled,
      identity_md: identity_md,
      soul_md: soul_md,
      user_md: user_md,
      variables: variables,
      raw: attrs
    }
  end

  defp render_template_file(_root, nil, _filename, context, fallback_fun) do
    fallback_fun.() |> TemplateRenderer.render(context)
  end

  defp render_template_file(root, template_set, filename, context, fallback_fun) do
    template_dir = Path.join([root, "templates", template_set])

    content =
      [filename, String.downcase(filename)]
      |> Enum.map(&Path.join(template_dir, &1))
      |> Enum.find_value(fn candidate ->
        case File.read(candidate) do
          {:ok, body} -> body
          {:error, _reason} -> nil
        end
      end) || fallback_fun.()

    TemplateRenderer.render(content, context)
  end

  defp yaml_files(path) do
    if File.dir?(path) do
      path
      |> File.ls!()
      |> Enum.filter(&String.match?(&1, ~r/\.(ya?ml)$/))
      |> Enum.map(&Path.join(path, &1))
      |> Enum.sort()
    else
      []
    end
  end

  defp read_yaml(path) do
    case File.exists?(path) do
      true ->
        case YamlElixir.read_from_file(path) do
          {:ok, attrs} when is_map(attrs) -> {:ok, attrs}
          {:ok, attrs} -> {:error, {:invalid_yaml, path, attrs}}
          {:error, reason} -> {:error, {:invalid_yaml, path, reason}}
        end

      false ->
        {:error, {:missing_config_file, path}}
    end
  end

  defp fetch_map(attrs, key) when is_map(attrs) do
    case Map.get(attrs, key, %{}) do
      value when is_map(value) -> value
      _other -> %{}
    end
  end

  defp text_value(attrs, key) when is_map(attrs) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _other ->
        nil
    end
  end

  defp boolean_value(attrs, key, fallback) when is_map(attrs) do
    case Map.get(attrs, key) do
      value when is_boolean(value) -> value
      _other -> fallback
    end
  end

  defp positive_integer_value(attrs, key) when is_map(attrs) do
    case Map.get(attrs, key) do
      value when is_integer(value) and value > 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {parsed, ""} when parsed > 0 -> parsed
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp basename_without_ext(path) do
    path
    |> Path.basename()
    |> Path.rootname()
  end

  defp normalize_identifier(value, fallback) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> fallback
      normalized -> normalized
    end
  end
end
