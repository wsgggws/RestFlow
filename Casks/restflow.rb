cask "restflow" do
  version "0.6.0"
  sha256 "89cb42f325495a99c69a49efcd39077112b2eaac2db238cd754e6434fec1dbd9"

  url "https://github.com/wsgggws/RestFlow/releases/download/v#{version}/RestFlow-#{version}-arm64.app.zip"
  name "RestFlow"
  desc "Menu bar break timer with synchronized breaks across displays"
  homepage "https://github.com/wsgggws/RestFlow"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "RestFlow.app"
end
