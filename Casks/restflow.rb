cask "restflow" do
  version "0.21.0"
  sha256 "009ffa4a51b966561802a7ba94fbe44405d1c7cd51aad8a145d934c236f6b792"

  url "https://github.com/wsgggws/RestFlow/releases/download/v#{version}/RestFlow-#{version}-arm64.app.zip"
  name "RestFlow"
  name "坐忘录"
  desc "Menu bar break timer with synchronized breaks across displays"
  homepage "https://github.com/wsgggws/RestFlow"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "RestFlow.app"
end
