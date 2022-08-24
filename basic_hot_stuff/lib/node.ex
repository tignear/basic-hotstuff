defmodule BasicHotStuff.Node do
  use GenServer
  alias BasicHotStuff.Role.{Replica, Leader}
  require Logger

  @next_view_timeout 5000
  def start_link(
        %{
          cur_view: _cur_view,
          locked_qc: _locked_qc,
          prepare_qc: _prepare_qc,
          config: %{
            n: _n,
            f: _f,
            nodes: _nodes,
            key: _key,
            leader: _leader
          }
        } = options
      ) do
    GenServer.start_link(__MODULE__, options)
  end

  def init(options) do
    options = %{options | config: options.config |> Map.put(:node_id, self())}
    {:ok, pid} = DynamicSupervisor.start_link(strategy: :one_for_one)

    {:ok, options |> Map.put(:super_visor, pid)}
  end

  def start(pid) do
    GenServer.cast(pid, :start)
  end

  def handle_cast(:start, st) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        st.super_visor,
        {Replica,
         %{
           config: st.config |> Map.put(:notice_next_view, &notice_next_view/2),
           cur_view: st.cur_view,
           locked_qc: st.locked_qc,
           prepare_qc: st.prepare_qc
         }}
      )

    Process.send_after(self(), {:next_view, st.cur_view}, @next_view_timeout)
    {:noreply, st |> Map.put(:replica, pid)}
  end

  def notice_next_view(pid, ctx) do
    GenServer.call(pid, {:notice_next_view, ctx})
  end

  def handle_call({:notice_next_view, ctx}, _from, st) do
    Logger.debug("notice_next_view: #{ctx.cur_view}")
    Process.send_after(self(), {:next_view, ctx.cur_view}, @next_view_timeout)
    st = Map.delete(st, :leader)
    st = Map.merge(st, ctx)
    IO.inspect(st)
    if st.config.leader.(ctx.cur_view) == self() do
      {:ok, pid} =
        DynamicSupervisor.start_child(
          st.super_visor,
          {Leader, ctx |> Map.put(:clients_command, <<0xF6>>)}
        )

      {:reply, :ok, st |> Map.put(:leader, pid)}
    else
      {:reply, :ok, st}
    end
  end

  def handle_info({:message, _msg, _sender} = m, st) do
    relay_msg(m, st)
  end

  def handle_info({:next_view, _view_number} = m, st) do
    Logger.debug("received message:#{inspect(m)}")

    relay_msg(m, st)
  end

  defp relay_msg(m, st) do
    send(st.replica, m)

    case Map.get(st, :leader) do
      nil -> nil
      leader -> send(leader, m)
    end

    {:noreply, st}
  end
end
