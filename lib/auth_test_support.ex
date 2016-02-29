defmodule AuthTestSupport do
  @moduledoc """
  A collection of common funcitonality to use in your Phoenix test suites.

  `use AuthTestSupport` in your test files.
  """
  @api_actions [:index, :show, :delete, :update, :create]

  @doc """
  Sign in to the session

  This function assumes that the session creation path is `session_path` and is using `post`.

  Feel free to override this function.
  """
  def sign_in(conn, creds)

  @doc """
  Assert that the current connection is authenticated as a given account

  Will run the following assertions:

  1. assert that `:account_id` value in the session is not `nil` and is equal to the `account`'s primary key value
  2. assert that `:account_type` value in the sesion is not `nil` and is equal to the `account`'s struct
  """
  def assert_authenticated_as(conn, account)
  defmacro __using__(_) do
    quote do
      import AuthTestSupport
      @before_compile AuthTestSupport
    end
  end

  defmacro __before_compile__(_) do
    quote do
      def sign_in(conn, creds),
        do: post(conn, session_path(conn, :create, creds))

      defoverridable [sign_in: 2]

      def assert_authenticated_as(conn, account) do
        module = account.__struct__
        [primary_key] = module.__schema__(:primary_key)
        primary_key_value = Map.get(account, primary_key)

        account_id = Plug.Conn.get_session(conn, :account_id)
        account_type = Plug.Conn.get_session(conn, :account_type)

        assert account_id, "expected an account_id to be set"
        assert account_id == primary_key_value, "expected the authenticated account to have a primary key value of: #{primary_key_value}"
        assert account_type, "expected an account_type to be set"
        assert account_type == module, "expected the authenticated account to be of type: #{inspect module}"
      end
    end
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
        sign_in(conn, username: "user@example.com", password: "password")
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

        for role <- unquote(role_keys) do
          for action <- unquote(action_keys) do
            {methods, params} = case action do
              :show -> {[:get], [0]}
              :delete -> {[:delete], [0]}
              :create -> {[:post], [unquote(actions)[action] || %{}]}
              :index -> {[:get], []}
              :update -> {[:put, :patch], [0, unquote(actions)[action] || %{}]}
            end

            conn = case unquote(roles)[role] do
              nil -> conn
              func -> func.(conn)
            end

            for method <- methods do
              path = cond do
                action in [:show, :delete, :update] -> unquote(path_helper)(conn, action, List.first(params))
                action in [:index, :create] -> unquote(path_helper)(conn, action)
              end

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
