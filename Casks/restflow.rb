cask "restflow" do
  version "0.18.0"
  sha256 "f4c3e9f82a260bed3dba05637fd0abd7b275b48ffb243e4245c7a61127b33413"

  url "https://github.com/wsgggws/RestFlow/releases/download/v#{version}/RestFlow-#{version}-arm64.app.zip"
  name "RestFlow"
  name "坐忘录"
  desc "Menu bar break timer with synchronized breaks across displays"
  homepage "https://github.com/wsgggws/RestFlow"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "RestFlow.app"
end
