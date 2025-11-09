defmodule MqttApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :mqtt_app,
      version: "0.1.1",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "MQTT packet encoder/decoder",
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [{:ex_doc, "~> 0.30", only: :dev, runtime: false}]
  end

  defp package do
    [
      mantainers: ["Pepethefrogger"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Pepethefrogger/elixir_mqtt.git"}
    ]
  end
end
