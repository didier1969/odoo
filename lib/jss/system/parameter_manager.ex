defmodule JSS.System.ParameterManager do
  @moduledoc """
  Gestionnaire centralisé des paramètres système avec hot-reload.
  Stockage en PostgreSQL avec notification temps réel via Phoenix PubSub.
  """

  use GenServer
  require Logger

  alias JSS.Repo
  alias JSS.Schemas.SystemParameter
  alias Phoenix.PubSub

  # Configuration du GenServer
  @pubsub_topic "parameter_updates"
  @cache_refresh_interval 30_000  # 30 secondes

  defstruct [
    :cached_parameters,
    :subscribers,
    :last_cache_refresh
  ]

  # API publique

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Récupère la valeur d'un paramètre avec conversion de type automatique.
  Utilise le cache en mémoire pour les performances.
  """
  def get(category, parameter_name) when is_binary(category) and is_binary(parameter_name) do
    GenServer.call(__MODULE__, {:get_parameter, category, parameter_name})
  end

  @doc """
  Met à jour un paramètre et notifie tous les abonnés.
  Valide le type avant l'enregistrement.
  """
  def set(category, parameter_name, value) when is_binary(category) and is_binary(parameter_name) do
    GenServer.call(__MODULE__, {:set_parameter, category, parameter_name, value})
  end

  @doc """
  Récupère tous les paramètres d'une catégorie.
  """
  def get_category(category) when is_binary(category) do
    GenServer.call(__MODULE__, {:get_category, category})
  end

  @doc """
  Abonnement aux changements de paramètres pour un processus.
  Le processus recevra {:parameter_updated, category, parameter_name, new_value}
  """
  def subscribe(pid \\ self()) do
    GenServer.cast(__MODULE__, {:subscribe, pid})
  end

  @doc """
  Désabonnement aux notifications.
  """
  def unsubscribe(pid \\ self()) do
    GenServer.cast(__MODULE__, {:unsubscribe, pid})
  end

  @doc """
  Force le rechargement du cache depuis la base de données.
  """
  def refresh_cache do
    GenServer.cast(__MODULE__, :refresh_cache)
  end

  @doc """
  Initialise les paramètres par défaut depuis la configuration.
  """
  def load_defaults do
    GenServer.call(__MODULE__, :load_defaults, 10_000)
  end

  # Callbacks GenServer

  @impl true
  def init(_opts) do
    # Abonnement aux mises à jour PubSub
    PubSub.subscribe(JSS.PubSub, @pubsub_topic)

    # Planification du rafraîchissement périodique du cache
    Process.send_after(self(), :periodic_cache_refresh, @cache_refresh_interval)

    # Chargement initial du cache
    cached_params = load_parameters_from_db()

    Logger.info("ParameterManager started with #{map_size(cached_params)} parameters")

    {:ok, %__MODULE__{
      cached_parameters: cached_params,
      subscribers: MapSet.new(),
      last_cache_refresh: DateTime.utc_now()
    }}
  end

  @impl true
  def handle_call({:get_parameter, category, parameter_name}, _from, state) do
    key = "#{category}.#{parameter_name}"

    case Map.get(state.cached_parameters, key) do
      nil ->
        # Fallback vers les valeurs par défaut
        default_value = get_default_value(category, parameter_name)
        {:reply, default_value, state}

      %{value: value, data_type: data_type} ->
        converted_value = convert_value(value, data_type)
        {:reply, converted_value, state}
    end
  end

  @impl true
  def handle_call({:set_parameter, category, parameter_name, value}, _from, state) do
    case upsert_parameter(category, parameter_name, value) do
      {:ok, parameter} ->
        # Mise à jour du cache local
        key = "#{category}.#{parameter_name}"
        updated_cache = Map.put(state.cached_parameters, key, %{
          value: parameter.parameter_value,
          data_type: parameter.data_type
        })

        # Notification via PubSub
        PubSub.broadcast(JSS.PubSub, @pubsub_topic, {
          :parameter_updated,
          category,
          parameter_name,
          convert_value(parameter.parameter_value, parameter.data_type)
        })

        {:reply, :ok, %{state | cached_parameters: updated_cache}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_category, category}, _from, state) do
    category_params =
      state.cached_parameters
      |> Enum.filter(fn {key, _value} -> String.starts_with?(key, "#{category}.") end)
      |> Enum.map(fn {key, %{value: value, data_type: data_type}} ->
        parameter_name = String.replace_prefix(key, "#{category}.", "")
        {parameter_name, convert_value(value, data_type)}
      end)
      |> Map.new()

    {:reply, category_params, state}
  end

  @impl true
  def handle_call(:load_defaults, _from, state) do
    case load_default_parameters() do
      :ok ->
        # Rechargement du cache après insertion des défauts
        updated_cache = load_parameters_from_db()
        {:reply, :ok, %{state | cached_parameters: updated_cache}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:subscribe, pid}, state) do
    # Surveillance du processus pour nettoyage automatique
    Process.monitor(pid)
    updated_subscribers = MapSet.put(state.subscribers, pid)
    {:noreply, %{state | subscribers: updated_subscribers}}
  end

  @impl true
  def handle_cast({:unsubscribe, pid}, state) do
    updated_subscribers = MapSet.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: updated_subscribers}}
  end

  @impl true
  def handle_cast(:refresh_cache, state) do
    updated_cache = load_parameters_from_db()
    Logger.info("Parameter cache refreshed with #{map_size(updated_cache)} parameters")

    {:noreply, %{state |
      cached_parameters: updated_cache,
      last_cache_refresh: DateTime.utc_now()
    }}
  end

  @impl true
  def handle_info(:periodic_cache_refresh, state) do
    # Rafraîchissement périodique du cache
    send(self(), :refresh_cache)
    Process.send_after(self(), :periodic_cache_refresh, @cache_refresh_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info({:parameter_updated, category, parameter_name, new_value}, state) do
    # Notification des processus abonnés
    Enum.each(state.subscribers, fn pid ->
      send(pid, {:parameter_updated, category, parameter_name, new_value})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Nettoyage automatique des abonnés terminés
    updated_subscribers = MapSet.delete(state.subscribers, pid)
    {:noreply, %{state | subscribers: updated_subscribers}}
  end

  # Fonctions privées

  defp load_parameters_from_db do
    SystemParameter
    |> Repo.all()
    |> Enum.map(fn param ->
      key = "#{param.category}.#{param.parameter_name}"
      value = %{value: param.parameter_value, data_type: param.data_type}
      {key, value}
    end)
    |> Map.new()
  rescue
    error ->
      Logger.error("Failed to load parameters from DB: #{inspect(error)}")
      %{}
  end

  defp upsert_parameter(category, parameter_name, value) do
    # Détection automatique du type
    data_type = detect_data_type(value)
    serialized_value = serialize_value(value, data_type)

    attrs = %{
      category: category,
      parameter_name: parameter_name,
      parameter_value: serialized_value,
      data_type: data_type,
      updated_at: DateTime.utc_now()
    }

    case Repo.get_by(SystemParameter, category: category, parameter_name: parameter_name) do
      nil ->
        %SystemParameter{}
        |> SystemParameter.changeset(Map.put(attrs, :created_at, DateTime.utc_now()))
        |> Repo.insert()

      existing ->
        existing
        |> SystemParameter.changeset(attrs)
        |> Repo.update()
    end
  end

  defp detect_data_type(value) when is_integer(value), do: "integer"
  defp detect_data_type(value) when is_float(value), do: "float"
  defp detect_data_type(value) when is_boolean(value), do: "boolean"
  defp detect_data_type(value) when is_list(value), do: "list"
  defp detect_data_type(value) when is_binary(value), do: "string"
  defp detect_data_type(_), do: "string"

  defp serialize_value(value, "list"), do: Jason.encode!(value)
  defp serialize_value(value, _), do: to_string(value)

  defp convert_value(value, "integer"), do: String.to_integer(value)
  defp convert_value(value, "float"), do: String.to_float(value)
  defp convert_value("true", "boolean"), do: true
  defp convert_value("false", "boolean"), do: false
  defp convert_value(value, "boolean"), do: !!value
  defp convert_value(value, "list"), do: Jason.decode!(value)
  defp convert_value(value, "string"), do: value
  defp convert_value(value, _), do: value

  defp get_default_value(category, parameter_name) do
    defaults = Application.get_env(:jss, :default_parameters, %{})

    category_defaults = Map.get(defaults, String.to_atom(category), %{})
    Map.get(category_defaults, String.to_atom(parameter_name))
  end

  defp load_default_parameters do
    defaults = Application.get_env(:jss, :default_parameters, %{})

    Enum.each(defaults, fn {category, params} ->
      category_str = Atom.to_string(category)

      Enum.each(params, fn {param_name, value} ->
        param_name_str = Atom.to_string(param_name)

        # Vérifier si le paramètre existe déjà
        existing = Repo.get_by(SystemParameter,
          category: category_str,
          parameter_name: param_name_str
        )

        if is_nil(existing) do
          case upsert_parameter(category_str, param_name_str, value) do
            {:ok, _} ->
              Logger.info("Default parameter loaded: #{category_str}.#{param_name_str}")
            {:error, reason} ->
              Logger.error("Failed to load default parameter #{category_str}.#{param_name_str}: #{inspect(reason)}")
          end
        end
      end)
    end)

    :ok
  rescue
    error ->
      Logger.error("Failed to load default parameters: #{inspect(error)}")
      {:error, error}
  end
end
