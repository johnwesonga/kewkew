defmodule KewkewWeb.PageController do
  use KewkewWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
