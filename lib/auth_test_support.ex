defmodule AuthTestSupport do
  @moduledoc """
  A collection of common funcitonality to use in your Phoenix test suites.

  `use AuthTestSupport` in your test files.

  `use` is necessary for `authenticate` and it will import the remaining functions. If you'd
  like to use another of the other functions in isolation feel free to import them specifically.
  """
  @api_actions [:index, :show, :delete, :update, :create]

  Module.add_doc(__MODULE__, __ENV__.line + 1, :def, {:authenticate, 2}, (quote do: [conn, credentials]),
  """
  Authenticate the session with the given credentials

  This function assumes that the session creation path is `session_path` and is using `post`.

  Feel free to override this function.
  """)

  defmacro __using__(_) do
    quote do
      import AuthTestSupport
      @before_compile AuthTestSupport
    end
  end

  defmacro __before_compile__(_) do
    quote do
      @doc false
      def authenticate(conn, creds),
        do: Phoenix.ConnTest.post(conn, session_path(conn, :create, creds))

      defoverridable [authenticate: 2]
    end
  end

  @doc """
  Assert that the current connection is authenticated as a given account

  Will run the following assertions:

  1. assert that `:account_id` value in the session is not `nil` and is equal to the `account`'s primary key value
  2. assert that `:account_type` value in the sesion is not `nil` and is equal to the `account`'s struct

  The original `conn` will be returned.
  """
  def assert_authorized_as(%Plug.Conn{assigns: %{account: assigned_account}} = conn, account) do
    ExUnit.Assertions.assert assigned_account == account, "expected the account to match the assigned account in the session"
    conn
  end
  def assert_authorized_as(conn, account) do
    {account_id, account_type} = get_account_info(account)

    session_account_id = Plug.Conn.get_session(conn, :account_id)
    session_account_type = Plug.Conn.get_session(conn, :account_type)

    ExUnit.Assertions.assert session_account_id, "expected an account_id to be set"
    ExUnit.Assertions.assert session_account_id == account_id, "expected the authenticated account to have a primary key value of: #{account_id}"
    ExUnit.Assertions.assert session_account_type, "expected an account_type to be set"
    ExUnit.Assertions.assert session_account_type == account_type, "expected the authenticated account to be of type: #{inspect account_type}"

    conn
  end

  @doc """
  Refute account is authorized

  Will refute that an account is currently authorized.

  You can also pass `:anyone` as the account and this will refute that anyone is
  authorized, not just a specific account.
  """
  def refute_authorized_as(conn, account)
  def refute_authorized_as(%Plug.Conn{assigns: %{account: account}}, :anyone) do
    ExUnit.Assertions.flunk "expected not to be authorized, was as #{inspect account}"
  end
  def refute_authorized_as(%Plug.Conn{assigns: %{account: account}}, account) do
    ExUnit.Assertions.flunk "expected not to be authorized as #{inspect account}"
  end
  def refute_authorized_as(conn, :anyone) do
    session_account_id = Plug.Conn.get_session(conn, :account_id)
    session_account_type = Plug.Conn.get_session(conn, :account_type)

    ExUnit.Assertions.refute session_account_id && session_account_type, "expected not to be authorized, was with account_id: #{inspect session_account_id} and account_type: #{inspect session_account_type}"
  end
  def refute_authorized_as(conn, account) do
    {account_id, account_type} = get_account_info(account)

    session_account_id = Plug.Conn.get_session(conn, :account_id)
    session_account_type = Plug.Conn.get_session(conn, :account_type)

    ExUnit.Assertions.refute session_account_id == account_id && session_account_type == account_type, "expected not to be authorized as #{inspect account}"

    conn
  end

  @doc """
  Authorizes a connection with an account

  Equivalent to running:

      Plug.Conn.assign(conn, :account, account)

  This function differs from `authentication_as/2` as that will run the actual authentication whereas this function
  simply assigns to the `conn`. The database is not hit, no encryption checks are run.
  """
  def authorize_as(conn, account),
    do: Plug.Conn.assign(conn, :account, account)

  @doc false
  def get_account_info(account) do
    module = account.__struct__
    [primary_key] = module.__schema__(:primary_key)
    primary_key_value = Map.get(account, primary_key)

    {primary_key_value, module}
  end

  @doc """
  Macro that generates a test for asserting that RESTful actions require authorization

  The assertion being run will expect that unauthorized route access will return a `401`

  Options:

  * `:roles` takes an keyword list of role names. Keyword values can be a function reference that to manipulate the `conn` object
  * `:only` only the actions in the keyword list given. Keyword values can be a map for passing custom params to the action
  * `:except` all actions (`index, show, create, update, destroy`) except those in the keyword list. Keyword value behave similiar to `only`

  ### Examples
      require_authorization :profile_path
      require_authorization :profile_path, roles: [:no_auth, auth: &auth_conn/1]

      defp auth_conn(conn) do
        authenticate(conn, username: "user@example.com", password: "password")
      end

      require_authorization :profile_path, only: [create: %{foo: "bar"}]

  Each call to `require_authorization` only generates a single test, not multiple tests. This saves on compilation time.
  """
  defmacro require_authorization(path_helper, opts \\ []) do
    roles =
      (opts[:roles] || [:no_auth])
      |> List.wrap()
    actions = cond do
      opts[:only] -> opts[:only]
      opts[:except] -> @api_actions -- opts[:except]
      true -> @api_actions
    end

    role_keys = Enum.map roles, fn
      {role, _fun} -> role
      role -> role
    end

    role_text = Enum.map roles, fn
      {role, fun} -> "#{role} via #{inspect fun}"
      role -> role
    end

    action_keys = Enum.map actions, fn
      {action, _params} -> action
      action -> action
    end

    action_text = Enum.map actions, fn
      {action, params} -> "#{action} with #{inspect params}"
      action -> action
    end

    quote do
      test "require authentication for #{Enum.join(unquote(role_text), ", ")} on #{Enum.join(unquote(action_text), ", ")}", %{conn: conn} do
        path_helper_full = inspect(unquote({:&, [], [{:/, [], [{path_helper, [], nil}, 3]}]}))
        path_helper_module =
          Regex.run(~r/\&([\w|\.]+)?\.\w+\/\d+/, path_helper_full)
          |> List.last()
          |> Code.eval_string()
          |> elem(0)

        for role <- unquote(role_keys) do
          for action <- unquote(action_keys) do
            {methods, params} = case action do
              :show -> {[:get], [0]}
              :delete -> {[:delete], [0]}
              :create -> {[:post], [nil, unquote(actions)[action] || %{}]}
              :index -> {[:get], []}
              :update -> {[:put, :patch], [0, unquote(actions)[action] || %{}]}
            end

            conn = case unquote(roles)[role] do
              nil -> conn
              func -> func.(conn)
            end

            for method <- methods do
              args =
                [conn, action, List.first(params)]
                |> Enum.reject(&is_nil/1)

              path = apply(path_helper_module, unquote(path_helper), args)

              {conn, message} = cond do
                action in [:show, :delete, :index] ->
                  conn = Phoenix.ConnTest.dispatch(conn, @endpoint, method, path, nil)
                  message = "[#{method |> Atom.to_string() |> String.upcase()}] #{action} on #{path} expected to return 401, got: #{conn.status}"
                  {conn, message}
                action in [:create, :update] ->
                  conn = Phoenix.ConnTest.dispatch(conn, @endpoint, method, path, List.last(params))
                  message = "[#{method |> Atom.to_string() |> String.upcase()}] #{action} on #{path} with #{inspect List.last(params)} expected to return 401, got: #{conn.status}"
                  {conn, message}
              end

              assert conn.status == 401, message
            end
          end
        end
      end
    end
  end
end
