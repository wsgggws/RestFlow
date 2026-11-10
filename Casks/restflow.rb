cask "restflow" do
  version "0.15.0"
  sha256 "ea520a9a22f9675291ae8941261f6b56f6c155e680d2b1c314021087b9562b7d"

  url "https://github.com/wsgggws/RestFlow/releases/download/v#{version}/RestFlow-#{version}-arm64.app.zip"
  name "RestFlow"
  name "坐忘录"
  desc "Menu bar break timer with synchronized breaks across displays"
  homepage "https://github.com/wsgggws/RestFlow"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "RestFlow.app"
end
