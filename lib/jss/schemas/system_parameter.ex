defmodule JSS.Schemas.SystemParameter do
  @moduledoc """
  Schema Ecto pour les paramètres système avec hot-reload.
  Stockage PostgreSQL avec audit trail et validation des types.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Types de données supportés
  @valid_data_types ~w(integer float boolean string list)

  # Catégories de paramètres prédéfinies
  @valid_categories ~w(optimizer system demo ui)

  schema "system_parameters" do
    field :category, :string
    field :parameter_name, :string
    field :parameter_value, :string
    field :data_type, :string
    field :description, :string
    field :is_hot_reloadable, :boolean, default: true
    field :created_by, :string, default: "system"
    field :updated_by, :string, default: "system"
    field :deleted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset pour la création et mise à jour des paramètres.
  Valide les types de données et contraintes métier.
  """
  def changeset(parameter, attrs) do
    parameter
    |> cast(attrs, [
      :category,
      :parameter_name,
      :parameter_value,
      :data_type,
      :description,
      :is_hot_reloadable,
      :created_by,
      :updated_by,
      :deleted_at
    ])
    |> validate_required([:category, :parameter_name, :parameter_value, :data_type])
    |> validate_inclusion(:data_type, @valid_data_types)
    |> validate_inclusion(:category, @valid_categories)
    |> validate_length(:category, min: 2, max: 50)
    |> validate_length(:parameter_name, min: 2, max: 100)
    |> validate_length(:description, max: 500)
    |> validate_parameter_value()
    |> unique_constraint([:category, :parameter_name],
      name: :system_parameters_category_parameter_name_index,
      message: "Parameter already exists in this category"
    )
  end

  @doc """
  Changeset pour la suppression logique (soft delete).
  """
  def delete_changeset(parameter, attrs \\ %{}) do
    parameter
    |> cast(attrs, [:deleted_at, :updated_by])
    |> put_change(:deleted_at, DateTime.utc_now())
    |> validate_required([:deleted_at])
  end

  @doc """
  Query pour récupérer seulement les paramètres actifs (non supprimés).
  """
  def active_query(query \\ __MODULE__) do
    from p in query, where: is_nil(p.deleted_at)
  end

  @doc """
  Query pour récupérer les paramètres par catégorie.
  """
  def by_category_query(query \\ __MODULE__, category) do
    from p in query, where: p.category == ^category
  end

  @doc """
  Query pour récupérer les paramètres hot-reloadables.
  """
  def hot_reloadable_query(query \\ __MODULE__) do
    from p in query, where: p.is_hot_reloadable == true
  end

  # Validation privée de la valeur selon le type
  defp validate_parameter_value(changeset) do
    data_type = get_field(changeset, :data_type)
    parameter_value = get_field(changeset, :parameter_value)

    case {data_type, parameter_value} do
      {nil, _} -> changeset
      {_, nil} -> changeset
      {type, value} -> validate_value_for_type(changeset, type, value)
    end
  end

  defp validate_value_for_type(changeset, "integer", value) do
    case Integer.parse(value) do
      {_int, ""} -> changeset
      _ -> add_error(changeset, :parameter_value, "must be a valid integer")
    end
  end

  defp validate_value_for_type(changeset, "float", value) do
    case Float.parse(value) do
      {_float, ""} -> changeset
      _ -> add_error(changeset, :parameter_value, "must be a valid float")
    end
  end

  defp validate_value_for_type(changeset, "boolean", value) do
    if value in ~w(true false) do
      changeset
    else
      add_error(changeset, :parameter_value, "must be 'true' or 'false'")
    end
  end

  defp validate_value_for_type(changeset, "list", value) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) -> changeset
      _ -> add_error(changeset, :parameter_value, "must be a valid JSON array")
    end
  end

  defp validate_value_for_type(changeset, "string", _value) do
    # Les strings sont toujours valides
    changeset
  end
end
