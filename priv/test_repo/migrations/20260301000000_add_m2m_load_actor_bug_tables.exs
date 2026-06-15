# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestRepo.Migrations.AddM2mLoadActorBugTables do
  @moduledoc """
  Tables backing the regression test for actor propagation into the join/through
  resource's policy when loading a many_to_many relationship.

  See `test/many_to_many_load_actor_bug_test.exs`.
  """
  use Ecto.Migration

  def change do
    create table(:rb_groups, primary_key: false) do
      add(:id, :uuid, primary_key: true, null: false)
      add(:owner_id, :uuid)
    end

    create table(:rb_items, primary_key: false) do
      add(:id, :uuid, primary_key: true, null: false)
    end

    create table(:rb_group_items, primary_key: false) do
      add(:id, :uuid, primary_key: true, null: false)
      add(:group_id, :uuid, null: false)
      add(:item_id, :uuid, null: false)
    end

    # The unique constraint on the join keys is what makes Ash choose the
    # lateral-join load strategy for the many_to_many (where the bug lives).
    create(unique_index(:rb_group_items, [:group_id, :item_id]))
  end
end
