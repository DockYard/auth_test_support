defmodule AuthTestSupportTest do
  use ExUnit.Case
  use AuthTestSupport

  defp post(conn, _path),
    do: conn

  defp session_path(conn, _action, _params),
    do: conn

  setup_all do
    Endpoint.start_link()
    Application.load(:phoenix)
    on_exit fn -> Application.delete_env(:auth_test_support, :serve_endpoints) end
    :ok
  end

  setup do
    opts = Plug.Session.init(store: :cookie, key: "foobar", signing_salt: "foobar")
    conn =
      Phoenix.ConnTest.conn()
      |> Plug.Session.call(opts) 
      |> Plug.Conn.fetch_session()

    user = struct(User, %{})
    admin = struct(Admin, %{})
  
    {:ok, conn: conn, user: user, admin: admin}
  end

  test "assert_authenticated_as when not authenticated raises on missing account_id value", %{conn: conn, user: user} do
    assert_raise ExUnit.AssertionError, "expected an account_id to be set", fn ->
      assert_authenticated_as(conn, user)
    end
  end

  test "assert_authenticated_as when not authenticated raises when account_id mismatch", %{conn: conn, user: user} do
    conn = Plug.Conn.put_session(conn, :account_id, 1)
    user = Map.put(user, :id, 2)

    assert_raise ExUnit.AssertionError, "expected the authenticated account to have a primary key value of: 2", fn ->
      assert_authenticated_as(conn, user)
    end 
  end

  test "assert_authenticated_as when not authenticated raises when account_type mismatch", %{conn: conn, admin: admin} do
    conn =
      conn
      |> Plug.Conn.put_session(:account_id, 1)
      |> Plug.Conn.put_session(:account_type, User)
    
    admin = Map.put(admin, :id, 1)

    assert_raise ExUnit.AssertionError, "expected the authenticated account to be of type: Admin", fn ->
      assert_authenticated_as(conn, admin)
    end
  end

  test "assert_authenticated_as does not raise when all conditions are met", %{conn: conn, user: user} do
    conn =
      conn
      |> Plug.Conn.put_session(:account_id, 1)
      |> Plug.Conn.put_session(:account_type, User)
    
    user = Map.put(user, :id, 1)
    assert_authenticated_as(conn, user)
  end

  @doc """
  ## `require_authorization` tests

  Because this macro generates a test the best way to actually test this is to ensure
  the test doesn't raise with green paths
  """

  @endpoint Endpoint
  import Router.Helpers

  require_authorization :profile_path
  require_authorization :profile_path, only: [:index, :create]
  require_authorization :profile_path, roles: [:no_auth, :auth]
  require_authorization :profile_path, roles: [:no_auth, :auth], only: [:index, :create]
  require_authorization :profile_path, only: [:index, create: %{foo: "bar"}]
  require_authorization :profile_path, roles: [:no_auth, auth: &auth_conn/1]

  defp auth_conn(conn), do: conn
end
