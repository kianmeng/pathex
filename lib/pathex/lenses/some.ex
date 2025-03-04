defmodule Pathex.Lenses.Some do
  # Private module for `some()` lens
  # > see `Pathex.Lenses.some/0` documentation
  @moduledoc false

  def some do
    fn
      :view, {%{} = map, func} ->
        Enum.find_value(map, :error, fn {_k, v} ->
          with :error <- func.(v) do
            false
          end
        end)

      :view, {[{a, _} | _] = kwd, func} when is_atom(a) ->
        Enum.find_value(kwd, :error, fn {_k, v} ->
          with :error <- func.(v) do
            false
          end
        end)

      :view, {l, func} when is_list(l) ->
        Enum.find_value(l, :error, fn v ->
          with :error <- func.(v) do
            false
          end
        end)

      :view, {t, func} when is_tuple(t) ->
        Enum.find_value(Tuple.to_list(t), :error, fn v ->
          with :error <- func.(v) do
            false
          end
        end)

      :update, {%{} = map, func} ->
        found =
          Enum.find_value(map, :error, fn {k, v} ->
            case func.(v) do
              {:ok, v} -> {k, v}
              :error -> false
            end
          end)

        with {k, v} <- found do
          {:ok, Map.put(map, k, v)}
        end

      :update, {[{a, _} | _] = keyword, func} when is_atom(a) ->
        case keyword_update(keyword, func) do
          :error ->
            :error

          updated_keyword ->
            {:ok, updated_keyword}
        end

      :update, {list, func} when is_list(list) ->
        case list_update(list, func) do
          :error ->
            :error

          updated_list ->
            {:ok, updated_list}
        end

      :update, {tuple, func} when is_tuple(tuple) ->
        tuple_update(tuple, func, 1, tuple_size(tuple))

      :force_update, {%{} = map, func, default} ->
        map
        |> Enum.find_value(:error, fn {k, v} ->
          case func.(v) do
            {:ok, v} -> {k, v}
            :error -> false
          end
        end)
        |> case do
          {k, v} ->
            {:ok, Map.put(map, k, v)}

          :error ->
            map
            |> :maps.iterator()
            |> :maps.next()
            |> case do
              {k, _, _} ->
                {:ok, Map.put(map, k, default)}

              :none ->
                :error
            end
        end

      :force_update, {[{a, _} | _] = kwd, func, default} when is_atom(a) ->
        kwd
        |> Enum.find_value(:error, fn {k, v} ->
          case func.(v) do
            {:ok, v} -> {k, v}
            :error -> false
          end
        end)
        |> case do
          {k, v} ->
            {:ok, Keyword.put(kwd, k, v)}

          :error ->
            {:ok, Keyword.put(kwd, a, default)}
        end

      :force_update, {list, func, default} when is_list(list) ->
        list
        |> Enum.reduce({:error, []}, fn
          v, {:error, acc} ->
            case func.(v) do
              {:ok, v} -> {:ok, [v | acc]}
              :error -> {:error, [v | acc]}
            end

          v, {:ok, acc} ->
            {:ok, [v | acc]}
        end)
        |> case do
          {:error, list} ->
            [_first | list] = :lists.reverse(list)
            {:ok, [default | list]}

          {:ok, list} ->
            {:ok, :lists.reverse(list)}
        end

      :force_update, {t, func, default} when is_tuple(t) and tuple_size(t) > 0 ->
        t
        |> Tuple.to_list()
        |> Enum.reduce_while(1, fn v, index ->
          case func.(v) do
            {:ok, v} -> {:halt, {index, v}}
            :error -> {:cont, index + 1}
          end
        end)
        |> case do
          {index, v} ->
            {:ok, :erlang.setelement(index, t, v)}

          _ ->
            {:ok, :erlang.setelement(0, t, default)}
        end

      :delete, {%{} = map, func} ->
        map
        |> Enum.find_value(:error, fn {k, v} ->
          case func.(v) do
            {:ok, v} -> {:ok, k, v}
            :delete_me -> {:delete_me, k}
            :error -> false
          end
        end)
        |> case do
          {:delete_me, k} ->
            {:ok, Map.delete(map, k)}

          {:ok, k, v} ->
            {:ok, Map.put(map, k, v)}

          :error ->
            :error
        end

      :delete, {tuple, func} when is_tuple(tuple) and tuple_size(tuple) > 0 ->
        tuple_delete(tuple, func, 1, tuple_size(tuple))

      :delete, {[{a, _} | _] = keyword, func} when is_atom(a) ->
        case keyword_delete(keyword, func) do
          :error ->
            :error

          updated_keyword ->
            {:ok, updated_keyword}
        end

      :delete, {list, func} when is_list(list) ->
        case list_delete(list, func) do
          :error ->
            :error

          updated_list ->
            {:ok, updated_list}
        end

      :inspect, _ ->
        {:some, [], []}

      op, _ when op in ~w[delete view update force_update]a ->
        :error
    end
  end

  defp keyword_update([], _), do: :error

  defp keyword_update([{key, value} | tail], func) do
    case func.(value) do
      {:ok, new_value} ->
        [{key, new_value} | tail]

      :error ->
        [{key, value} | keyword_update(tail, func)]
    end
  end

  defp list_update([], _), do: :error

  defp list_update([value | tail], func) do
    case func.(value) do
      {:ok, new_value} ->
        [new_value | tail]

      :error ->
        [value | list_update(tail, func)]
    end
  end

  defp tuple_update(_, _, iterator, tuple_size) when iterator > tuple_size, do: :error

  defp tuple_update(tuple, func, iterator, tuple_size) do
    case func.(:erlang.element(iterator, tuple)) do
      {:ok, new_value} ->
        {:ok, :erlang.setelement(iterator, tuple, new_value)}

      :error ->
        tuple_update(tuple, func, iterator + 1, tuple_size)
    end
  end

  defp tuple_delete(_, _, iterator, tuple_size) when iterator > tuple_size, do: :error

  defp tuple_delete(tuple, func, iterator, tuple_size) do
    case func.(:erlang.element(iterator, tuple)) do
      {:ok, new_value} ->
        {:ok, :erlang.setelement(iterator, tuple, new_value)}

      :delete_me ->
        {:ok, :erlang.delete_element(iterator, tuple)}

      :error ->
        tuple_delete(tuple, func, iterator + 1, tuple_size)
    end
  end

  defp keyword_delete([], _), do: :error

  defp keyword_delete([{key, value} | tail], func) do
    case func.(value) do
      {:ok, new_value} ->
        [{key, new_value} | tail]

      :delete_me ->
        tail

      :error ->
        [{key, value} | keyword_delete(tail, func)]
    end
  end

  defp list_delete([], _), do: :error

  defp list_delete([value | tail], func) do
    case func.(value) do
      {:ok, new_value} ->
        [new_value | tail]

      :delete_me ->
        tail

      :error ->
        [value | list_delete(tail, func)]
    end
  end
end
