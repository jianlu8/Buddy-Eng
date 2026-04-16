#include "LiteRTShim.hpp"

#include <chrono>
#include <filesystem>
#include <sstream>
#include <thread>
#include <utility>

#include "c/engine.h"

namespace {

constexpr char kCancelledSentinel[] = "__ENGLISH_BUDDY_CANCELLED__";

std::string EscapeJsonString(const std::string& input) {
  std::string output;
  output.reserve(input.size() + 16);

  for (const char character : input) {
    switch (character) {
      case '\\':
        output += "\\\\";
        break;
      case '"':
        output += "\\\"";
        break;
      case '\b':
        output += "\\b";
        break;
      case '\f':
        output += "\\f";
        break;
      case '\n':
        output += "\\n";
        break;
      case '\r':
        output += "\\r";
        break;
      case '\t':
        output += "\\t";
        break;
      default:
        if (static_cast<unsigned char>(character) < 0x20) {
          constexpr char hex_digits[] = "0123456789abcdef";
          output += "\\u00";
          output += hex_digits[(character >> 4) & 0x0F];
          output += hex_digits[character & 0x0F];
        } else {
          output += character;
        }
        break;
    }
  }

  return output;
}

std::string BuildTextContentJson(const std::string& text) {
  return "{\"type\":\"text\",\"text\":\"" + EscapeJsonString(text) + "\"}";
}

std::string BuildUserMessageJson(const std::string& text) {
  return "{\"role\":\"user\",\"content\":[" + BuildTextContentJson(text) + "]}";
}

bool LooksCancelled(const std::string& message) {
  return message.find("CANCELLED") != std::string::npos ||
         message.find("Cancelled") != std::string::npos ||
         message.find("cancelled") != std::string::npos;
}

}  // namespace

struct LiteRTShim::StreamState {
  StreamCallback callback;
  std::atomic<bool> cancel_requested{false};
  std::atomic<bool> finished{false};
};

struct LiteRTShim::OpaqueRuntime {
  LiteRtLmEngine* engine = nullptr;
  LiteRtLmConversation* conversation = nullptr;
};

LiteRTShim::LiteRTShim() = default;

LiteRTShim::~LiteRTShim() {
  Cancel();
  ResetRuntimeObjects();
}

bool LiteRTShim::Prepare(const std::string& model_path,
                         const std::string& cache_directory_path,
                         bool prefer_gpu,
                         std::string* error_message) {
  model_path_ = model_path;
  cache_directory_path_ = cache_directory_path;
  prefer_gpu_ = prefer_gpu;
  cancelled_ = false;
  use_stub_runtime_ = false;
  ResetRuntimeObjects();

  if (model_path.empty()) {
    if (error_message != nullptr) {
      *error_message = "Missing model path.";
    }
    return false;
  }

  runtime_ = std::make_unique<OpaqueRuntime>();

  const auto create_engine = [&](const char* backend) -> LiteRtLmEngine* {
    LiteRtLmEngineSettings* settings =
        litert_lm_engine_settings_create(model_path.c_str(), backend, nullptr, nullptr);
    if (settings == nullptr) {
      return nullptr;
    }

    // Gemma 4 E2B exposes prefill runners at 128 and 1024 tokens. Forcing 512
    // triggers magic-number patching that is unstable on the simulator runtime.
    litert_lm_engine_settings_set_max_num_tokens(settings, 1024);
    if (std::string_view(backend) == "cpu") {
      litert_lm_engine_settings_set_prefill_chunk_size(settings, 128);
    }

    std::error_code filesystem_error;
    if (!cache_directory_path_.empty()) {
      std::filesystem::create_directories(cache_directory_path_, filesystem_error);
      if (!filesystem_error) {
        litert_lm_engine_settings_set_cache_dir(settings, cache_directory_path_.c_str());
      }
    }

    LiteRtLmEngine* engine = litert_lm_engine_create(settings);
    litert_lm_engine_settings_delete(settings);
    return engine;
  };

  runtime_->engine = create_engine(prefer_gpu ? "gpu" : "cpu");
  if (runtime_->engine == nullptr && prefer_gpu) {
    prefer_gpu_ = false;
    runtime_->engine = create_engine("cpu");
  }

  if (runtime_->engine == nullptr) {
    if (error_message != nullptr) {
      *error_message = "Failed to initialize LiteRT-LM. Make sure the runtime artifacts are built and the device supports the selected backend.";
    }
    return false;
  }

  return true;
}

