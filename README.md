# TranscribeIosDemo

一个基于 SwiftUI 的 iOS 示例应用，展示如何集成 AWS Transcribe 实现语音转文字功能。支持**实时转录**和**批量离线转录**两种模式。

## 功能特性

### 实时转录 (Realtime)
- 通过设备麦克风捕获音频，实时流式发送至 AWS Transcribe Streaming
- 支持加载本地音频文件模拟实时转录（适用于模拟器调试）
- 内置 WAV 测试音频文件，开箱即用
- 自动将音频转换为 PCM 16-bit 16kHz 单声道格式
- 转录结果实时显示，区分中间结果（灰色斜体）和最终结果

### 批量转录 (Offline)
- 三步工作流：选择 S3 存储桶 → 选择音频文件 → 配置并提交任务
- 自动上传音频至 S3 并创建 Transcribe 批处理任务
- 任务列表实时展示状态（QUEUED / IN_PROGRESS / COMPLETED / FAILED）
- 任务完成后自动拉取并显示转录文本

## 技术栈

| 类别 | 技术 |
|------|------|
| UI | SwiftUI (TabView + NavigationStack) |
| 音频处理 | AVFoundation (AVAudioEngine, AVAudioConverter) |
| 云服务 | AWS SDK Swift ≥ 1.2.0 |
| 并发 | Swift async/await, AsyncThrowingStream |
| 依赖管理 | Swift Package Manager |

### AWS 服务依赖

- **AWSTranscribeStreaming** — 实时流式转录
- **AWSTranscribe** — 批量转录任务管理
- **AWSS3** — 音频文件上传与结果下载

## 项目结构

```
TranscribeIosDemo/
├── TranscribeIosDemoApp.swift       # 应用入口
├── ContentView.swift                # 主界面（Tab 导航）
├── Secrets.swift                    # AWS 凭证配置
├── Models/
│   ├── TranscriptLine.swift         # 转录文本数据模型
│   └── TranscribeError.swift        # 自定义错误类型
├── Services/
│   ├── AudioCaptureService.swift    # 麦克风音频捕获
│   ├── TranscriptionService.swift   # 实时转录服务
│   ├── S3Service.swift              # S3 文件操作
│   └── OfflineTranscriptionService.swift  # 批量转录服务
├── Views/
│   ├── MicrophoneView.swift         # 实时转录界面
│   ├── OfflineTranscribeView.swift  # 批量转录界面
│   └── TranscriptTextView.swift     # 转录文本展示组件
└── Resources/
    └── transcribe-test-file.wav     # 测试音频文件
```

## 环境要求

- Xcode 16.3+
- iOS 18.0+
- 具有以下权限的 AWS 账号：
  - Transcribe Streaming API
  - Transcribe 批处理 API
  - S3 读写权限

## 快速开始

1. **克隆项目**

   ```bash
   git clone <repository-url>
   open TranscribeIosDemo.xcodeproj
   ```

2. **配置 AWS 凭证**

   编辑 `TranscribeIosDemo/Secrets.swift`，填入你的 AWS 凭证：

   ```swift
   enum Secrets {
       static let accessKey = "YOUR_ACCESS_KEY_HERE"
       static let secretKey = "YOUR_SECRET_KEY_HERE"
   }
   ```

   > **注意**：静态凭证仅用于演示。生产环境请使用 Amazon Cognito Identity Pool。

3. **构建并运行**

   选择目标设备或模拟器，点击 Run。

   - **真机**：支持麦克风实时转录和文件转录
   - **模拟器**：仅支持文件转录（无麦克风访问）

## 注意事项

- AWS Region 默认设置为 `us-east-1`，如需更改请修改 `TranscriptionService` 和 `S3Service` 中的配置
- 实时模式下音频以 125ms 为单位分块发送
- 首次使用麦克风时，应用会请求录音权限