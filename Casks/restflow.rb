cask "restflow" do
  version "0.8.0"
  sha256 "00aaded6d492f1690c502ddc1c8e8243d72fa2f7e20146f11351d1a1f6504d51"

  url "https://github.com/wsgggws/RestFlow/releases/download/v#{version}/RestFlow-#{version}-arm64.app.zip"
  name "RestFlow"
  desc "Menu bar break timer with synchronized breaks across displays"
  homepage "https://github.com/wsgggws/RestFlow"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "RestFlow.app"
end
