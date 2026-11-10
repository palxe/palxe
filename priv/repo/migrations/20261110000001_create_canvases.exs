defmodule Palxe.Repo.Migrations.CreateCanvases do
  use Ecto.Migration

  def change do
    create table(:canvases) do
      add :width, :integer, null: false
      add :height, :integer, null: false
      add :pixels, :binary, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
