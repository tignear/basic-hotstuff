defmodule BasicHotStuff.Role.Leader do
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
          prepare_qc: prepare_qc,
          config: %{
            n: n,
            f: f,
            nodes: nodes,
            node_id: node_id
          },
          clients_command: clients_command
        } = ctx
      ) do
    Logger.debug("leader: prepare")

    case wait_for_new_view_messages(n - f, cur_view, prepare_qc, []) do
      {:ok, messages} ->
        high_qc = (messages |> Enum.max_by(& &1.justify.view_number)).justify
        IO.inspect(high_qc)
        cur_proposal = create_leaf(high_qc.node, clients_command)
        broadcast_msg(nodes.(), msg(:prepare, cur_view, cur_proposal, high_qc), node_id)
        pre_commit(ctx |> Map.delete(:clients_command))

      :interrupt ->
        next_view(ctx |> Map.delete(:clients_command))
    end
  end

  def pre_commit(
        %{
          cur_view: cur_view,
          prepare_qc: prepare_qc,
          config: %{
            n: n,
            f: f,
            nodes: nodes,
            node_id: node_id
          }
        } = ctx
      ) do
    Logger.debug("leader: pre_commit")

    case wait_for_votes(n - f, cur_view, :prepare, prepare_qc, []) do
      {:ok, votes} ->
        [h | tail] = votes |> Enum.map(&Map.take(&1, [:node, :view_number, :type]))

        with true <- tail |> Enum.all?(&(&1 == h)) do
          prepare_qc = qc(h.type, h.view_number, h.node, votes |> Enum.map(& &1.partial_sig))
          ctx = %{ctx | prepare_qc: prepare_qc}
          broadcast_msg(nodes.(), msg(:pre_commit, cur_view, nil, prepare_qc), node_id)
          commit(ctx)
        else
          _ ->
            IO.inspect(votes)
            raise "not implemented"
        end

      :interrupt ->
        Logger.warn("interrupted")
        next_view(ctx)
    end
  end

  def commit(
        %{
          cur_view: cur_view,
          prepare_qc: prepare_qc,
          config: %{
            n: n,
            f: f,
            nodes: nodes,
            node_id: node_id
          }
        } = ctx
      ) do
    Logger.debug("leader: commit")

    case wait_for_votes(n - f, cur_view, :pre_commit, prepare_qc, []) do
      {:ok, votes} ->
        [h | tail] = votes |> Enum.map(&Map.take(&1, [:node, :view_number, :type]))

        with true <- tail |> Enum.all?(&(&1 == h)) do
          pre_commit_qc = qc(h.type, h.view_number, h.node, votes |> Enum.map(& &1.partial_sig))
          broadcast_msg(nodes.(), msg(:commit, cur_view, nil, pre_commit_qc), node_id)
          decide(ctx)
        else
          _ -> raise "not implemented"
        end

      :interrupt ->
        next_view(ctx)
    end
  end

  def decide(
        %{
          cur_view: cur_view,
          prepare_qc: prepare_qc,
          config: %{
            n: n,
            f: f,
            nodes: nodes,
            node_id: node_id
          }
        } = ctx
      ) do
    Logger.debug("leader: decide")

    case wait_for_votes(n - f, cur_view, :commit, prepare_qc, []) do
      {:ok, votes} ->
        [h | tail] = votes |> Enum.map(&Map.take(&1, [:node, :view_number, :type]))

        with true <- tail |> Enum.all?(&(&1 == h)) do
          commit_qc = qc(h.type, h.view_number, h.node, votes |> Enum.map(& &1.partial_sig))
          broadcast_msg(nodes.(), msg(:decide, cur_view, nil, commit_qc), node_id)
          Logger.info("decided!!#{inspect(commit_qc)}")
          next_view(ctx)
        else
          _ -> raise "not implemented"
        end

      :interrupt ->
        next_view(ctx)
    end
  end

  def next_view(_ctx) do
    exit(:normal)
  end
end
