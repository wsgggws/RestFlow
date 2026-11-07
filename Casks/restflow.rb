cask "restflow" do
  version "0.5.0"
  sha256 "71767ac44ad6d1d716008e1849e36274ff8d90726baaea0dd250f6fc636f8f71"

  url "https://github.com/wsgggws/RestFlow/releases/download/v#{version}/RestFlow-#{version}-arm64.app.zip"
  name "RestFlow"
  desc "Menu bar break timer with synchronized breaks across displays"
  homepage "https://github.com/wsgggws/RestFlow"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "RestFlow.app"
end
