defmodule EmporiumEnvironment.Horde do
  @moduledoc """
  Convenience module to look up or start a named GenServer within
  the target Horde, for inclusion in Horde-using applications.

  By convention, each OTP application using Horde Supervisor / Registry
  modules will hang them under their own namespace such as…

  - EmporiumAccess.Horde.Registry
  - EmporiumAccess.Horde.Supervisor

  …and this convention is respected when spawning servers.
  """

  @callback registry_module :: module()
  @callback registry_key(term()) :: term()

  defmacro __using__(options) do
    {:ok, namespace} = Keyword.fetch(options, :namespace)
    namespace = Macro.expand(namespace, __CALLER__)
    supervisor = Module.concat(namespace, Horde.Supervisor)
    registry = Module.concat(namespace, Horde.Registry)

    quote bind_quoted: [parent: __MODULE__, supervisor: supervisor, registry: registry] do
      def ensure_started(id) do
        unquote(parent).ensure_started(unquote(supervisor), __MODULE__, id)
      end

      def child_spec(term) do
        %{start: {__MODULE__, :start_link, [term]}, restart: :transient}
      end

      @behaviour parent
      @before_compile {parent, :__build_start_link__}

      @impl parent
      def registry_module, do: unquote(registry)

      @impl parent
      def registry_key(term), do: term

      defoverridable parent
    end
  end

  defmacro __build_start_link__(env) do
    unless Module.defines?(env.module, {:start_link, 1}) do
      behaviours = Module.get_attribute(env.module, :behaviour)

      if Enum.member?(behaviours, GenServer) do
        quote do
          def start_link(term) do
            name = {:via, Horde.Registry, {registry_module(), registry_key(term)}}
            GenServer.start_link(__MODULE__, term, name: name)
          end
        end
      else
        reason = "required by behaviour EmporiumEnvironment.Horde"

        raise UndefinedFunctionError,
          module: env.module,
          function: :start_link,
          arity: 1,
          message: "heh",
          reason: reason
      end
    end
  end

  def ensure_started(supervisor, module, term) do
    answer = lookup(module, term) || start(supervisor, module, term)

    case answer do
      pid when is_pid(pid) -> {:ok, pid}
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, {:shutdown, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lookup(module, term) do
    registry = module.registry_module()
    key = module.registry_key(term)

    case Horde.Registry.lookup(registry, key) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end

  defp start(supervisor, module, term) do
    Horde.DynamicSupervisor.start_child(supervisor, {module, term})
  end
end
