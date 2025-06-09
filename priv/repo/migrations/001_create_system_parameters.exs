defmodule JSS.Repo.Migrations.CreateSystemParameters do
  use Ecto.Migration

  def change do
    create table(:system_parameters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :category, :string, null: false, size: 50
      add :parameter_name, :string, null: false, size: 100
      add :parameter_value, :text, null: false
      add :data_type, :string, null: false, size: 20
      add :description, :text
      add :is_hot_reloadable, :boolean, default: true, null: false
      add :created_by, :string, default: "system", size: 100
      add :updated_by, :string, default: "system", size: 100
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Index unique sur (category, parameter_name) pour les paramètres actifs
    create unique_index(:system_parameters, [:category, :parameter_name],
      where: "deleted_at IS NULL",
      name: :system_parameters_category_parameter_name_index
    )

    # Index de performance sur category pour les requêtes par catégorie
    create index(:system_parameters, [:category])

    # Index pour les requêtes de paramètres hot-reloadables
    create index(:system_parameters, [:is_hot_reloadable])

    # Index pour les soft-deletes
    create index(:system_parameters, [:deleted_at])

    # Index de performance sur created_at pour l'audit
    create index(:system_parameters, [:inserted_at])

    # Contraintes de validation au niveau base
    create constraint(:system_parameters, :valid_data_type,
      check: "data_type IN ('integer', 'float', 'boolean', 'string', 'list')"
    )

    create constraint(:system_parameters, :valid_category,
      check: "category IN ('optimizer', 'system', 'demo', 'ui')"
    )

    create constraint(:system_parameters, :non_empty_parameter_name,
      check: "length(trim(parameter_name)) > 0"
    )

    create constraint(:system_parameters, :non_empty_category,
      check: "length(trim(category)) > 0"
    )
  end

  def down do
    drop table(:system_parameters)
  end
end