bool LiteRTShim::StartConversation(const std::string& system_prompt,
                                   const std::string& memory_context,
                                   const std::string& mode,
                                   std::string* error_message) {
  if (model_path_.empty()) {
    if (error_message != nullptr) {
      *error_message = "Engine is not prepared.";
    }
    return false;
  }

  system_prompt_ = system_prompt;
  memory_context_ = memory_context;
  mode_ = mode;
  cancelled_ = false;

  if (use_stub_runtime_) {
    return true;
  }

  if (runtime_ == nullptr || runtime_->engine == nullptr) {
    if (error_message != nullptr) {
      *error_message = "LiteRT-LM engine is unavailable.";
    }
    return false;
  }

  if (runtime_->conversation != nullptr) {
    litert_lm_conversation_delete(runtime_->conversation);
    runtime_->conversation = nullptr;
  }

  LiteRtLmSessionConfig* session_config = litert_lm_session_config_create();
  if (session_config == nullptr) {
    if (error_message != nullptr) {
      *error_message = "Failed to create LiteRT-LM session config.";
    }
    return false;
  }

  litert_lm_session_config_set_max_output_tokens(session_config, mode_ == "tutor" ? 512 : 384);
  LiteRtLmSamplerParams sampler_params{
      .type = kTopP,
      .top_k = 40,
      .top_p = 0.95f,
      .temperature = mode_ == "tutor" ? 0.55f : 0.7f,
      .seed = 42,
  };
  litert_lm_session_config_set_sampler_params(session_config, &sampler_params);

  const std::string system_prompt_json = BuildTextContentJson(system_prompt_);
  LiteRtLmConversationConfig* conversation_config =
      litert_lm_conversation_config_create(runtime_->engine, session_config,
                                           system_prompt_json.c_str(), nullptr,
                                           nullptr, false);
  litert_lm_session_config_delete(session_config);

  if (conversation_config == nullptr) {
    if (error_message != nullptr) {
      *error_message = "Failed to configure LiteRT-LM conversation.";
    }
    return false;
  }

  runtime_->conversation =
      litert_lm_conversation_create(runtime_->engine, conversation_config);
  litert_lm_conversation_config_delete(conversation_config);

  if (runtime_->conversation == nullptr) {
    if (error_message != nullptr) {
      *error_message = "Failed to create LiteRT-LM conversation.";
    }
    return false;
  }

  return true;
}

