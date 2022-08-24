defmodule BasicHotStuff.Util do
  def tsign(type, cur_view, node, key) do
    type = Enum.find_index([:new_view, :prepare, :pre_commit, :commit, :decide], &(&1 == type))
    binary = <<type, cur_view::4, node.parent::binary-size(32), byte_size(node.cmd)::4>> <> node.cmd
    :public_key.sign(binary, :none, key)
  end

  def msg(type, cur_view, node, qc) do
    %{type: type, view_number: cur_view, node: node, justify: qc}
  end

  def vote_msg(type, cur_view, node, qc, key) do
    m = msg(type, cur_view, node, qc)
    Map.put(m, :partial_sig, tsign(type, cur_view, node, key))
  end

  defp node_hash(node) do
    :crypto.hash(:sha256, node.parent <> node.cmd)
  end
  def create_leaf(parent, cmd) do
    %{parent: node_hash(parent), cmd: cmd}
  end

  def qc(type, view_number, node, partial_sigs) do
    %{
      type: type,
      view_number: view_number,
      node: node,
      sig: partial_sigs
    }
  end

  defguard matching_msg(m, t, v) when m.type == t and m.view_number == v

  defguard matching_qc(qc, t, v) when qc.type == t and qc.view_number == v

  def safe_node?(locked_qc, node, qc) do
    extends_from?(node, locked_qc.node) or qc.view_number > locked_qc.view_number
  end

  def extends_from?(node_extended, node_base) do
    node_extended.parent == node_hash(node_base)
  end
end
