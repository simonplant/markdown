use std::path::{Path, PathBuf};

/// Default model filename stored in the app data directory.
const MODEL_FILENAME: &str = "markdown-ai-model.gguf";

/// Default download URL for the quantized model.
const MODEL_URL: &str =
    "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf";

/// Returns the expected model file path within the given data directory.
pub fn model_path(data_dir: &Path) -> PathBuf {
    data_dir.join(MODEL_FILENAME)
}

/// Check whether the AI model file exists and is non-empty.
pub fn is_model_available(data_dir: &Path) -> bool {
    let path = model_path(data_dir);
    path.is_file() && path.metadata().map(|m| m.len() > 0).unwrap_or(false)
}

/// Returns the download URL for the default model.
pub fn model_download_url() -> &'static str {
    MODEL_URL
}

/// AI action type, determines the prompt template used.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiAction {
    Improve,
    Summarize,
    Continue,
}

/// Build the prompt string for the given action and input text.
pub fn build_prompt(action: AiAction, text: &str, context: &str) -> String {
    match action {
        AiAction::Improve => {
            let ctx = if context.is_empty() {
                String::new()
            } else {
                format!("\n\nSurrounding context:\n{}", context)
            };
            format!(
                "[INST] You are a writing assistant. Improve the following text to make it clearer, \
                 more concise, and better written. Return ONLY the improved text, no explanations.{}\n\n\
                 Text to improve:\n{} [/INST]",
                ctx, text
            )
        }
        AiAction::Summarize => {
            format!(
                "[INST] You are a writing assistant. Summarize the following text in a concise paragraph. \
                 Return ONLY the summary, no explanations.\n\n\
                 Text to summarize:\n{} [/INST]",
                text
            )
        }
        AiAction::Continue => {
            format!(
                "[INST] You are a writing assistant. Continue writing the following text naturally, \
                 maintaining the same style and tone. Write 1-3 sentences. Return ONLY the continuation, \
                 no explanations.\n\n{} [/INST]",
                text
            )
        }
    }
}

// ---------------------------------------------------------------------------
// AI inference engine (feature-gated on "ai")
// ---------------------------------------------------------------------------

#[cfg(feature = "ai")]
mod engine {
    use super::*;
    use llama_cpp_2::context::params::LlamaContextParams;
    use llama_cpp_2::llama_backend::LlamaBackend;
    use llama_cpp_2::llama_batch::LlamaBatch;
    use llama_cpp_2::model::params::LlamaModelParams;
    use llama_cpp_2::model::{AddBos, LlamaModel};
    use llama_cpp_2::sampling::LlamaSampler;
    use std::sync::OnceLock;

    static BACKEND: OnceLock<LlamaBackend> = OnceLock::new();

