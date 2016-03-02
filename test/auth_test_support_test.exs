defmodule AuthTestSupportTest do
  use ExUnit.Case

  use Phoenix.ConnTest
  @endpoint Endpoint
  import Router.Helpers
  use AuthTestSupport

  setup_all do
    Endpoint.start_link()
    Application.load(:phoenix)
    on_exit fn -> Application.delete_env(:auth_test_support, :serve_endpoints) end
    :ok
  end

  setup do
    conn =
      Phoenix.ConnTest.conn(:get, "/")

    user = struct(User, %{})
    admin = struct(Admin, %{})

    {:ok, conn: conn, user: user, admin: admin}
  end

  test "assert_authorized_as when not authenticated raises on missing account_id value", %{conn: conn, user: user} do
    conn =
      conn
      |> Phoenix.ConnTest.bypass_through()
      |> @endpoint.call(@endpoint.init([]))
      |> Plug.Conn.fetch_session()

    assert_raise ExUnit.AssertionError, "expected an account_id to be set", fn ->
      assert_authorized_as(conn, user)
    end
  end

  test "assert_authorized_as when not authenticated raises when account_id mismatch", %{conn: conn, user: user} do
    conn =
      conn
      |> Phoenix.ConnTest.bypass_through()
      |> @endpoint.call(@endpoint.init([]))
      |> Plug.Conn.fetch_session()
      |> Plug.Conn.put_session(:account_id, 1)

    user = Map.put(user, :id, 2)

    assert_raise ExUnit.AssertionError, "expected the authenticated account to have a primary key value of: 2", fn ->
      assert_authorized_as(conn, user)
    end 
  end

  test "assert_authorized_as when not authenticated raises when account_type mismatch", %{conn: conn, admin: admin} do
    conn =
      conn
      |> Phoenix.ConnTest.bypass_through()
      |> @endpoint.call(@endpoint.init([]))
      |> Plug.Conn.fetch_session()
      |> Plug.Conn.put_session(:account_id, 1)
      |> Plug.Conn.put_session(:account_type, User)

    admin = Map.put(admin, :id, 1)

    assert_raise ExUnit.AssertionError, "expected the authenticated account to be of type: Admin", fn ->
      assert_authorized_as(conn, admin)
    end
  end

  test "assert_authorized_as does not raise when all conditions are met", %{conn: conn, user: user} do
    conn =
      conn
      |> Phoenix.ConnTest.bypass_through()
      |> @endpoint.call(@endpoint.init([]))
      |> Plug.Conn.fetch_session()
      |> Plug.Conn.put_session(:account_id, 1)
      |> Plug.Conn.put_session(:account_type, User)

    user = Map.put(user, :id, 1)
    assert_authorized_as(conn, user)
  end

  test "assert_authorized_as will not raise when account is present in `conn.assigns`", %{conn: conn, user: user} do
    conn
    |> Plug.Conn.assign(:account, user)
    |> assert_authorized_as(user)
  end

  test "assert_authorized_as will raise when account is present in `conn.assigns` but doesn't match the challenge account", %{conn: conn, user: user} do
    assert_raise ExUnit.AssertionError, "expected the account to match the assigned account in the session", fn ->
      conn
      |> Plug.Conn.assign(:account, %{})
      |> assert_authorized_as(user)
    end
  end

  test "assert_authorized_as will return the original `conn`", %{conn: conn, user: user} do
    conn = Plug.Conn.assign(conn, :account, user)

    result = assert_authorized_as(conn, user)

    assert result == conn
  end

  test "authorize_as will authenticate with a specific account", %{conn: conn, user: user}  do
    conn
    |> authorize_as(user)
    |> assert_authorized_as(user)
  end

  @doc """
  ## `require_authorization` tests

  Because this macro generates a test the best way to actually test this is to ensure
  the test doesn't raise with green paths
  """

  require_authorization :profile_path
  require_authorization :profile_path, only: [:index, :create]
  require_authorization :profile_path, roles: [:no_auth, :auth]
  require_authorization :profile_path, roles: [:no_auth, :auth], only: [:index, :create]
  require_authorization :profile_path, only: [:index, create: %{foo: "bar"}]
  require_authorization :profile_path, roles: [:no_auth, auth: &auth_conn/1]
  require_authorization :foo_path, only: [:show]
  require_authorization :bar_path, only: [:index]

  defp auth_conn(conn), do: conn
end
