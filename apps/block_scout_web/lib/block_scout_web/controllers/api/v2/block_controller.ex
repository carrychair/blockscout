defmodule BlockScoutWeb.API.V2.BlockController do
  use BlockScoutWeb, :controller

  import BlockScoutWeb.Chain,
    only: [
      next_page_params: 3,
      paging_options: 1,
      put_key_value_to_paging_options: 3,
      split_list_by_page: 1,
      parse_block_hash_or_number_param: 1
    ]

  import BlockScoutWeb.PagingHelper,
    only: [delete_parameters_from_next_page_params: 1, select_block_type: 1, type_filter_options: 1]

  import Explorer.MicroserviceInterfaces.BENS, only: [maybe_preload_ens: 1]

  alias BlockScoutWeb.API.V2.{TransactionView, WithdrawalView}
  alias Explorer.Chain

  case Application.compile_env(:explorer, :chain_type) do
    "ethereum" ->
      @chain_type_transaction_necessity_by_association %{
        :beacon_blob_transaction => :optional
      }
      @chain_type_block_necessity_by_association %{
        [transactions: :beacon_blob_transaction] => :optional
      }

    _ ->
      @chain_type_transaction_necessity_by_association %{}
      @chain_type_block_necessity_by_association %{}
  end

  @transaction_necessity_by_association [
    necessity_by_association:
      %{
        [created_contract_address: :names] => :optional,
        [from_address: :names] => :optional,
        [to_address: :names] => :optional,
        :block => :optional,
        [created_contract_address: :smart_contract] => :optional,
        [from_address: :smart_contract] => :optional,
        [to_address: :smart_contract] => :optional
      }
      |> Map.merge(@chain_type_transaction_necessity_by_association)
  ]

  @api_true [api?: true]

  @block_params [
    necessity_by_association:
      %{
        [miner: :names] => :optional,
        :uncles => :optional,
        :nephews => :optional,
        :rewards => :optional,
        :transactions => :optional,
        :withdrawals => :optional
      }
      |> Map.merge(@chain_type_block_necessity_by_association),
    api?: true
  ]

  action_fallback(BlockScoutWeb.API.V2.FallbackController)

  def block(conn, %{"block_hash_or_number" => block_hash_or_number}) do
    with {:ok, type, value} <- parse_block_hash_or_number_param(block_hash_or_number),
         {:ok, block} <- fetch_block(type, value, @block_params) do
      conn
      |> put_status(200)
      |> render(:block, %{block: block})
    end
  end

  defp fetch_block(:hash, hash, params) do
    Chain.hash_to_block(hash, params)
  end

  defp fetch_block(:number, number, params) do
    case Chain.number_to_block(number, params) do
      {:ok, _block} = ok_response ->
        ok_response

      _ ->
        {:lost_consensus, Chain.nonconsensus_block_by_number(number, @api_true)}
    end
  end

  def blocks(conn, params) do
    full_options = select_block_type(params)

    blocks_plus_one =
      full_options
      |> Keyword.merge(paging_options(params))
      |> Keyword.merge(@api_true)
      |> Chain.list_blocks()

    {blocks, next_page} = split_list_by_page(blocks_plus_one)

    next_page_params = next_page |> next_page_params(blocks, delete_parameters_from_next_page_params(params))

    conn
    |> put_status(200)
    |> render(:blocks, %{blocks: blocks |> maybe_preload_ens(), next_page_params: next_page_params})
  end

  def transactions(conn, %{"block_hash_or_number" => block_hash_or_number} = params) do
    with {:ok, type, value} <- parse_block_hash_or_number_param(block_hash_or_number),
         {:ok, block} <- fetch_block(type, value, @api_true) do
      full_options =
        @transaction_necessity_by_association
        |> Keyword.merge(put_key_value_to_paging_options(paging_options(params), :is_index_in_asc_order, true))
        |> Keyword.merge(type_filter_options(params))
        |> Keyword.merge(@api_true)

      transactions_plus_one = Chain.block_to_transactions(block.hash, full_options, false)

      {transactions, next_page} = split_list_by_page(transactions_plus_one)

      next_page_params =
        next_page
        |> next_page_params(transactions, delete_parameters_from_next_page_params(params))

      conn
      |> put_status(200)
      |> put_view(TransactionView)
      |> render(:transactions, %{transactions: transactions |> maybe_preload_ens(), next_page_params: next_page_params})
    end
  end

  def withdrawals(conn, %{"block_hash_or_number" => block_hash_or_number} = params) do
    with {:ok, type, value} <- parse_block_hash_or_number_param(block_hash_or_number),
         {:ok, block} <- fetch_block(type, value, @api_true) do
      full_options =
        [necessity_by_association: %{address: :optional}, api?: true]
        |> Keyword.merge(paging_options(params))

      withdrawals_plus_one = Chain.block_to_withdrawals(block.hash, full_options)
      {withdrawals, next_page} = split_list_by_page(withdrawals_plus_one)

      next_page_params = next_page |> next_page_params(withdrawals, delete_parameters_from_next_page_params(params))

      conn
      |> put_status(200)
      |> put_view(WithdrawalView)
      |> render(:withdrawals, %{withdrawals: withdrawals |> maybe_preload_ens(), next_page_params: next_page_params})
    end
  end
end
