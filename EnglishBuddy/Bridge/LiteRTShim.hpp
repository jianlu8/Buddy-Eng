#pragma once

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>

class LiteRTShim {
public:
  using StreamCallback = std::function<void(const std::string&, bool, const std::string&)>;

  LiteRTShim();
  ~LiteRTShim();

  bool Prepare(const std::string& model_path, bool prefer_gpu, std::string* error_message);
  bool StartConversation(const std::string& system_prompt,
                         const std::string& memory_context,
                         const std::string& mode,
                         std::string* error_message);
  bool SendTextStreaming(const std::string& input_text,
                         StreamCallback callback,
                         std::string* error_message);
  void Cancel();
  bool IsUsingStubRuntime() const;

private:
  struct StreamState;

  std::string BuildStubResponse(const std::string& input_text) const;
  std::string BuildCombinedSystemPrompt() const;
  void ResetRuntimeObjects();
  void EmitStubResponseAsync(const std::string& input_text, StreamCallback callback);

  mutable std::atomic<bool> cancelled_{false};
  std::shared_ptr<StreamState> current_stream_;
  mutable std::mutex mutex_;
  std::string model_path_;
  std::string system_prompt_;
  std::string memory_context_;
  std::string mode_ = "chat";
  bool prefer_gpu_ = true;
  bool use_stub_runtime_ = false;

  struct OpaqueRuntime;
  std::unique_ptr<OpaqueRuntime> runtime_;
};
