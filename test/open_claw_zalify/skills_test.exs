defmodule OpenClawZalify.SkillsTest do
  use ExUnit.Case, async: false

  alias OpenClawZalify.Agents.AgentRecord
  alias OpenClawZalify.Skills

  defmodule FakeSpacesService do
    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
    end

    def start_link(_opts) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def reset!, do: Agent.update(__MODULE__, fn _state -> %{} end)

    def put_space(workspace_id, workspace_path) do
      Agent.update(__MODULE__, fn state ->
        Map.put(state, workspace_id, %{id: workspace_id, workspace_path: workspace_path})
      end)
    end

    def get_space(workspace_id) do
      {:ok, Agent.get(__MODULE__, &Map.get(&1, workspace_id))}
    end
  end

  defmodule FakeAgentsService do
    def child_spec(_opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
    end

    def start_link(_opts) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def reset!, do: Agent.update(__MODULE__, fn _state -> %{} end)

    def put_workspace(workspace_id, workspace_path) do
      Agent.update(__MODULE__, fn state ->
        Map.put(state, workspace_id, %AgentRecord{
          workspace_id: workspace_id,
          agent_id: "agent-#{workspace_id}",
          status: "active",
          runtime_mode: "shared",
          workspace_path: workspace_path
        })
      end)
    end

    def get_workspace_agent(workspace_id) do
      {:ok, Agent.get(__MODULE__, &Map.get(&1, workspace_id))}
    end
  end

  defmodule FakeRunner do
    @behaviour OpenClawZalify.Skills.Runner

    @impl true
    def search_skills(query, _opts) do
      normalized_query = String.trim(query)

      {:ok,
       [
         %{
           slug: "#{normalized_query}-calendar",
           name: "#{String.capitalize(normalized_query)} Calendar",
           score: 3.9,
           summary: "Skill for #{normalized_query} planning",
           latest_version: "1.4.0",
           installs: 42,
           downloads: 128,
           stars: 7,
           owner_handle: "clawhub",
           owner_name: "ClawHub",
           source: "clawhub"
         }
       ]}
    end

    @impl true
    def inspect_skill("missing-skill", _opts) do
      {:error, {:command_failed, "Skill not found"}}
    end

    def inspect_skill(slug, _opts) do
      {:ok,
       %{
         slug: slug,
         name: String.capitalize(slug),
         score: nil,
         summary: "Skill for #{slug}",
         latest_version: "2.0.0",
         installs: 99,
         downloads: 256,
         stars: 11,
         owner_handle: "clawhub",
         owner_name: "ClawHub",
         source: "clawhub"
       }}
    end

    @impl true
    def install_skill(workspace_path, slug, opts) do
      version = Keyword.get(opts, :version) || "1.0.0"
      create_skill(workspace_path, slug, version)
    end

    @impl true
    def update_skill(workspace_path, slug, opts) do
      version = Keyword.get(opts, :version) || "1.0.1"

      if File.exists?(skill_md_path(workspace_path, slug)) do
        create_skill(workspace_path, slug, version)
      else
        {:error, {:command_failed, "Skill #{slug} is not installed"}}
      end
    end

    @impl true
    def uninstall_skill(workspace_path, slug) do
      case File.rm_rf(Path.join(skills_root(workspace_path), slug)) do
        {:ok, _paths} ->
          update_lockfile(workspace_path, slug, nil)
          {:ok, %{slug: slug}}

        {:error, reason, _path} ->
          {:error, reason}
      end
    end

    defp create_skill(workspace_path, slug, version) do
      skill_root = Path.join(skills_root(workspace_path), slug)
      File.mkdir_p!(skill_root)
      File.write!(skill_md_path(workspace_path, slug), skill_md(slug, version))
      update_lockfile(workspace_path, slug, version)
      {:ok, %{slug: slug, version: version}}
    end

    defp update_lockfile(workspace_path, slug, version) do
      lock_dir = Path.join(workspace_path, ".clawhub")
      lock_path = Path.join(lock_dir, "lock.json")
      File.mkdir_p!(lock_dir)

      entries =
        case File.read(lock_path) do
          {:ok, content} ->
            case Jason.decode(content) do
              {:ok, %{"entries" => payload}} when is_map(payload) -> payload
              _ -> %{}
            end

          _ ->
            %{}
        end

      next_entries =
        if version do
          Map.put(entries, slug, %{
            "slug" => slug,
            "name" => "#{slug}-name",
            "version" => version
          })
        else
          Map.delete(entries, slug)
        end

      File.write!(lock_path, Jason.encode!(%{"entries" => next_entries}))
    end

    defp skill_md(slug, version) do
      """
      ---
      name: #{slug}-name
      description: Skill for #{slug}
      version: #{version}
      ---

      # #{slug}
      """
    end

    defp skills_root(workspace_path), do: Path.join(workspace_path, "skills")

    defp skill_md_path(workspace_path, slug),
      do: Path.join([skills_root(workspace_path), slug, "SKILL.md"])
  end

  setup do
    start_supervised!(FakeSpacesService)
    start_supervised!(FakeAgentsService)

    FakeSpacesService.reset!()
    FakeAgentsService.reset!()

    original_spaces = Application.get_env(:openclaw_zalify, :spaces_service)
    original_agents = Application.get_env(:openclaw_zalify, :agents_service)
    original_runner = Application.get_env(:openclaw_zalify, :skills_runner)

    Application.put_env(:openclaw_zalify, :spaces_service, FakeSpacesService)
    Application.put_env(:openclaw_zalify, :agents_service, FakeAgentsService)
    Application.put_env(:openclaw_zalify, :skills_runner, FakeRunner)

    on_exit(fn ->
      Application.put_env(:openclaw_zalify, :spaces_service, original_spaces)
      Application.put_env(:openclaw_zalify, :agents_service, original_agents)
      Application.put_env(:openclaw_zalify, :skills_runner, original_runner)
    end)

    :ok
  end

  test "list_workspace_skills returns an empty list for a new workspace" do
    workspace_id = "space-empty"
    workspace_path = tmp_workspace_path("empty")
    FakeSpacesService.put_space(workspace_id, workspace_path)

    assert {:ok, []} = Skills.list_workspace_skills(workspace_id)
  end

  test "search_market_skills returns normalized market results" do
    assert {:ok, [skill]} = Skills.search_market_skills(" weather ")
    assert skill.slug == "weather-calendar"
    assert skill.name == "Weather Calendar"
    assert skill.summary == "Skill for weather planning"
    assert skill.installs == 42
  end

  test "inspect_market_skill returns detailed skill metadata" do
    assert {:ok, skill} = Skills.inspect_market_skill("calendar")
    assert skill.slug == "calendar"
    assert skill.latest_version == "2.0.0"
    assert skill.owner_handle == "clawhub"
  end

  test "inspect_market_skill maps missing clawhub skills to not_found" do
    assert {:error, :not_found} = Skills.inspect_market_skill("missing-skill")
  end

  test "install_workspace_skill installs a skill into the workspace" do
    workspace_id = "space-install"
    workspace_path = tmp_workspace_path("install")
    FakeSpacesService.put_space(workspace_id, workspace_path)

    assert {:ok, skill} = Skills.install_workspace_skill(workspace_id, "calendar")
    assert skill.slug == "calendar"
    assert skill.name == "calendar-name"
    assert skill.version == "1.0.0"
    assert skill.source == "clawhub"

    assert {:ok, skills} = Skills.list_workspace_skills(workspace_id)
    assert Enum.map(skills, & &1.slug) == ["calendar"]
  end

  test "install_workspace_skill validates duplicate installs" do
    workspace_id = "space-duplicate"
    workspace_path = tmp_workspace_path("duplicate")
    FakeSpacesService.put_space(workspace_id, workspace_path)

    assert {:ok, _skill} = Skills.install_workspace_skill(workspace_id, "calendar")

    assert {:error, {:validation, %{slug: ["already installed"]}}} =
             Skills.install_workspace_skill(workspace_id, "calendar")
  end

  test "update_workspace_skill refreshes the stored version" do
    workspace_id = "space-update"
    workspace_path = tmp_workspace_path("update")
    FakeSpacesService.put_space(workspace_id, workspace_path)

    assert {:ok, _skill} = Skills.install_workspace_skill(workspace_id, "calendar")

    assert {:ok, skill} =
             Skills.update_workspace_skill(workspace_id, "calendar", version: "2.0.0")

    assert skill.version == "2.0.0"
  end

  test "uninstall_workspace_skill removes the skill from the workspace" do
    workspace_id = "space-uninstall"
    workspace_path = tmp_workspace_path("uninstall")
    FakeSpacesService.put_space(workspace_id, workspace_path)

    assert {:ok, _skill} = Skills.install_workspace_skill(workspace_id, "calendar")
    assert {:ok, %{slug: "calendar"}} = Skills.uninstall_workspace_skill(workspace_id, "calendar")
    assert {:ok, []} = Skills.list_workspace_skills(workspace_id)
  end

  test "falls back to workspace path from the agent record when the space service has none" do
    workspace_id = "space-agent-fallback"
    workspace_path = tmp_workspace_path("fallback")
    FakeAgentsService.put_workspace(workspace_id, workspace_path)

    assert {:ok, skill} = Skills.install_workspace_skill(workspace_id, "weather")
    assert skill.slug == "weather"
    assert File.exists?(Path.join([workspace_path, "skills", "weather", "SKILL.md"]))
  end

  defp tmp_workspace_path(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "clawengine-skills-#{label}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf(path)
    path
  end
end
