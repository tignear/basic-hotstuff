defmodule BasicHotStuff.Role.Util do
  import BasicHotStuff.Util
  require Logger
  def wait_for_new_view_messages(_require_count, _cur_view, _prepare_qc, _messages, _rec \\ 15)

  def wait_for_new_view_messages(require_count, _cur_view, _prepare_qc, messages, _rec)
      when length(messages) >= require_count do
    {:ok, messages}
  end

  def wait_for_new_view_messages(require_count, _cur_view, _prepare_qc, messages, 0) do
    raise "infinite loop"
  end

  def wait_for_new_view_messages(require_count, cur_view, prepare_qc, messages, rec) do
    Logger.debug("wait for #{cur_view - 1}")

    receive do
      {:message, m, _addr} when matching_msg(m, :new_view, cur_view - 1) ->
        wait_for_new_view_messages(require_count, cur_view, prepare_qc, [m | messages], rec - 1)

      {:message, m, _addr} ->
        #Logger.warn("message ignored in wait_for_new_view_messages: #{inspect(m)}")

        wait_for_new_view_messages(require_count, cur_view, prepare_qc, messages, rec - 1)

      {:next_view, ^cur_view} ->
        :interrupt
    end
  end

  def wait_for_votes(_require_count, _cur_view, _type, _prepare_qc, _messages, _rec \\ 15)

  def wait_for_votes(require_count, _cur_view, _type, _prepare_qc, messages, _rec)
      when length(messages) >= require_count do
    Logger.debug("wait_for_votes:return")

    {:ok, messages}
  end

  def wait_for_votes(require_count, _cur_view, _type, _prepare_qc, messages, 0) do
    raise "infinite loop"
  end

  def wait_for_votes(require_count, cur_view, type, prepare_qc, messages, rec) do
    receive do
      {:message, %{partial_sig: _sig} = m, _addr} when matching_msg(m, type, cur_view) ->
        Logger.debug("wait_for_votes:#{inspect(m)},#{cur_view},#{inspect type}")
        wait_for_votes(require_count, cur_view, type, prepare_qc, [m | messages], rec - 1)

      {:message, m, _addr} ->
        #Logger.warn("message ignored in wait_for_votes: #{inspect(m)}")

        wait_for_votes(require_count, cur_view, type, prepare_qc, messages, rec - 1)

      {:next_view, ^cur_view} ->
        :interrupt
    end
  end

  def wait_for_message(leader, cur_view, rec \\ 5)

  def wait_for_message(_leader, _cur_view, 0) do
    raise "infinite loop"
  end

  def wait_for_message(leader, cur_view, rec) do
    receive do
      {:message, m, addr} when matching_msg(m, :prepare, cur_view) and addr == leader ->
        {:ok, m}

      {:message, m, _addr} ->
        #Logger.warn("message ignored in wait_for_message: #{inspect(m)}")

        wait_for_message(leader, cur_view, rec - 1)

      {:next_view, ^cur_view} ->
        :interrupt
    end
  end

  def wait_for_message_qc(leader, cur_view, type, rec \\ 5)

  def wait_for_message_qc(leader, cur_view, type, 0) do
    raise "infinite loop"
  end

  def wait_for_message_qc(leader, cur_view, type, rec) do
    receive do
      {:message, m, addr} when matching_qc(m.justify, type, cur_view) and addr == leader ->
        {:ok, m}

      {:message, m, _addr} ->
        #Logger.warn("message ignored in wait_for_message_qc: #{inspect(m)},#{inspect(type)}")

        wait_for_message_qc(leader, cur_view, type, rec - 1)

      {:next_view, ^cur_view} ->
        :interrupt
    end
  end

  def send_msg(addr, m, sender) do
    send(addr, {:message, m, sender})
  end

  def broadcast_msg(addrs, m, sender) do
    Enum.each(addrs, &send(&1, {:message, m, sender}))
  end
end
