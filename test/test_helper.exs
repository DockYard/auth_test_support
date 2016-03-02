ExUnit.start()

defmodule User do
  use Ecto.Schema

  schema "users" do
  end
end

defmodule Admin do
  use Ecto.Schema

  schema "admins" do
  end
end

defmodule Router do
  use Phoenix.Router

  pipeline :browser do
    plug :fetch_session
  end

  pipeline :api do
    plug :fetch_session
  end

  pipeline :other do
  end

  resources "/sessions", SessionController, only: [:create]
  resources "/profiles", ProfileController
  resources "/foos", FooController, only: [:show]
  resources "/bars", BarController, only: [:index]
end

defmodule SessionController do
  use Phoenix.Controller

  def create(conn, _params), do: resp(conn, 200, "")
end

defmodule ProfileController do
  use Phoenix.Controller

  def index(conn, _params),  do: resp(conn, 401, "")
  def show(conn, _params),   do: resp(conn, 401, "")
  def delete(conn, _params), do: resp(conn, 401, "")
  def create(conn, _params), do: resp(conn, 401, "")
  def update(conn, _params), do: resp(conn, 401, "")
end

defmodule FooController do
  use Phoenix.Controller

  def show(conn, _params), do: resp(conn, 401, "")
end

defmodule BarController do
  use Phoenix.Controller

  def index(conn, _params), do: resp(conn, 401, "")
end

Application.put_env(:auth_test_support, Endpoint, [secret_key_base: "foobar"])

defmodule Endpoint do
  use Phoenix.Endpoint, otp_app: :auth_test_support

  plug Plug.Session,
    store: :cookie,
    key: "_test",
    signing_salt: "foobar"

  plug Router
end
