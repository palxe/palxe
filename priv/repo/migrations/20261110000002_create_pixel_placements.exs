defmodule Palxe.Repo.Migrations.CreatePixelPlacements do
  use Ecto.Migration

  def change do
    create table(:pixel_placements) do
      add :x, :integer, null: false
      add :y, :integer, null: false
      add :color, :integer, null: false
      add :player_id, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:pixel_placements, [:x, :y, :inserted_at])
  end
end
