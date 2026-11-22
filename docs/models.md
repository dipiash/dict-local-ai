# Models

Parakeet Ultra is the only ASR engine; Nemotron 3 fast32/fast128 handles speaker diarization. The model manager downloads Core ML assets from the FluidInference Hugging Face repositories only when the user chooses an installation. It records the resolved revision and local SHA-256 digests for every file in the selected Core ML bundles and their tokenizer or silence embedding. Subsequent inference is local; offline mode is enabled outside installation. No model weights are included in source or application archives.

Older model installation locations and alternative engines are not supported. Install the current models from Settings if the cache or receipt is invalid. Receipts from earlier builds need one explicit reinstall at the recorded revision to obtain full-file verification. Installation uses a fresh directory and switches the receipt only after the models load successfully. Existing cache files are preserved, so allow space for both copies. This repository does not remove existing user files as part of an update; users can explicitly remove local data if desired. Model outputs and speaker labels are estimates.

See [third-party notices](../THIRD_PARTY_NOTICES.md) for licenses and exact dependency revision. Review the licenses of downloaded model versions and binary dependencies before redistribution or commercial use.