bool LiteRTShim::SendTextStreaming(const std::string& input_text,
                                   StreamCallback callback,
                                   std::string* error_message) {
  cancelled_ = false;

  std::shared_ptr<StreamState> stream_state;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (current_stream_ != nullptr && !current_stream_->finished.load()) {
      if (error_message != nullptr) {
        *error_message = "A LiteRT-LM response is already in progress.";
      }
      return false;
    }
    stream_state = std::make_shared<StreamState>();
    stream_state->callback = std::move(callback);
    current_stream_ = stream_state;
  }

  if (use_stub_runtime_) {
    EmitStubResponseAsync(input_text, stream_state->callback);
    return true;
  }

  if (runtime_ == nullptr || runtime_->conversation == nullptr) {
    if (error_message != nullptr) {
      *error_message = "LiteRT-LM conversation is not ready.";
    }
    stream_state->finished = true;
    return false;
  }

  const std::string message_json = BuildUserMessageJson(input_text);

  const int status = litert_lm_conversation_send_message_stream(
      runtime_->conversation, message_json.c_str(), nullptr,
      [](void* callback_data, const char* chunk, bool is_final, const char* error_message_raw) {
        auto* state = static_cast<StreamState*>(callback_data);
        if (state == nullptr) {
          return;
        }

        if (error_message_raw != nullptr) {
          std::string error(error_message_raw);
          if (state->cancel_requested.load() || LooksCancelled(error)) {
            error = kCancelledSentinel;
          }
          state->finished = true;
          state->callback("", true, error);
          return;
        }

        if (is_final) {
          state->finished = true;
          state->callback("", true, state->cancel_requested.load() ? kCancelledSentinel : "");
          return;
        }

        if (state->cancel_requested.load()) {
          return;
        }

        const std::string text = chunk != nullptr ? std::string(chunk) : std::string();
        if (!text.empty()) {
          state->callback(text, false, "");
        }
      },
      stream_state.get());

  if (status != 0) {
    stream_state->finished = true;
    if (error_message != nullptr) {
      *error_message = "Failed to start LiteRT-LM streaming generation.";
    }
    return false;
  }

  return true;
}

void LiteRTShim::Cancel() {
  cancelled_ = true;
  std::shared_ptr<StreamState> stream_state;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stream_state = current_stream_;
  }
  if (stream_state != nullptr) {
    stream_state->cancel_requested = true;
  }

  if (!use_stub_runtime_ && runtime_ != nullptr && runtime_->conversation != nullptr) {
    litert_lm_conversation_cancel_process(runtime_->conversation);
  }
}

bool LiteRTShim::IsUsingStubRuntime() const {
  return use_stub_runtime_;
}

std::string LiteRTShim::BuildStubResponse(const std::string& input_text) const {
  std::stringstream output;
  if (mode_ == "tutor") {
    output << "Let's turn that into stronger English. ";
    output << "You said: " << input_text << ". ";
    output << "Now try one clearer version with one reason and one concrete example. ";
    output << "If you get stuck, I can give you two short sentence starters in Chinese. ";
  } else {
    output << "That sounds interesting. ";
    output << "Tell me a little more about " << input_text << ". ";
    output << "I will keep my replies short so you can interrupt me anytime. ";
  }

  if (!memory_context_.empty()) {
    output << "I am also remembering your recent practice themes while we talk. ";
  }
  return output.str();
}

void LiteRTShim::ResetRuntimeObjects() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (current_stream_ != nullptr) {
    current_stream_->cancel_requested = true;
    current_stream_->finished = true;
    current_stream_.reset();
  }

  if (runtime_ != nullptr) {
    if (runtime_->conversation != nullptr) {
      litert_lm_conversation_delete(runtime_->conversation);
      runtime_->conversation = nullptr;
    }
    if (runtime_->engine != nullptr) {
      litert_lm_engine_delete(runtime_->engine);
      runtime_->engine = nullptr;
    }
  }
}

void LiteRTShim::EmitStubResponseAsync(const std::string& input_text,
                                       StreamCallback callback) {
  std::shared_ptr<StreamState> stream_state;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stream_state = current_stream_;
  }

  const std::string response = BuildStubResponse(input_text);
  std::thread([response, callback = std::move(callback), stream_state]() mutable {
    std::stringstream stream(response);
    std::string word;
    while (stream >> word) {
      if (stream_state == nullptr) {
        return;
      }
      if (stream_state->cancel_requested.load()) {
        stream_state->finished = true;
        callback("", true, kCancelledSentinel);
        return;
      }
      callback(word + " ", false, "");
      std::this_thread::sleep_for(std::chrono::milliseconds(35));
    }

    if (stream_state != nullptr) {
      stream_state->finished = true;
    }
    callback("", true, "");
  }).detach();
}
