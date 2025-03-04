defmodule Pathex.Lenses.Star do
  # Private module for `star()` lens
  @moduledoc false

  # Helpers

  defmacrop extend_if_ok(status, func, value, acc) do
    quote do
      case unquote(func).(unquote(value)) do
        {:ok, result} -> {:ok, [result | unquote(acc)]}
        :error -> {unquote(status), unquote(acc)}
      end
    end
  end

  defmacrop wrap_ok(code) do
    quote(do: {:ok, unquote(code)})
  end

  # Lens

  @spec star() :: Pathex.t()
  def star do
    fn
      :view, {%{} = map, func} ->
        map
        |> Enum.reduce({:error, []}, fn {_key, value}, {status, acc} ->
          extend_if_ok(status, func, value, acc)
        end)
        |> case do
          {:error, _} -> :error
          {:ok, res} -> {:ok, res}
        end

      :view, {tuple, func} when is_tuple(tuple) and tuple_size(tuple) > 0 ->
        tuple
        |> Tuple.to_list()
        |> Enum.reduce({:error, []}, fn value, {status, acc} ->
          extend_if_ok(status, func, value, acc)
        end)
        |> case do
          {:error, _} -> :error
          {:ok, res} -> {:ok, :lists.reverse(res)}
        end

      :view, {[{a, _} | _] = kwd, func} when is_atom(a) ->
        kwd
        |> Enum.reduce({:error, []}, fn {_key, value}, {status, acc} ->
          extend_if_ok(status, func, value, acc)
        end)
        |> case do
          {:error, _} -> :error
          {:ok, res} -> {:ok, :lists.reverse(res)}
        end

      :view, {list, func} when is_list(list) ->
        list
        |> Enum.reduce({:error, []}, fn value, {status, acc} ->
          extend_if_ok(status, func, value, acc)
        end)
        |> case do
          {:error, _} -> :error
          {:ok, res} -> {:ok, :lists.reverse(res)}
        end

      :update, {%{} = map, func} ->
        Enum.reduce(map, {:error, %{}}, fn {key, value}, {status, acc} ->
          case func.(value) do
            {:ok, new_value} -> {:ok, Map.put(acc, key, new_value)}
            :error -> {status, Map.put(acc, key, value)}
          end
        end)
        |> case do
          {:error, _} -> :error
          {:ok, map} -> {:ok, map}
        end

      :update, {tuple, func} when is_tuple(tuple) and tuple_size(tuple) > 0 ->
        tuple_update(tuple, func, 1, tuple_size(tuple), false)

      :update, {[{a, _} | _] = keyword, func} when is_atom(a) ->
        keyword_update(keyword, func, false, [])

      :update, {list, func} when is_list(list) ->
        list_update(list, func, false, [])

      :force_update, {%{} = map, func, default} ->
        map
        |> Map.new(fn {key, value} ->
          case func.(value) do
            {:ok, v} -> {key, v}
            :error -> {key, default}
          end
        end)
        |> wrap_ok()

      :force_update, {t, func, default} when is_tuple(t) and tuple_size(t) > 0 ->
        t
        |> Tuple.to_list()
        |> Enum.map(fn value ->
          case func.(value) do
            {:ok, v} -> v
            :error -> default
          end
        end)
        |> List.to_tuple()
        |> wrap_ok()

      :force_update, {[{a, _} | _] = kwd, func, default} when is_atom(a) ->
        kwd
        |> Enum.map(fn {key, value} ->
          case func.(value) do
            {:ok, v} -> {key, v}
            :error -> {key, default}
          end
        end)
        |> wrap_ok()

      :force_update, {l, func, default} when is_list(l) ->
        l
        |> Enum.map(fn value ->
          case func.(value) do
            {:ok, v} -> v
            :error -> default
          end
        end)
        |> wrap_ok()

      :delete, {tuple, func} when is_tuple(tuple) ->
        tuple_delete(tuple, func, 1, tuple_size(tuple), false)

      :delete, {map, func} when is_map(map) ->
        Enum.reduce(map, {:error, %{}}, fn {key, value}, {status, acc} ->
          case func.(value) do
            {:ok, new_value} -> {:ok, Map.put(acc, key, new_value)}
            :delete_me -> {:ok, acc}
            :error -> {status, Map.put(acc, key, value)}
          end
        end)
        |> case do
          {:error, _} -> :error
          {:ok, map} -> {:ok, map}
        end

      :delete, {[{a, _} | _] = keyword, func} when is_atom(a) ->
        keyword_delete(keyword, func, false, [])

      :delete, {list, func} when is_list(list) ->
        list_delete(list, func, false, [])

      :inspect, _ ->
        {:star, [], []}

      op, _ when op in ~w[delete view update force_update]a ->
        :error
    end
  end

  defp list_update([], _, false, _), do: :error
  defp list_update([], _, _true, head_acc), do: {:ok, :lists.reverse(head_acc)}

  defp list_update([head | tail], func, called?, head_acc) do
    case func.(head) do
      {:ok, new_value} ->
        list_update(tail, func, true, [new_value | head_acc])

      :error ->
        list_update(tail, func, called?, [head | head_acc])
    end
  end

  # defp tuple_update(list, func, iterator, tuple_size, called? \\ false)
  defp tuple_update(_, _, iterator, tuple_size, false) when iterator > tuple_size, do: :error
  defp tuple_update(t, _, iterator, tuple_size, _true) when iterator > tuple_size, do: t

  defp tuple_update(tuple, func, iterator, tuple_size, called?) do
    case func.(:erlang.element(iterator, tuple)) do
      {:ok, new_value} ->
        iterator
        |> :erlang.setelement(tuple, new_value)
        |> tuple_update(func, iterator + 1, tuple_size, true)

      :error ->
        tuple_update(tuple, func, iterator + 1, tuple_size, called?)
    end
  end

  # defp keyword_update(keyword, func, called? \\ false, head_acc \\ [])
  defp keyword_update([], _, false, _), do: :error
  defp keyword_update([], _, _true, head_acc), do: {:ok, :lists.reverse(head_acc)}

  defp keyword_update([{key, value} = head | tail], func, called?, head_acc) do
    case func.(value) do
      {:ok, new_value} ->
        keyword_update(tail, func, true, [{key, new_value} | head_acc])

      :error ->
        keyword_update(tail, func, called?, [head | head_acc])
    end
  end

  # defp list_delete(list, func, called? \\ false, head_acc \\ [])
  defp list_delete([], _, false, _), do: :error
  defp list_delete([], _, _true, head_acc), do: {:ok, :lists.reverse(head_acc)}

  defp list_delete([head | tail], func, called?, head_acc) do
    case func.(head) do
      {:ok, new_value} ->
        list_delete(tail, func, true, [new_value | head_acc])

      :delete_me ->
        list_delete(tail, func, true, head_acc)

      :error ->
        list_delete(tail, func, called?, [head | head_acc])
    end
  end

  # defp tuple_delete(list, func, iterator, tuple_size, called? \\ false)
  defp tuple_delete(_, _, iterator, tuple_size, false) when iterator > tuple_size, do: :error
  defp tuple_delete(t, _, iterator, tuple_size, _true) when iterator > tuple_size, do: t

  defp tuple_delete(tuple, func, iterator, tuple_size, called?) do
    case func.(:erlang.element(iterator, tuple)) do
      {:ok, new_value} ->
        iterator
        |> :erlang.setelement(tuple, new_value)
        |> tuple_delete(func, iterator + 1, tuple_size, true)

      :delete_me ->
        iterator
        |> :erlang.delete_element(tuple)
        |> tuple_delete(func, iterator, tuple_size - 1, true)

      :error ->
        tuple_delete(tuple, func, iterator + 1, tuple_size, called?)
    end
  end

  # defp keyword_delete(keyword, func, called? \\ false, head_acc \\ [])
  defp keyword_delete([], _, false, _), do: :error
  defp keyword_delete([], _, _true, head_acc), do: {:ok, :lists.reverse(head_acc)}

  defp keyword_delete([{key, value} = head | tail], func, called?, head_acc) do
    case func.(value) do
      {:ok, new_value} ->
        keyword_delete(tail, func, true, [{key, new_value} | head_acc])

      :delete_me ->
        keyword_delete(tail, func, true, head_acc)

      :error ->
        keyword_delete(tail, func, called?, [head | head_acc])
    end
  end
end
