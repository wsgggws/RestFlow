cask "restflow" do
  version "0.13.0"
  sha256 "42de95b9bd62e10f24f6ff23cd5d32cfdc4546e6cf100d819f71100e232eb461"

  url "https://github.com/wsgggws/RestFlow/releases/download/v#{version}/RestFlow-#{version}-arm64.app.zip"
  name "RestFlow"
  name "坐忘录"
  desc "Menu bar break timer with synchronized breaks across displays"
  homepage "https://github.com/wsgggws/RestFlow"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "RestFlow.app"
end
