# ADR 0001 — Local inference and user-managed models

Status: accepted

Use Core ML and FluidAudio for Parakeet Ultra ASR and Nemotron 3 diarization. Keep model weights outside source and app bundles. Use explicit downloads, recorded revisions and verification receipts. Keep inference offline. Do not add a secondary engine for legacy compatibility. Consequence: the runtime is Apple Silicon/macOS specific; model downloads are a separate setup step.
