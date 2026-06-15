# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ManyToManyLoadActorBugTest do
  @moduledoc """
  Regression test: loading a `many_to_many` relationship with an actor must
  propagate that actor into the authorization filter of the join/through
  resource.

  Two conditions put the load on the lateral-join strategy, where the bug lives:

    * a unique constraint on the join keys (so AshPostgres prefers the lateral join)
    * the through resource's read policy uses a calculation that needs the actor

  On that path the through query is authorized and embedded directly into the
  lateral join without going through the read pipeline that sets calculation
  context. The calculation's `^actor(:id)` is therefore resolved with no actor
  and renders as `NULL` in the generated SQL, so the join matches nothing and
  the relationship loads empty — even though the actor is allowed and a direct
  read of the through resource authorizes correctly.
  """
  use AshPostgres.RepoCase, async: false

  require Ash.Query

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered?(true)
    end
  end

  defmodule Item do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: AshPostgres.DataLayer

    postgres do
      table("rb_items")
      repo(AshPostgres.TestRepo)
    end

    actions do
      default_accept(:*)
      defaults([:read, :destroy, create: :*, update: :*])
    end

    attributes do
      uuid_primary_key(:id)
    end
  end

  defmodule Group do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: AshPostgres.DataLayer

    postgres do
      table("rb_groups")
      repo(AshPostgres.TestRepo)
    end

    actions do
      default_accept(:*)
      defaults([:read, :destroy, create: :*, update: :*])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:owner_id, :uuid, public?: true)
    end

    relationships do
      many_to_many :items, Item do
        through(AshPostgres.Test.ManyToManyLoadActorBugTest.GroupItem)
        source_attribute_on_join_resource(:group_id)
        destination_attribute_on_join_resource(:item_id)
        public?(true)
      end
    end
  end

  defmodule GroupItem do
    @moduledoc "The join/through resource: a read policy backed by an actor-dependent calculation, plus a unique constraint on the join keys."
    use Ash.Resource,
      domain: Domain,
      data_layer: AshPostgres.DataLayer,
      authorizers: [Ash.Policy.Authorizer]

    postgres do
      table("rb_group_items")
      repo(AshPostgres.TestRepo)
    end

    actions do
      default_accept(:*)
      defaults([:read, :destroy, create: :*, update: :*])
    end

    policies do
      policy action_type(:read) do
        authorize_if(expr(actor_is_owner == true))
      end

      policy action_type([:create, :update, :destroy]) do
        authorize_if(always())
      end
    end

    attributes do
      uuid_primary_key(:id)
    end

    relationships do
      belongs_to(:group, Group, public?: true)
      belongs_to(:item, Item, public?: true)
    end

    identities do
      identity(:unique_group_item, [:group_id, :item_id])
    end

    calculations do
      # Needs the actor; `^actor(:id)` is resolved (from the calc context) only
      # when the calculation is expanded into SQL.
      calculate(:actor_is_owner, :boolean, expr(group.owner_id == ^actor(:id)))
    end
  end

  setup do
    user_id = Ash.UUID.generate()
    group = Ash.Seed.seed!(Group, %{owner_id: user_id})
    item = Ash.Seed.seed!(Item, %{})
    Ash.Seed.seed!(GroupItem, %{group_id: group.id, item_id: item.id})

    %{actor: %{id: user_id}, group: group, item: item}
  end

  test "a direct authorized read of the through resource sees the actor", %{actor: actor} do
    assert [_] = Ash.read!(GroupItem, actor: actor, authorize?: true)
  end

  test "many_to_many load propagates the actor into the through-resource policy", %{
    actor: actor,
    group: group,
    item: item
  } do
    loaded = Ash.load!(group, [:items], actor: actor, authorize?: true)

    assert [%{id: loaded_item_id}] = loaded.items,
           "many_to_many load must apply the through-resource policy WITH the actor, " <>
             "but it returned #{inspect(loaded.items)}"

    assert loaded_item_id == item.id
  end
end