    fn get_backend() -> &'static LlamaBackend {
        BACKEND.get_or_init(|| {
            LlamaBackend::init().expect("failed to initialize llama backend")
        })
    }

    /// The AI inference engine. Wraps llama.cpp model loading and text generation.
    pub struct AiEngine {
        // Model is Box::leaked so we can hold a context that borrows it.
        // This leaks memory on drop but the engine lives for the app lifetime.
        model: &'static LlamaModel,
    }

    unsafe impl Send for AiEngine {}
    unsafe impl Sync for AiEngine {}

    impl AiEngine {
        /// Load a GGUF model from the given path.
        pub fn new(model_file: &Path) -> Result<Self, String> {
            if !model_file.is_file() {
                return Err("Model file not found. Download the AI model first.".into());
            }

            let backend = get_backend();
            let model_params = LlamaModelParams::default();
            let model = LlamaModel::load_from_file(backend, model_file, &model_params)
                .map_err(|e| format!("Failed to load model: {}", e))?;

            let model: &'static LlamaModel = Box::leak(Box::new(model));

            Ok(AiEngine { model })
        }

        /// Run inference for the given action and return generated text.
        pub fn run(&self, action: AiAction, text: &str, context: &str) -> Result<String, String> {
            let prompt = build_prompt(action, text, context);
            self.generate(&prompt)
        }

        fn generate(&self, prompt: &str) -> Result<String, String> {
            let backend = get_backend();

            let ctx_params = LlamaContextParams::default()
                .with_n_ctx(std::num::NonZeroU32::new(2048));
            let mut ctx = self
                .model
                .new_context(backend, ctx_params)
                .map_err(|e| format!("Failed to create context: {}", e))?;

            // Tokenize prompt
            let tokens = self
                .model
                .str_to_token(prompt, AddBos::Always)
                .map_err(|e| format!("Tokenization failed: {}", e))?;

            if tokens.is_empty() {
                return Ok(String::new());
            }

            // Process prompt tokens in a batch
            let mut batch = LlamaBatch::new(tokens.len().max(1), 1);
            for (i, &token) in tokens.iter().enumerate() {
                let is_last = i == tokens.len() - 1;
                batch
                    .add(token, i as i32, &[0], is_last)
                    .map_err(|_| "Failed to add token to batch")?;
            }
            ctx.decode(&mut batch)
                .map_err(|e| format!("Prompt decode failed: {}", e))?;

            // Build a sampler chain: temperature -> top-p -> distribution sampling
            let mut sampler = LlamaSampler::chain_simple([
                LlamaSampler::temp(0.7),
                LlamaSampler::top_p(0.9, 1),
                LlamaSampler::dist(42),
            ]);

            // Generate tokens autoregressively
            let max_tokens: usize = 512;
            let mut output_bytes: Vec<u8> = Vec::new();
            let mut n_decoded = tokens.len();

            for _ in 0..max_tokens {
                let new_token = sampler.sample(&ctx, (batch.n_tokens() - 1) as i32);
                sampler.accept(new_token);

                if self.model.is_eog_token(new_token) {
                    break;
                }

                // Detokenize: get raw bytes for this token
                let piece = self
                    .model
                    .token_to_piece_bytes(new_token, 32, false, None)
                    .map_err(|e| format!("Detokenization failed: {}", e))?;
                output_bytes.extend_from_slice(&piece);

                // Prepare next batch with the generated token
                batch.clear();
                batch
                    .add(new_token, n_decoded as i32, &[0], true)
                    .map_err(|_| "Failed to add token to batch")?;
                ctx.decode(&mut batch)
                    .map_err(|e| format!("Decode failed: {}", e))?;

                n_decoded += 1;
            }

            String::from_utf8(output_bytes)
                .map(|s| s.trim().to_string())
                .map_err(|e| format!("UTF-8 conversion failed: {}", e))
        }
    }
}

#[cfg(feature = "ai")]
pub use engine::AiEngine;

#[cfg(not(feature = "ai"))]
pub struct AiEngine {
    _priv: (),
}

#[cfg(not(feature = "ai"))]
impl AiEngine {
    pub fn new(_model_path: &Path) -> Result<Self, String> {
        Err("AI runtime not available (compiled without 'ai' feature)".into())
    }

    pub fn run(&self, _action: AiAction, _text: &str, _context: &str) -> Result<String, String> {
        Err("AI runtime not available (compiled without 'ai' feature)".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn model_path_construction() {
        let dir = Path::new("/tmp/test-app-data");
        let path = model_path(dir);
        assert_eq!(
            path,
            PathBuf::from("/tmp/test-app-data/markdown-ai-model.gguf")
        );
    }

    #[test]
    fn model_not_available_in_nonexistent_dir() {
        assert!(!is_model_available(Path::new("/nonexistent/path")));
    }

    #[test]
    fn build_prompt_improve() {
        let prompt = build_prompt(AiAction::Improve, "bad text", "some context");
        assert!(prompt.contains("bad text"));
        assert!(prompt.contains("some context"));
        assert!(prompt.contains("[INST]"));
    }

    #[test]
    fn build_prompt_summarize() {
        let prompt = build_prompt(AiAction::Summarize, "long text here", "");
        assert!(prompt.contains("long text here"));
        assert!(prompt.contains("Summarize"));
    }

    #[test]
    fn build_prompt_continue() {
        let prompt = build_prompt(AiAction::Continue, "start of document", "");
        assert!(prompt.contains("start of document"));
        assert!(prompt.contains("Continue"));
    }

    #[test]
    fn engine_fails_without_model() {
        let result = AiEngine::new(Path::new("/nonexistent/model.gguf"));
        assert!(result.is_err());
    }

    #[test]
    fn build_prompt_improve_without_context() {
        let prompt = build_prompt(AiAction::Improve, "some text", "");
        assert!(prompt.contains("some text"));
        assert!(!prompt.contains("Surrounding context"));
    }
}
