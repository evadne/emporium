defmodule EmporiumProxy do
  @otp_app Mix.Project.config()[:app]

  def get_port, do: String.to_integer(System.get_env("PORT"))
  def get_endpoints, do: Keyword.get(get_config(), :endpoints, [])
  defp get_config, do: Application.get_env(@otp_app, __MODULE__) || []
end
