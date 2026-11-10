cask "restflow" do
  version "0.17.0"
  sha256 "437f2a448233b00c3b3c3aee9a2a62a114783bc78c9a9085e349ca16d10eea09"

  url "https://github.com/wsgggws/RestFlow/releases/download/v#{version}/RestFlow-#{version}-arm64.app.zip"
  name "RestFlow"
  name "坐忘录"
  desc "Menu bar break timer with synchronized breaks across displays"
  homepage "https://github.com/wsgggws/RestFlow"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "RestFlow.app"
end
