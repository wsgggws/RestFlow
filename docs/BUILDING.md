# 从源码构建

需要 macOS 13+、Apple Command Line Tools、Swift 5.9+；首次构建需联网获取固定版本的官方 Lottie。Intel Mac 可在本机从源码构建，公开预编译包仅提供 Apple Silicon 版本。

```sh
git clone https://github.com/wsgggws/RestFlow.git
cd RestFlow
./scripts/test.sh
./scripts/build-app.sh
open dist/RestFlow.app
```

本地 Homebrew 构建安装使用 `./scripts/install-brew.sh`，详见 [Homebrew](../Homebrew/README.md)。

内置音频位于 `Resources/Audio`，构建时直接打包；如需重新生成，运行 `python3 scripts/generate-audio.py`（仅用标准库，无外部素材）。

[开发约定](../AGENTS.md) · [验证范围](TESTING.md) · [发行流程](RELEASING.md)
