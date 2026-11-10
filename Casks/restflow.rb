cask "restflow" do
  version "0.14.0"
  sha256 "2222e2c220cc4cb043b3a9c8e528d7c7b53e08a6b911e3dedccc744a39cbcfd4"

  url "https://github.com/wsgggws/RestFlow/releases/download/v#{version}/RestFlow-#{version}-arm64.app.zip"
  name "RestFlow"
  name "坐忘录"
  desc "Menu bar break timer with synchronized breaks across displays"
  homepage "https://github.com/wsgggws/RestFlow"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "RestFlow.app"
end
