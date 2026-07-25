# Privacy

Talkie has no account system, analytics, advertising, or Talkie-operated server. When a cloud feature is enabled, Talkie connects directly from your Mac to the provider you selected with your own API key. The provider's terms and retention practices apply to data it receives.

## On-device transcription

Audio stays on your Mac during transcription. The local model files are downloaded from Hugging Face, but dictated audio, transcripts, and nearby context are not sent there.

After a successfully completed dictation, Talkie attempts to delete temporary audio unless **Keep audio recordings** is enabled. Deletion is best-effort: a deletion error can leave the temporary file on your Mac. Failed or cancelled dictations, including an insertion failure after transcription, may retain audio locally for retry or recovery.

## Cloud batch transcription

After you release the dictation key, the recorded audio is sent directly from your Mac to the selected transcription provider: OpenAI or OpenRouter. The provider's terms and retention practices apply.

## Instant transcription

While you are recording, audio is streamed directly from your Mac to OpenAI's realtime transcription service. The provider's terms and retention practices apply.

## Cleanup and context

When cleanup is enabled, transcript text is sent directly to the selected cleanup provider: OpenAI or OpenRouter. Cleanup can also include dictionary terms, style instructions, and a language preference.

**Use nearby text for smart insertion** is off by default. Only when you explicitly enable it, Talkie may read a bounded portion of the focused editable field and send that nearby text to the selected cleanup provider. Secure and password fields are excluded. Nearby context is not sent to transcription and is not persisted by Talkie.

When you explicitly run a selected-text transform, the selected text and your transform instruction are sent to the selected cleanup provider.

## Providers

| Provider | When Talkie contacts it | Data sent | Official policies |
| --- | --- | --- | --- |
| OpenAI | Direct batch transcription when selected; all instant transcription; cleanup or selected-text transforms when selected | Recorded or streaming audio and transcription hints; or transcript/selected text, processing instructions, and optional nearby context | [Services Agreement](https://openai.com/policies/services-agreement/) · [Service Terms](https://openai.com/policies/service-terms/) · [API data controls](https://developers.openai.com/api/docs/guides/your-data) |
| OpenRouter | Batch transcription, cleanup, or selected-text transforms when selected; checking remaining OpenRouter credits when the Home screen appears and an OpenRouter key is saved | Recorded audio and transcription settings; transcript/selected text, processing instructions, and optional nearby context; or an authenticated credits request. OpenRouter may route model requests to the model provider you select. | [Privacy](https://openrouter.ai/privacy) · [Terms](https://openrouter.ai/terms) |
| Hugging Face | Downloading the on-device transcription model (`FluidInference/parakeet-tdt-0.6b-v3-coreml`) | Model download requests and ordinary network metadata; no dictated audio, transcripts, or nearby context | [Privacy](https://huggingface.co/privacy) · [Terms](https://huggingface.co/terms-of-service) |

Provider policies can change. Review the linked policies before using cloud features.

## Local storage

API keys are stored in the macOS Keychain. Dictation history is stored locally on your Mac unless you copy or export it. Recordings kept by choice, retained after a failed or cancelled dictation, or left after a deletion error also remain local.
