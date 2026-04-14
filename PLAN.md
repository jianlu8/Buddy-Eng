# EnglishBuddy iPhone 离线版 v1 方案

**Summary**
- 从空仓库启动一个原生 iPhone app，目标是做一个“受 CallAnnie 启发但不复制其品牌/素材”的离线英语陪练原型。
- 技术路线固定为 `SwiftUI + AVFoundation + Apple 本地 ASR/TTS + LiteRT-LM C++ + Gemma 4 E2B`，不走已弃用的 MediaPipe LLM Inference。
- 产品形态固定为：`1 个原创 2D 数字人角色`、`聊天/教学双模式`、`近似全双工通话感`、`快速开聊`、`英语练习 + 中文讲解`、`本地长期记忆`、`应用内下载模型`、`仅本地开发包`。
- 设备基线固定为 `iPhone 15 Pro / Pro Max 及以上，iOS 17+`。`Gemma 4 E4B` 不进入 v1。

**Implementation Changes**
- 创建一个新的原生 iOS 工程，按 4 层拆分：
  - `App/UI`：SwiftUI 界面、来电式主页、通话页、通话后反馈页、历史页、设置页。
  - `Conversation Core`：模式切换、提示词装配、记忆检索、会话状态机、反馈生成。
  - `Speech/Avatar`：麦克风采集、VAD、Apple 本地语音识别、Apple 本地语音合成、2D 角色状态驱动。
  - `Inference Bridge`：ObjC++/C++ 封装 LiteRT-LM，暴露给 Swift 的最小桥接接口。
- 近似全双工的实现不做“实时音频直喂 Gemma”。改为：
  - 常驻监听麦克风并做本地流式转写。
  - 助手说话期间继续监听用户插话。
  - 一旦检测到有效插话，立即停止 TTS、取消当前生成、把截断点之前的上下文入库，然后以新一轮用户输入继续。
  - 对用户表现为可打断、接近电话，但底层仍是快速轮转式对话。
- 模型管理固定为应用内下载：
  - 首启检查磁盘空间、网络、模型是否已存在。
  - 下载 `gemma-4-E2B-it.litertlm` 到 `Application Support/Models/`。
  - 记录版本、校验和、文件大小、最后使用时间。
  - 提供删除、重新下载、损坏恢复，不把模型打进安装包。
- 推理引擎固定为 `GPU 优先，CPU 调试回退`：
  - App 启动后预热 LiteRT-LM Engine 并常驻单例。
  - 一个重型 `Engine`，多会话轻量 `Conversation`。
  - 使用异步 token streaming 回调驱动字幕和 TTS 分段播报。
- 产品模式固定为两个：
  - `Chat`：自然闲聊优先，只轻量采集错误与用户偏好，不在通话中频繁打断。
  - `Tutor`：围绕主题练习、目标词汇、追问和纠偏，通话后输出更强的学习反馈。
- 通话后反馈页固定包含：
  - 语法问题 3 条以内。
  - 词汇替换建议 3 条以内。
  - 本次高频表达。
  - 下次建议话题。
  - 发音提示采用“识别偏差 + 目标句对齐”的词级启发式，不做 v1 的音素级评分。
- 长期记忆固定为本地结构化存储：
  - 用户画像：英语水平估计、常错点、偏好话题、学习目标。
  - 会话历史：摘要、关键句、纠错记录。
  - 词汇进度：新词、复现次数、掌握状态。
  - Persona 状态：称呼偏好、语速偏好、是否允许中文解释。
  - 每次生成前只检索压缩后的记忆摘要，避免上下文爆炸。
- 快速开聊不做首屏分级测评：
  - 首次启动只收集称呼、练习目标、是否偏向教学/聊天。
  - 前 3 次通话里被动估计 CEFR 区间并逐步修正。
- 2D 数字人固定做原创角色，不仿制 Annie：
  - 状态仅保留 `Idle / Listening / Thinking / Speaking / Interrupted / Error`。
  - 口型用 TTS 音量包络驱动，辅以呼吸、眨眼、头部轻动。
  - 不做 3D 驱动、不做真人视频脸、不做多角色系统。

**Public APIs / Interfaces / Types**
- `InferenceEngineProtocol`
  - `prepare(modelURL, backend)`
  - `startConversation(preface, memoryContext, mode)`
  - `send(text)`
  - `sendStreaming(text, onToken)`
  - `cancelCurrentResponse()`
- `SpeechPipelineProtocol`
  - `startListening()`
  - `stopListening()`
  - `onPartialTranscript`
  - `onFinalTranscript`
  - `speak(text, voiceStyle)`
  - `interruptSpeech()`
- `ConversationOrchestrator`
  - 负责 `Chat/Tutor` 模式、打断策略、提示词拼装、反馈生成、会话持久化。
- `MemoryStore`
  - `fetchPersonaSummary()`
  - `fetchLearningContext()`
  - `saveTurn()`
  - `saveSessionFeedback()`
  - `updateLearnerProfile()`
- 主要数据类型固定为：
  - `LearnerProfile`
  - `ConversationSession`
  - `ConversationTurn`
  - `FeedbackReport`
  - `VocabularyItem`
  - `CorrectionEvent`
  - `PersonaState`
  - `ModelInstallState`

**Test Plan**
- 首次启动无模型时能完成下载、校验、预热，并在二次启动时直接进入可聊状态。
- 模型文件损坏、磁盘不足、下载中断、重复下载时都有明确恢复路径。
- `iPhone 15 Pro` 上 GPU 后端可稳定初始化，首 token 与持续生成不阻塞 UI。
- 助手说话时用户插话能在 500ms 级别内打断 TTS，并安全取消当前生成。
- `Chat` 与 `Tutor` 两种模式的系统提示、追问风格、反馈页面内容显著不同。
- 无网状态下，模型已下载的设备可以完整完成多轮对话、历史查看和通话后反馈。
- 本地长期记忆能跨会话保留称呼、目标、常错点和词汇进度，但不会把完整长历史无上限塞进上下文。
- 英语对话、中文解释、历史页回看、删除记忆、重置角色偏好都可正常工作。
- 来电中断、App 退后台、耳机切换、音频路由变化、权限拒绝时状态机不崩溃。
- 热机、发热、低电量场景下会降级动画频率和 TTS 分段长度，但不丢会话。

**Assumptions**
- 当前仓库为空，按绿地项目实施。
- 参考的是 CallAnnie 的交互方向，不依赖其私有代码，也不复用其品牌、角色、美术或文案。
- 官方技术事实按当前资料锁定：2026-03-31 的 MediaPipe iOS LLM 文档已标记弃用，2026-04-02 的 LiteRT-LM 文档与 2026-04-03 的仓库版本已支持 Gemma 4 和 iOS。
- v1 不做 App Store 上架、订阅、账号体系、云同步、多角色、多语言扩展、E4B 切换、真人级全双工语音。
- “近似全双工”在 v1 中定义为“可随时插话打断的本地轮转式通话”，不是同时双向连续生成。
