defmodule BasicHotStuff do
  def start_one_node() do
    {:ECPrivateKey, 1, private_key, _params, public_key, :asn1_NOVALUE} =
      :public_key.generate_key({:namedCurve, :ed25519})

    nodes = &BasicHotStuff.NodeList.value/0

    {:ok, pid} =
      BasicHotStuff.Node.start_link(%{
        cur_view: 1,
        locked_qc:
          BasicHotStuff.Util.qc(
            :commit,
            0,
            %{
              parent:
                <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
                  22, 23, 24, 25, 26, 27, 28, 29, 30, 31>>,
              cmd: <<0>>
            },
            []
          ),
        prepare_qc:
          BasicHotStuff.Util.qc(
            :prepare,
            0,
            %{
              parent:
                <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
                  22, 23, 24, 25, 26, 27, 28, 29, 30, 31>>,
              cmd: <<0>>
            },
            []
          ),
        config: %{
          n: 4,
          f: 1,
          nodes: nodes,
          key: {:ed_pri, :ed25519, public_key, private_key},
          leader: fn cur_view ->
            nodes.() |> Enum.at(rem(cur_view, 4))
          end
        }
      })

    pid
  end

  def start() do
    nodes = 1..4 |> Enum.map(fn _ -> start_one_node() end)
    BasicHotStuff.NodeList.start_link(nodes)
    nodes |> Enum.each(&BasicHotStuff.Node.start(&1))
  end
end
