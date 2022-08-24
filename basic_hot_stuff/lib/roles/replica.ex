defmodule BasicHotStuff.Role.Replica do
  import BasicHotStuff.Util
  import BasicHotStuff.Role.Util
  require Logger

  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      shutdown: 5_000,
      restart: :transient,
      type: :worker
    }
  end

  def start_link(options) do
    {:ok, spawn_link(__MODULE__, :prepare, [options])}
  end

  def prepare(
        %{
          cur_view: cur_view,
          locked_qc: locked_qc,
          config: %{
            key: key,
            leader: leader,
            node_id: node_id
          }
        } = ctx
      ) do
    Logger.debug("replica: prepare")

    leader = leader.(cur_view)

    case wait_for_message(leader, cur_view) do
      {:ok, m} ->
        with {:extends_from, true} <- {:extends_from, extends_from?(m.node, m.justify.node)},
             {:safe_node, true} <- {:safe_node, safe_node?(locked_qc, m.node, m.justify)} do
          send_msg(leader, vote_msg(:prepare, cur_view, m.node, nil, key), node_id)
          pre_commit(ctx)
        else
          err ->
            Logger.warn("failed assertion#{inspect(err)},#{inspect(m)},#{inspect(locked_qc)}")
            raise "not implemented"
        end

      :interrupt ->
        next_view(ctx)
    end
  end

  def pre_commit(
        %{
          cur_view: cur_view,
          config: %{
            key: key,
            leader: leader,
            node_id: node_id
          }
        } = ctx
      ) do
    Logger.debug("replica: pre_commit")

    leader = leader.(cur_view)

    case wait_for_message_qc(leader, cur_view, :prepare) do
      {:ok, m} ->
        ctx = %{ctx | prepare_qc: m.justify}

        send_msg(
          leader,
          vote_msg(:pre_commit, cur_view, m.justify.node, nil, key),
          node_id
        )

        commit(ctx)

      :interrupt ->
        next_view(ctx)
    end
  end

  def commit(
        %{
          cur_view: cur_view,
          config: %{
            key: key,
            leader: leader,
            node_id: node_id
          }
        } = ctx
      ) do
    Logger.debug("replica: commit")

    leader = leader.(cur_view)

    case wait_for_message_qc(leader, cur_view, :pre_commit) do
      {:ok, m} ->
        ctx = %{ctx | locked_qc: m.justify}
        Logger.debug("replica@commit: send vote")

        send_msg(leader, vote_msg(:commit, cur_view, m.justify.node, nil, key), node_id)
        decide(ctx)

      :interrupt ->
        next_view(ctx)
    end
  end

  def decide(
        %{
          cur_view: cur_view,
          config: %{
            leader: leader
          }
        } = ctx
      ) do
    Logger.debug("replica: decide")

    case wait_for_message_qc(leader.(cur_view), cur_view, :commit) do
      {:ok, _m} ->
        next_view(ctx)

      :interrupt ->
        next_view(ctx)
    end
  end

  def next_view(
        %{
          cur_view: cur_view,
          prepare_qc: prepare_qc,
          config: %{
            leader: leader,
            node_id: node_id,
            notice_next_view: notice_next_view
          }
        } = ctx
      ) do
    Logger.debug("replica: next_view")

    ctx = ctx |> Map.put(:cur_view, cur_view + 1)
    notice_next_view.(node_id, ctx)
    Process.sleep(1)
    send_msg(leader.(cur_view + 1), msg(:new_view, cur_view, nil, prepare_qc), node_id)

    prepare(ctx)
  end

  def next_view(_) do
    raise "error"
  end
end
