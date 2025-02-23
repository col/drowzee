defmodule DrowzeeWeb.HomeLiveTest do
  use DrowzeeWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Index" do

    test "view home", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/")

      assert html =~ "Drowzee"
    end

  end
end
