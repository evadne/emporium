defmodule EmporiumWeb.LayoutView do
  use EmporiumWeb, :view
  alias Plug.Conn
  @compile {:no_warn_undefined, {Routes, :live_dashboard_path, 2}}

  defp get_title(%Conn{private: %{title: title}}), do: title
  defp get_title(%Conn{} = _), do: gettext("application.name")

  defp get_stylesheet_sources(%Conn{} = conn) do
    Enum.map(get_stylesheet_names(conn), &Routes.static_path(conn, &1))
  end

  defp get_script_sources(%Conn{} = conn) do
    Enum.map(get_script_names(conn), &Routes.static_path(conn, &1))
  end

  defp get_stylesheet_names(%Conn{private: %{stylesheet_names: names}}), do: names
  defp get_stylesheet_names(_), do: ["/assets/screen-generic.css"]

  defp get_script_names(%Conn{private: %{script_names: names}}), do: names
  defp get_script_names(_), do: ["/assets/screen-generic.js"]
end
