defmodule AttributeRepositoryRiak do
  @moduledoc """

  ## Initializing a bucket type for attribute repository

  ```sh
  $ sudo riak-admin bucket-type create attr_rep '{"props":{"datatype":"map", "backend":"leveldb_mult"}}'
  attr_rep created

  $ sudo riak-admin bucket-type activate attr_rep
  attr_rep has been activated

  ```


  ## Options

  ### run options (`run_opts`)
  - `:instance`: instance name (an `atom()`)
  - `:bucket_type`: a `String.t()` for the bucket type that must be created beforehand
  """

  require Logger

  alias AttributeRepository.Search.AttributePath

  use AttributeRepository.Read
  use AttributeRepository.Write
  use AttributeRepository.Search

  @behaviour AttributeRepository.Install
  @behaviour AttributeRepository.Read
  @behaviour AttributeRepository.Write
  @behaviour AttributeRepository.Search

  @impl AttributeRepository.Install

  def install(run_opts, _init_opts) do
    :ok = Riak.Search.Schema.create(
      schema_name(run_opts),
      :code.priv_dir(:attribute_repository_riak) ++ '/schema.xml' |> File.read!()
    )

    :ok = Riak.Search.Index.put(index_name(run_opts), schema_name(run_opts))

    :ok = Riak.Search.Index.set({run_opts[:bucket_type], bucket_name(run_opts)},
                                index_name(run_opts))
  end

  @impl AttributeRepository.Read

  def get(resource_id, attributes, run_opts) do
    case Riak.find(run_opts[:bucket_type], bucket_name(run_opts), resource_id) do
      nil ->
        {:error, AttributeRepository.Read.NotFoundError.exception("Entry not found")}

      attribute_list ->
        {
          :ok,
          Enum.reduce(
            Riak.CRDT.Map.value(attribute_list),
            %{},
            fn
              {{attribute_name, _attribute_type}, attribute_value}, acc ->
                if attributes == :all or attribute_name in attributes do
                  if String.ends_with?(attribute_name, "_date") do
                    Map.put(acc,
                            String.slice(attribute_name, 0..-6),
                            elem(DateTime.from_iso8601(attribute_value), 1))
                  else
                    if String.ends_with?(attribute_name, "_binarydata") do
                    Map.put(acc,
                            String.slice(attribute_name, 0..-12),
                            {:binary_data, attribute_value})
                    else
                      Map.put(acc, attribute_name, attribute_value)
                    end
                  end
                else
                  acc
                end
            end
          )
        }
    end
  end

  @impl AttributeRepository.Write

  def put(resource_id, resource, run_opts) do
    new_base_obj =
      case Riak.find(run_opts[:bucket_type], bucket_name(run_opts), resource_id) do
        obj when not is_nil(obj) ->
          #FIXME: mwe may not need to keep the same object in the case of repacement:
          # just deleting it and creating a new could be enough?
          # There would be however a short time with no object
          Enum.reduce(
            Riak.CRDT.Map.keys(obj),
            obj,
            fn
              {key, type}, acc ->
                Riak.CRDT.Map.delete(acc, {key, type})
            end
          )

        nil ->
          Riak.CRDT.Map.new()
      end

    riak_res =
      Enum.reduce(
        resource,
        new_base_obj,
        fn
          {key, value}, acc ->
            pre_insert_map_put(acc, key, value)
        end
      )

    case Riak.update(riak_res, run_opts[:bucket_type], bucket_name(run_opts), resource_id) do
      :ok ->
        {:ok, resource}

      _ ->
        {:error, AttributeRepository.WriteError.exception("Write error")}
    end
  end

  @impl AttributeRepository.Write

  def modify(resource_id, modify_ops, run_opts) do
    case Riak.find(run_opts[:bucket_type], bucket_name(run_opts), resource_id) do
      obj when not is_nil(obj) ->
        modified_obj =
          Enum.reduce(
            modify_ops,
            obj,
            fn
              {:add, attribute_name, attribute_value}, acc ->
                pre_insert_map_put(acc, attribute_name, attribute_value)

              {:replace, attribute_name, value}, acc ->
                try do
                  # sets can only be for strings - so no need to handle date, etc. here
                  Riak.CRDT.Map.update(acc,
                                       :set,
                                       attribute_name,
                                       fn
                                         set ->
                                           set =
                                             Enum.reduce(
                                               Riak.CRDT.Set.value(set),
                                               set,
                                               fn
                                                 val, acc ->
                                                   Riak.CRDT.Set.delete(acc, val)
                                               end
                                             )

                                           Riak.CRDT.Set.put(set, value)
                                       end)
                rescue
                  _ ->
                    pre_insert_map_put(acc, attribute_name, value)
                end

              {:replace, attribute_name, old_value, new_value}, acc ->
                try do
                  # sets can only be for strings - so no need to handle date, etc. here
                  Riak.CRDT.Map.update(acc,
                                       :set,
                                       attribute_name,
                                       fn
                                         set ->
                                           set
                                           |> Riak.CRDT.Set.delete(old_value)
                                           |> Riak.CRDT.Set.put(new_value)
                                       end)
                rescue
                  _ ->
                    pre_insert_map_put(acc, attribute_name, new_value)
                end

              {:delete, attribute_name}, acc ->
                case map_entry_data_type_of_key(obj, attribute_name) do
                  data_type when not is_nil(data_type) ->
                    Riak.CRDT.Map.delete(acc, {attribute_name, data_type})

                  nil ->
                    acc
                end

              {:delete, attribute_name, attribute_value}, acc ->
                try do
                  Riak.CRDT.Map.update(acc,
                                       :set,
                                       attribute_name,
                                       fn
                                         obj ->
                                           Riak.CRDT.Set.delete(obj, attribute_value)
                                       end)
                rescue
                  _ ->
                    acc
                end
            end
          )

        case Riak.update(modified_obj,
                         run_opts[:bucket_type],
                         bucket_name(run_opts),
                         resource_id) do
          :ok ->
            :ok

          _ ->
            {:error, AttributeRepository.WriteError.exception("Write error")}
        end

      nil ->
        {:error, AttributeRepository.Read.NotFoundError.exception("Entry not found")}
    end
  end

  defp pre_insert_map_put(map, attribute_name, %DateTime{} = value) do
    map
    |> crdt_map_delete_if_present(attribute_name)
    |> crdt_map_delete_if_present(attribute_name <> "_binarydata")
    |> Riak.CRDT.Map.put(attribute_name <> "_date", to_riak_crdt(value))
  end

  defp pre_insert_map_put(map, attribute_name, {:binary_data, binary_data}) do
    map
    |> crdt_map_delete_if_present(attribute_name)
    |> crdt_map_delete_if_present(attribute_name <> "_date")
    |> Riak.CRDT.Map.put(attribute_name <> "_binarydata", to_riak_crdt(binary_data))
  end

  defp pre_insert_map_put(map, attribute_name, value) do
    map
    |> crdt_map_delete_if_present(attribute_name <> "_binarydata")
    |> crdt_map_delete_if_present(attribute_name <> "_date")
    |> Riak.CRDT.Map.put(attribute_name, to_riak_crdt(value))
  end

  defp crdt_map_delete_if_present(map, attribute_name) do
    if Riak.CRDT.Map.has_key?(map, attribute_name) do
      Riak.CRDT.Map.delete(map, {attribute_name, :register})
    else
      map
    end
  end

  @impl AttributeRepository.Write

  def delete(resource_id, run_opts) do
    Riak.delete(run_opts[:bucket_type], bucket_name(run_opts), resource_id)
  end

  @impl AttributeRepository.Search

  def search(filter, attributes, run_opts) do
    case Riak.Search.query(index_name(run_opts), build_riak_filter(filter)) do
      {:ok, {:search_results, result_list, _, _}} ->
        for {_index_name, result_attributes} <- result_list do
          {
            id_from_search_result(result_attributes),
            Enum.reduce(
              result_attributes,
              %{},
              fn {attribute_name, attribute_value}, acc ->
                to_search_result_map(acc, attribute_name, attribute_value, attributes)
              end
            )
          }
        end

      {:error, reason} ->
        {:error, AttributeRepository.ReadError.exception(inspect(reason))}
    end
  rescue
    e in AttributeRepository.UnsupportedError ->
      {:error, e}
  end

  defp id_from_search_result(result_attributes) do
    :proplists.get_value("_yz_id", result_attributes)
    |> String.split("*")
    |> Enum.at(3)
  end

  defp to_search_result_map(result_map, attribute_name, attribute_value, attribute_list) do
    res = Regex.run(~r/(.*)_(register|flag|counter|set|date_register|binarydata_register)/U,
                    attribute_name,
                    capture: :all_but_first)

    if res != nil and (attribute_list == :all or List.first(res) in attribute_list) do
      case res do
        [attribute_name, "register"] ->
          Map.put(result_map, attribute_name, attribute_value)

        [attribute_name, "flag"] ->
          Map.put(result_map, attribute_name, attribute_value == "true")

        [attribute_name, "counter"] ->
          {int, _} = Integer.parse(attribute_value)

          Map.put(result_map, attribute_name, int)

        [attribute_name, "set"] ->
          Map.put(result_map,
                  attribute_name,
                  [attribute_value] ++ (result_map[attribute_name] || []))

        [attribute_name, "date_register"] ->
          {:ok, date, _} = DateTime.from_iso8601(attribute_value)

          Map.put(result_map, attribute_name, date)

        [attribute_name, "binarydata_register"] ->
          Map.put(result_map, attribute_name, {:binary_data, attribute_value})

        _ ->
          result_map
      end
    else
      result_map
    end
  end

  defp build_riak_filter({:attrExp, attrExp}) do
    build_riak_filter(attrExp)
  end

  defp build_riak_filter({:and, lhs, rhs}) do
    build_riak_filter(lhs) <> " AND " <> build_riak_filter(rhs)
  end

  defp build_riak_filter({:or, lhs, rhs}) do
    "(" <> build_riak_filter(lhs) <> ") OR (" <> build_riak_filter(rhs) <> ")"
  end

  defp build_riak_filter({:not, filter}) do
    "(*:* NOT " <> build_riak_filter(filter) <> ")"
  end

  defp build_riak_filter({:pr, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  }})
  do
    attribute <> "_register:* OR " <>
    attribute <> "_date_register:* OR " <>
    attribute <> "_binarydata_register:* OR " <>
    attribute <> "_flag:* OR " <>
    attribute <> "_counter:* OR " <>
    attribute <> "_set:*"
  end

  defp build_riak_filter({:eq, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  }, value}) when is_binary(value)
  do
    attribute <> "_register:" <> to_string(value) <> " OR " <>
    attribute <> "_set:" <> to_string(value) # special case to handle equality in sets
  end

  defp build_riak_filter({:eq, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  }, value}) when is_boolean(value) or is_integer(value)
  do
    riak_attribute_name(attribute, value) <> ":" <> to_string(value)
  end

  defp build_riak_filter({:eq, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  }, %DateTime{} = value})
  do
    riak_attribute_name(attribute, value) <>
    ":[" <>
    DateTime.to_iso8601(value) <>
    " TO " <>
    DateTime.to_iso8601(value) <>
    "]"
  end

  defp build_riak_filter({:eq, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  }, {:binary_data, value}})
  do
    riak_attribute_name(attribute, value) <> ":" <> to_string(value)
  end

  defp build_riak_filter({:ne, attribute_path, value})
  do
    "(*:* NOT " <> build_riak_filter({:eq, attribute_path, value}) <> ")"
  end

  defp build_riak_filter({:ge, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  }, value}) when is_binary(value) or is_integer(value)
  do
    riak_attribute_name(attribute, value) <> ":[" <> to_string(value) <> " TO *]"
  end

  defp build_riak_filter({:ge, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  }, %DateTime{} = value})
  do
    riak_attribute_name(attribute, value) <> ":[" <> DateTime.to_iso8601(value) <> " TO *]"
  end

  defp build_riak_filter({:le, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  }, value}) when is_binary(value) or is_integer(value)
  do
    riak_attribute_name(attribute, value) <> ":[* TO " <> to_string(value) <> "]"
  end

  defp build_riak_filter({:le, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  }, %DateTime{} = value})
  do
    riak_attribute_name(attribute, value) <> ":[* TO " <> DateTime.to_iso8601(value) <> "]"
  end

  defp build_riak_filter({:gt, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  } = attribute_path, value}) when is_binary(value) or is_integer(value)
  do
    riak_attribute_name(attribute, value) <> ":* AND " <> # attribute does exist
    "(*:* NOT " <> build_riak_filter({:le, attribute_path, value}) <> ")"
  end

  defp build_riak_filter({:gt, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  } = attribute_path, %DateTime{} = value})
  do
    riak_attribute_name(attribute, value) <> ":* AND " <> # attribute does exist
    "(*:* NOT " <> build_riak_filter({:le, attribute_path, value}) <> ")"
  end

  defp build_riak_filter({:lt, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  } = attribute_path, value}) when is_binary(value) or is_integer(value)
  do
    riak_attribute_name(attribute, value) <> ":* AND " <> # attribute does exist
    "(*:* NOT " <> build_riak_filter({:ge, attribute_path, value}) <> ")"
  end

  defp build_riak_filter({:lt, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  } = attribute_path, %DateTime{} = value})
  do
    riak_attribute_name(attribute, value) <> ":* AND " <> # attribute does exist
    "(*:* NOT " <> build_riak_filter({:ge, attribute_path, value}) <> ")"
  end

  defp build_riak_filter({:co, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  }, value}) when is_binary(attribute)
  do
    attribute <> "_register:*" <> to_string(value) <> "* OR " <>
      attribute <> "_set:*" <> to_string(value) <> "*" # special case to handle equality in sets
  end

  defp build_riak_filter({:sw, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  }, value}) when is_binary(attribute)
  do
    attribute <> "_register:" <> to_string(value) <> "* OR " <>
      attribute <> "_set:" <> to_string(value) <> "*" # special case to handle equality in sets
  end

  defp build_riak_filter({:ew, %AttributePath{
    attribute: attribute,
    sub_attribute: nil
  }, value}) when is_binary(attribute)
  do
    attribute <> "_register:*" <> to_string(value) <> " OR " <>
      attribute <> "_set:*" <> to_string(value) # special case to handle equality in sets
  end

  defp build_riak_filter({_, _, value}) when is_float(value) or is_nil(value) do
    raise AttributeRepository.UnsupportedError, message: "Unsupported data type"
  end

  defp build_riak_filter({_, _, {:binary_data, _}}) do
    raise AttributeRepository.UnsupportedError, message: "Unsupported data type"
  end

  defp build_riak_filter({_, _, {:ref, _, _}}) do
    raise AttributeRepository.UnsupportedError, message: "Unsupported data type"
  end

  defp riak_attribute_name(name, {:binary_data, _value}), do: name <> "_binarydata_register"
  defp riak_attribute_name(name, value) when is_binary(value), do: name <> "_register"
  defp riak_attribute_name(name, %DateTime{}), do: name <> "_date_register"
  defp riak_attribute_name(name, value) when is_boolean(value), do: name <> "_flag"
  defp riak_attribute_name(name, value) when is_integer(value), do: name <> "_counter"

  @spec to_riak_crdt(AttributeRepository.attribute_data_type()) :: any()

  defp to_riak_crdt(value) when is_binary(value) do
    Riak.CRDT.Register.new(value)
  end

  defp to_riak_crdt(true) do
    Riak.CRDT.Flag.new()
    |> Riak.CRDT.Flag.enable()
  end

  defp to_riak_crdt(false) do
    Riak.CRDT.Flag.new()
    |> Riak.CRDT.Flag.disable()
  end

  defp to_riak_crdt(value) when is_integer(value) do
    Riak.CRDT.Counter.new()
    |> Riak.CRDT.Counter.increment(value)
  end

  defp to_riak_crdt(%DateTime{} = value) do
    value
    |> DateTime.to_iso8601()
    |> Riak.CRDT.Register.new()
  end

  defp to_riak_crdt({:binary_data, value}) do
    Riak.CRDT.Register.new(value)
  end

  defp to_riak_crdt(value) when is_list(value) do
    Enum.reduce(
      value,
      Riak.CRDT.Set.new(),
      fn
        list_element, acc ->
          Riak.CRDT.Set.put(acc, list_element)
      end
    )
  end

  @spec bucket_name(AttributeRepository.run_opts()) :: String.t()
  defp bucket_name(run_opts), do: "attribute_repository_" <> to_string(run_opts[:instance])

  @spec index_name(AttributeRepository.run_opts()) :: String.t()
  defp index_name(run_opts), do: "attribute_repository_" <> to_string(run_opts[:instance]) <> "_index"

  @spec schema_name(AttributeRepository.run_opts()) :: String.t()
  def schema_name(_run_opts), do: "attribute_repository_schema"

  defp map_entry_data_type_of_key(obj, key) do
    keys = Riak.CRDT.Map.keys(obj)

    case Enum.find(
      keys,
      fn
        {^key, _} ->
          true

        _ ->
          false
      end
    ) do
      {^key, type} ->
        type

      _ ->
        nil
    end
  end
end
