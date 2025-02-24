defmodule Drowzee.K8sConn do
  @moduledoc """
  Initializes the %K8s.Conn{} struct.
  """

  @spec get!() :: K8s.Conn.t()
  def get!() do
    get!(Application.get_env(:drowzee, __MODULE__))
  end

  @spec get!(keyword()) :: K8s.Conn.t()
  def get!(opts) do
    get!(Keyword.get(opts, :method, :kube_config), opts)
  end

  def get!(:kube_config, opts) do
    path = Keyword.get(opts, :path, "~/.kube/config")
    context = Keyword.get(opts, :context, "docker-desktop")
    {:ok, conn} = K8s.Conn.from_file(path, context: context)
    conn
  end

  def get!(:test, opts) do
    path = Keyword.get(opts, :path, "test/support/discovery.json")
    %K8s.Conn{
      discovery_driver: K8s.Discovery.Driver.File,
      discovery_opts: [config: path],
      http_provider: K8s.Client.DynamicHTTPProvider
    }
  end

  def get!(:service_account, _opts) do
    {:ok, conn} = K8s.Conn.from_service_account()
    conn
  end
end
