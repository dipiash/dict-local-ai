# Third-party notices

Dict Local AI source: MIT (LICENSE). The application's source license does not grant rights to third-party models, binaries or assets.

## Project artwork

The project owner generated the following images with ChatGPT for Dict Local AI:

- `Resources/App/AppIcon.icns` — macOS app icon
- `Resources/App/BrandMark.png` — in-app logo
- `Resources/Installer/DMGBackground.png` — DMG installer background

## Speech models (downloaded separately)

- Parakeet Ultra: [Moondream / M87 Labs](https://huggingface.co/moondream/parakeet-ultra), based on [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). The model's stated license is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Core ML conversion: [FluidInference](https://huggingface.co/FluidInference/parakeet-ultra-coreml).
- Nemotron 3 Diarization: [NVIDIA](https://huggingface.co/nvidia/nemotron-3-diarization) and [FluidInference Core ML conversion](https://huggingface.co/FluidInference/nemotron-3-diarization-coreml). The stated model license is NVIDIA Open Model Data Weights License 1.1. Review the model card and license at the actual downloaded revision.

Weights are not distributed with this project; the user installs them at runtime. No endorsement by the model authors is implied.

## Swift dependency and system frameworks

[FluidAudio](https://github.com/FluidInference/FluidAudio) at commit `503b4bd1bbf7220882de39fe8ae6716aae4132da` is Apache-2.0. The main license and the pinned upstream notices for FastCluster, VBx and NemoTextProcessing are in `Resources/Licenses/`. Its manifest includes FastClusterWrapper, MachTaskSelfWrapper, a checksum-pinned NemoTextProcessing binary from [text-processing-rs v0.3.1](https://github.com/FluidInference/text-processing-rs/releases/tag/v0.3.1), and packaged resources. Inspect all applicable bundled third-party notices, Rust dependencies and resource licenses before redistributing a compiled app.

SQLite is a system library (public domain). Apple frameworks are provided by macOS. Build and evaluation tools (Homebrew, SwiftLint, ShellCheck, Task, Gitleaks, ds_store and mac_alias (MIT), optional pyannote.metrics and ffmpeg) are development dependencies and are not embedded in the distributed app. Their separate terms apply to their respective distributions.

Publication gate: confirm the license terms for the exact retrieved model revisions and all linked binary components. This notice is not a certification of redistribution rights.
