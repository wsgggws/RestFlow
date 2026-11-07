cask "restflow" do
  version "0.7.0"
  sha256 "7bc74c7fd01177438130f3ede9090cdaa6d2f858a96e4c0fa0a8beb7829185cb"

  url "https://github.com/wsgggws/RestFlow/releases/download/v#{version}/RestFlow-#{version}-arm64.app.zip"
  name "RestFlow"
  desc "Menu bar break timer with synchronized breaks across displays"
  homepage "https://github.com/wsgggws/RestFlow"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "RestFlow.app"
end
