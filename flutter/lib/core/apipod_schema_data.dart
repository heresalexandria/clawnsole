// APIPod public per-model OpenAPI Input schemas, checked 2026-11-05.
// Source: https://www.apipod.ai/models (live model-page initialSchema).
// Integer enums normalized; upload UI count/byte limits retained.
// Offline routes are deliberately excluded.

const apipodRouteSchemas = <String, Map<String, Object?>>{
  "gemini-omni-extend": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema1,
      "image_urls": _imageUrlsSchema1,
      "model": _modelSchema1,
      "prompt": _promptSchema1,
      "resolution": _resolutionSchema1,
      "video_url": _videoUrlSchema1,
    },
    "required": ["model", "prompt", "video_url"],
  },
  "gemini-omni-flash-1.1-extend": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema1,
      "image_urls": _imageUrlsSchema1,
      "model": _modelSchema2,
      "prompt": _promptSchema2,
      "resolution": _resolutionSchema2,
      "video_url": _videoUrlSchema2,
    },
    "required": ["model", "prompt", "video_url"],
  },
  "gemini-omni-flash-1.1-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema1,
      "duration": _durationSchema1,
      "image_urls": _imageUrlsSchema2,
      "model": _modelSchema3,
      "prompt": _promptSchema2,
      "resolution": _resolutionSchema2,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "gemini-omni-flash-1.1-lite-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema1,
      "duration": _durationSchema2,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema4,
      "prompt": _promptSchema3,
      "resolution": _resolutionSchema1,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "gemini-omni-flash-1.1-lite-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema1,
      "duration": _durationSchema2,
      "image_urls": _imageUrlsSchema4,
      "model": _modelSchema5,
      "prompt": _promptSchema3,
      "resolution": _resolutionSchema1,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "gemini-omni-flash-1.1-lite-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema1,
      "duration": _durationSchema2,
      "model": _modelSchema6,
      "prompt": _promptSchema3,
      "resolution": _resolutionSchema1,
    },
    "required": ["model", "prompt"],
  },
  "gemini-omni-flash-1.1-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema1,
      "duration": _durationSchema1,
      "image_urls": _imageUrlsSchema5,
      "model": _modelSchema7,
      "prompt": _promptSchema2,
      "resolution": _resolutionSchema2,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "gemini-omni-flash-1.1-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema1,
      "duration": _durationSchema1,
      "model": _modelSchema8,
      "prompt": _promptSchema4,
      "resolution": _resolutionSchema2,
    },
    "required": ["model", "prompt"],
  },
  "gemini-omni-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema1,
      "duration": _durationSchema3,
      "image_urls": _imageUrlsSchema2,
      "model": _modelSchema9,
      "prompt": _promptSchema1,
      "resolution": _resolutionSchema1,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "gemini-omni-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema1,
      "duration": _durationSchema4,
      "image_urls": _imageUrlsSchema6,
      "model": _modelSchema10,
      "prompt": _promptSchema1,
      "resolution": _resolutionSchema1,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "gemini-omni-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema1,
      "duration": _durationSchema5,
      "model": _modelSchema11,
      "prompt": _promptSchema5,
      "resolution": _resolutionSchema1,
    },
    "required": ["model", "prompt"],
  },
  "grok-imagine-1.5-fast": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema2,
      "duration": _durationSchema6,
      "image_urls": _imageUrlsSchema7,
      "model": _modelSchema12,
      "prompt": _promptSchema1,
      "resolution": _resolutionSchema3,
    },
    "required": ["model", "prompt"],
  },
  "grok-imagine-1.5-preview": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema3,
      "duration": _durationSchema7,
      "image_url": _imageUrlSchema1,
      "model": _modelSchema13,
      "prompt": _promptSchema1,
      "resolution": _resolutionSchema4,
    },
    "required": ["model", "prompt", "image_url"],
  },
  "grok-imagine-1.5-vip": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema4,
      "duration": _durationSchema8,
      "image_url": _imageUrlSchema1,
      "model": _modelSchema14,
      "prompt": _promptSchema6,
      "resolution": _resolutionSchema5,
    },
    "required": ["model", "prompt", "image_url"],
  },
  "grok-imagine-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema5,
      "duration": _durationSchema9,
      "image_urls": _imageUrlsSchema8,
      "model": _modelSchema15,
      "prompt": _promptSchema1,
      "resolution": _resolutionSchema6,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "grok-imagine-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema5,
      "duration": _durationSchema10,
      "model": _modelSchema16,
      "prompt": _promptSchema7,
      "resolution": _resolutionSchema6,
    },
    "required": ["model", "prompt"],
  },
  "kling-2.6-motion-control": {
    "properties": {
      "character_orientation": _characterOrientationSchema1,
      "image_url": _imageUrlSchema2,
      "keep_original_sound": _keepOriginalSoundSchema1,
      "model": _modelSchema17,
      "prompt": _promptSchema8,
      "quality": _qualitySchema1,
      "video_url": _videoUrlSchema3,
    },
    "required": ["model", "prompt", "image_url", "video_url"],
  },
  "kling-3.0-i2v": {
    "properties": {
      "duration": _durationSchema11,
      "generate_audio": _generateAudioSchema1,
      "image_urls": _imageUrlsSchema9,
      "model": _modelSchema18,
      "multi_prompt": _multiPromptSchema1,
      "multi_shot": _multiShotSchema1,
      "prompt": _promptSchema9,
      "resolution": _resolutionSchema7,
    },
    "required": ["model", "image_urls"],
  },
  "kling-3.0-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema6,
      "duration": _durationSchema11,
      "generate_audio": _generateAudioSchema2,
      "kling_elements": _klingElementsSchema1,
      "model": _modelSchema19,
      "multi_prompt": _multiPromptSchema2,
      "multi_shot": _multiShotSchema2,
      "prompt": _promptSchema9,
      "resolution": _resolutionSchema8,
    },
    "required": ["model"],
  },
  "kling-4.0-i2v": {
    "properties": {
      "duration": _durationSchema12,
      "image_urls": _imageUrlsSchema3,
      "keyframe_urls": _keyframeUrlsSchema1,
      "model": _modelSchema20,
      "prompt": _promptSchema10,
      "resolution": _resolutionSchema1,
    },
    "required": ["model", "prompt"],
  },
  "kling-4.0-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema7,
      "duration": _durationSchema12,
      "image_urls": _imageUrlsSchema10,
      "keep_original_sound": _keepOriginalSoundSchema2,
      "kling_elements": _klingElementsSchema2,
      "model": _modelSchema21,
      "prompt": _promptSchema10,
      "resolution": _resolutionSchema1,
      "video_urls": _videoUrlsSchema1,
      "voices": _voicesSchema1,
    },
    "required": ["model", "prompt"],
  },
  "kling-4.0-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema8,
      "duration": _durationSchema12,
      "model": _modelSchema22,
      "prompt": _promptSchema10,
      "resolution": _resolutionSchema1,
    },
    "required": ["model", "prompt"],
  },
  "minimax-h3-i2v": {
    "properties": {
      "duration": _durationSchema13,
      "first_frame_image": _imageUrlSchema1,
      "last_frame_image": _imageUrlSchema1,
      "model": _modelSchema23,
      "prompt": _promptSchema11,
      "resolution": _resolutionSchema9,
    },
    "required": ["model", "prompt", "duration", "resolution"],
  },
  "minimax-h3-lite-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema9,
      "duration": _durationSchema14,
      "image_urls": _imageUrlsSchema11,
      "model": _modelSchema24,
      "prompt": _promptSchema12,
      "resolution": _resolutionSchema10,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "minimax-h3-lite-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema10,
      "audio_urls": _audioUrlsSchema1,
      "duration": _durationSchema15,
      "image_urls": _imageUrlsSchema12,
      "model": _modelSchema25,
      "prompt": _promptSchema11,
      "resolution": _resolutionSchema11,
      "video_urls": _videoUrlsSchema2,
    },
    "required": ["model", "prompt"],
  },
  "minimax-h3-lite-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema11,
      "duration": _durationSchema14,
      "model": _modelSchema26,
      "prompt": _promptSchema12,
      "resolution": _resolutionSchema10,
    },
    "required": ["model", "prompt"],
  },
  "minimax-h3-max-i2v": {
    "properties": {
      "duration": _durationSchema16,
      "image_urls": _imageUrlsSchema13,
      "model": _modelSchema27,
      "prompt": _promptSchema13,
      "prompt_expansion_mode": _promptExpansionModeSchema1,
      "resolution": _resolutionSchema12,
    },
    "required": ["model", "prompt"],
  },
  "minimax-h3-max-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema12,
      "duration": _durationSchema16,
      "model": _modelSchema28,
      "prompt": _promptSchema13,
      "prompt_expansion_mode": _promptExpansionModeSchema2,
      "resolution": _resolutionSchema12,
    },
    "required": ["model", "prompt"],
  },
  "minimax-h3-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema13,
      "audio_urls": _audioUrlsSchema2,
      "duration": _durationSchema17,
      "image_urls": _imageUrlsSchema14,
      "model": _modelSchema29,
      "prompt": _promptSchema11,
      "resolution": _resolutionSchema9,
      "video_urls": _videoUrlsSchema3,
    },
    "required": ["model", "prompt", "duration"],
  },
  "minimax-h3-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema14,
      "duration": _durationSchema17,
      "model": _modelSchema30,
      "prompt": _promptSchema14,
      "resolution": _resolutionSchema9,
    },
    "required": ["model", "prompt", "resolution", "duration", "aspect_ratio"],
  },
  "motion-control-m1": {
    "properties": {
      "image_url": _imageUrlSchema1,
      "model": _modelSchema31,
      "video_url": _imageUrlSchema1,
    },
    "required": ["model", "image_url", "video_url"],
  },
  "muse-video-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema15,
      "duration": _durationSchema18,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema32,
      "prompt": _promptSchema15,
      "resolution": _resolutionSchema13,
    },
    "required": ["model", "prompt"],
  },
  "muse-video-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema15,
      "duration": _durationSchema18,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema15,
      "model": _modelSchema33,
      "prompt": _promptSchema6,
      "resolution": _resolutionSchema13,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "muse-video-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema15,
      "duration": _durationSchema18,
      "generate_audio": _generateAudioSchema3,
      "model": _modelSchema34,
      "prompt": _promptSchema6,
      "resolution": _resolutionSchema13,
    },
    "required": ["model", "prompt"],
  },
  "seedance-1.0-lite-i2v-ref": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema16,
      "callback_url": _imageUrlSchema1,
      "duration": _durationSchema19,
      "image_urls": _imageUrlsSchema16,
      "model": _modelSchema35,
      "prompt": _promptSchema16,
      "resolution": _resolutionSchema3,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-1.0-lite-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema16,
      "camera_fixed": _cameraFixedSchema1,
      "duration": _durationSchema19,
      "image_urls": _imageUrlsSchema17,
      "model": _modelSchema36,
      "prompt": _promptSchema16,
      "resolution": _resolutionSchema14,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-1.0-lite-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema17,
      "camera_fixed": _cameraFixedSchema2,
      "duration": _durationSchema19,
      "model": _modelSchema37,
      "prompt": _imageUrlSchema1,
      "resolution": _resolutionSchema5,
    },
    "required": ["model", "prompt"],
  },
  "seedance-1.0-pro-fast-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema18,
      "camera_fixed": _cameraFixedSchema2,
      "duration": _durationSchema19,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema38,
      "prompt": _promptSchema16,
      "resolution": _resolutionSchema5,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-1.0-pro-fast-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema19,
      "camera_fixed": _cameraFixedSchema2,
      "duration": _durationSchema19,
      "model": _modelSchema39,
      "prompt": _promptSchema16,
      "resolution": _resolutionSchema15,
    },
    "required": ["model", "prompt"],
  },
  "seedance-1.0-pro-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema20,
      "camera_fixed": _cameraFixedSchema2,
      "duration": _durationSchema19,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema40,
      "prompt": _promptSchema16,
      "resolution": _resolutionSchema15,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-1.0-pro-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema21,
      "camera_fixed": _cameraFixedSchema2,
      "duration": _durationSchema19,
      "model": _modelSchema41,
      "prompt": _promptSchema16,
      "resolution": _resolutionSchema15,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-fast-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema22,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema4,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema42,
      "prompt": _promptSchema17,
      "resolution": _resolutionSchema16,
      "web_search": _webSearchSchema1,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-2.0-fast-lite-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema22,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema4,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema43,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema17,
      "watermark": _watermarkSchema1,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-2.0-fast-lite-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "audio_urls": _audioUrlsSchema3,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "image_urls": _imageUrlsSchema18,
      "model": _modelSchema44,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema13,
      "video_urls": _videoUrlsSchema4,
      "watermark": _watermarkSchema2,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-fast-lite-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema24,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "model": _modelSchema45,
      "prompt": _promptSchema19,
      "resolution": _resolutionSchema17,
      "watermark": _watermarkSchema3,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-fast-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "audio_urls": _audioUrlsSchema3,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "image_urls": _imageUrlsSchema18,
      "model": _modelSchema46,
      "prompt": _promptSchema17,
      "resolution": _resolutionSchema3,
      "video_urls": _videoUrlsSchema4,
      "web_search": _webSearchSchema2,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-fast-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema24,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "model": _modelSchema47,
      "prompt": _promptSchema20,
      "resolution": _resolutionSchema16,
      "web_search": _webSearchSchema1,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema22,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema4,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema48,
      "prompt": _promptSchema17,
      "resolution": _resolutionSchema18,
      "return_last_frame": _returnLastFrameSchema1,
      "watermark": _watermarkSchema1,
      "web_search": _webSearchSchema1,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-2.0-lite-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "duration": _durationSchema21,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema49,
      "prompt": _promptSchema18,
      "real_person": _realPersonSchema1,
      "resolution": _resolutionSchema13,
      "return_last_frame": _cameraFixedSchema2,
      "watermark": _cameraFixedSchema2,
      "web_search": _cameraFixedSchema2,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-2.0-lite-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "audio_urls": _audioUrlsSchema3,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "image_urls": _imageUrlsSchema18,
      "model": _modelSchema50,
      "prompt": _promptSchema17,
      "real_person": _realPersonSchema1,
      "resolution": _resolutionSchema13,
      "return_last_frame": _returnLastFrameSchema2,
      "video_urls": _videoUrlsSchema4,
      "watermark": _cameraFixedSchema2,
      "web_search": _webSearchSchema2,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-lite-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "duration": _durationSchema21,
      "generate_audio": _generateAudioSchema3,
      "model": _modelSchema51,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema13,
      "return_last_frame": _cameraFixedSchema2,
      "watermark": _cameraFixedSchema2,
      "web_search": _cameraFixedSchema2,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-mini-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema22,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema4,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema52,
      "prompt": _promptSchema17,
      "resolution": _resolutionSchema16,
      "web_search": _webSearchSchema1,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-2.0-mini-lite-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema22,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema4,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema53,
      "prompt": _promptSchema17,
      "resolution": _resolutionSchema17,
      "watermark": _watermarkSchema4,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-2.0-mini-lite-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "audio_urls": _audioUrlsSchema3,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "image_urls": _imageUrlsSchema18,
      "model": _modelSchema54,
      "prompt": _promptSchema17,
      "resolution": _resolutionSchema13,
      "video_urls": _videoUrlsSchema4,
      "watermark": _watermarkSchema4,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-mini-lite-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema24,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "model": _modelSchema55,
      "prompt": _promptSchema20,
      "resolution": _resolutionSchema17,
      "watermark": _watermarkSchema4,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-mini-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "audio_urls": _audioUrlsSchema3,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "image_urls": _imageUrlsSchema18,
      "model": _modelSchema56,
      "prompt": _promptSchema17,
      "resolution": _resolutionSchema3,
      "video_urls": _videoUrlsSchema4,
      "web_search": _webSearchSchema2,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-mini-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema24,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "model": _modelSchema57,
      "prompt": _promptSchema20,
      "resolution": _resolutionSchema16,
      "web_search": _webSearchSchema1,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "audio_urls": _audioUrlsSchema3,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "image_urls": _imageUrlsSchema18,
      "model": _modelSchema58,
      "prompt": _promptSchema17,
      "resolution": _resolutionSchema19,
      "return_last_frame": _returnLastFrameSchema2,
      "video_urls": _videoUrlsSchema4,
      "watermark": _cameraFixedSchema2,
      "web_search": _webSearchSchema2,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-spicy-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema22,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema4,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema59,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema18,
      "watermark": _watermarkSchema1,
      "web_search": _webSearchSchema1,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-2.0-spicy-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "audio_urls": _audioUrlsSchema3,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "image_urls": _imageUrlsSchema18,
      "model": _modelSchema60,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema19,
      "video_urls": _videoUrlsSchema4,
      "watermark": _cameraFixedSchema2,
      "web_search": _webSearchSchema2,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-spicy-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema24,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "model": _modelSchema61,
      "prompt": _promptSchema21,
      "resolution": _resolutionSchema18,
      "watermark": _watermarkSchema3,
      "web_search": _webSearchSchema1,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema24,
      "duration": _durationSchema20,
      "generate_audio": _generateAudioSchema5,
      "model": _modelSchema62,
      "prompt": _promptSchema17,
      "resolution": _resolutionSchema18,
      "return_last_frame": _returnLastFrameSchema1,
      "watermark": _watermarkSchema3,
      "web_search": _webSearchSchema1,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-x-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema25,
      "audio_urls": _audioUrlsSchema4,
      "duration": _durationSchema22,
      "image_urls": _imageUrlsSchema19,
      "model": _modelSchema63,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema13,
      "video_urls": _videoUrlsSchema5,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.0-x-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema26,
      "duration": _durationSchema22,
      "model": _modelSchema64,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema17,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.5-draft": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "audio_urls": _audioUrlsSchema5,
      "draft_task_id": _draftTaskIdSchema1,
      "duration": _durationSchema23,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema20,
      "model": _modelSchema65,
      "output_format": _outputFormatSchema1,
      "prompt": _promptSchema22,
      "resolution": _resolutionSchema20,
      "video_urls": _audioUrlsSchema5,
    },
    "required": ["model", "resolution"],
  },
  "seedance-2.5-edit": {
    "properties": {
      "audio_urls": _audioUrlsSchema5,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema20,
      "model": _modelSchema66,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema5,
      "video_urls": _videoUrlsSchema6,
      "web_search": _cameraFixedSchema2,
    },
    "required": ["model", "prompt", "video_urls"],
  },
  "seedance-2.5-extend": {
    "properties": {
      "audio_urls": _audioUrlsSchema5,
      "duration": _durationSchema23,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema20,
      "model": _modelSchema67,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema5,
      "video_urls": _videoUrlsSchema7,
      "web_search": _cameraFixedSchema2,
    },
    "required": ["model", "prompt", "video_urls"],
  },
  "seedance-2.5-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema27,
      "duration": _durationSchema23,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema68,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema5,
      "web_search": _cameraFixedSchema2,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-2.5-lite-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "duration": _durationSchema23,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema69,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema13,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-2.5-lite-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "audio_urls": _audioUrlsSchema5,
      "duration": _durationSchema23,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema20,
      "model": _modelSchema70,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema13,
      "video_urls": _audioUrlsSchema5,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.5-lite-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "duration": _durationSchema23,
      "generate_audio": _generateAudioSchema3,
      "model": _modelSchema71,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema13,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.5-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "audio_urls": _audioUrlsSchema5,
      "duration": _durationSchema23,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema20,
      "model": _modelSchema72,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema5,
      "video_urls": _audioUrlsSchema5,
      "web_search": _cameraFixedSchema2,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.5-spicy-edit": {
    "properties": {
      "audio_urls": _audioUrlsSchema5,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema20,
      "model": _modelSchema73,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema5,
      "video_urls": _videoUrlsSchema6,
      "web_search": _cameraFixedSchema2,
    },
    "required": ["model", "prompt", "video_urls"],
  },
  "seedance-2.5-spicy-extend": {
    "properties": {
      "audio_urls": _audioUrlsSchema5,
      "duration": _durationSchema23,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema20,
      "model": _modelSchema74,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema5,
      "video_urls": _videoUrlsSchema7,
      "web_search": _cameraFixedSchema2,
    },
    "required": ["model", "prompt", "video_urls"],
  },
  "seedance-2.5-spicy-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema27,
      "duration": _durationSchema23,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema75,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema5,
      "web_search": _cameraFixedSchema2,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "seedance-2.5-spicy-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "audio_urls": _audioUrlsSchema5,
      "duration": _durationSchema23,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema20,
      "model": _modelSchema76,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema5,
      "video_urls": _audioUrlsSchema5,
      "web_search": _cameraFixedSchema2,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.5-spicy-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "duration": _durationSchema23,
      "generate_audio": _generateAudioSchema3,
      "model": _modelSchema77,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema5,
      "web_search": _cameraFixedSchema2,
    },
    "required": ["model", "prompt"],
  },
  "seedance-2.5-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema23,
      "duration": _durationSchema23,
      "generate_audio": _generateAudioSchema3,
      "model": _modelSchema78,
      "prompt": _promptSchema18,
      "resolution": _resolutionSchema5,
      "web_search": _cameraFixedSchema2,
    },
    "required": ["model", "prompt"],
  },
  "veo3-1-fast-4k": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema28,
      "image_urls": _imageUrlsSchema21,
      "model": _modelSchema79,
      "prompt": _promptSchema23,
    },
    "required": ["model", "prompt"],
  },
  "veo3-1-fast-ref": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema28,
      "image_urls": _imageUrlsSchema3,
      "model": _modelSchema80,
      "prompt": _promptSchema24,
      "resolution": _resolutionSchema1,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "veo3-1-fast": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema28,
      "image_urls": _imageUrlsSchema22,
      "model": _modelSchema81,
      "prompt": _promptSchema24,
      "resolution": _resolutionSchema1,
    },
    "required": ["model", "prompt"],
  },
  "veo3-1-lite-4k": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema28,
      "image_urls": _imageUrlsSchema21,
      "model": _modelSchema82,
      "prompt": _promptSchema23,
    },
    "required": ["model", "prompt"],
  },
  "veo3-1-lite": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema28,
      "image_urls": _imageUrlsSchema21,
      "model": _modelSchema83,
      "prompt": _promptSchema25,
      "resolution": _resolutionSchema1,
    },
    "required": ["model", "prompt"],
  },
  "veo3-1-quality-4k": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema28,
      "image_urls": _imageUrlsSchema21,
      "model": _modelSchema84,
      "prompt": _promptSchema26,
    },
    "required": ["model", "prompt"],
  },
  "veo3-1-quality": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema28,
      "image_urls": _imageUrlsSchema22,
      "model": _modelSchema85,
      "prompt": _promptSchema27,
      "resolution": _resolutionSchema1,
    },
    "required": ["model", "prompt"],
  },
  "wan2.7-i2v": {
    "properties": {
      "audio_url": _audioUrlSchema1,
      "duration": _durationSchema24,
      "image_urls": _imageUrlsSchema23,
      "model": _modelSchema86,
      "negative_prompt": _negativePromptSchema1,
      "prompt": _promptSchema28,
      "prompt_extend": _promptExtendSchema1,
      "resolution": _resolutionSchema21,
      "video_url": _videoUrlSchema4,
      "watermark": _watermarkSchema5,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "wan2.7-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema29,
      "audio_url": _audioUrlSchema2,
      "duration": _durationSchema24,
      "model": _modelSchema87,
      "negative_prompt": _negativePromptSchema2,
      "prompt": _promptSchema29,
      "prompt_extend": _promptExtendSchema2,
      "resolution": _resolutionSchema22,
      "watermark": _watermarkSchema6,
    },
    "required": ["model", "prompt"],
  },
  "wan2.7-videoedit": {
    "properties": {
      "audio_setting": _audioSettingSchema1,
      "duration": _durationSchema25,
      "image_urls": _imageUrlsSchema24,
      "model": _modelSchema88,
      "negative_prompt": _negativePromptSchema3,
      "prompt": _promptSchema30,
      "prompt_extend": _promptExtendSchema3,
      "resolution": _resolutionSchema23,
      "video_url": _videoUrlSchema5,
      "watermark": _watermarkSchema5,
    },
    "required": ["model", "prompt", "video_url"],
  },
  "wan3.0-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema30,
      "duration": _durationSchema26,
      "first_frame_image": _firstFrameImageSchema1,
      "generate_audio": _generateAudioSchema3,
      "last_frame_image": _lastFrameImageSchema1,
      "model": _modelSchema89,
      "prompt": _promptSchema31,
      "resolution": _resolutionSchema24,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model"],
  },
  "wan3.0-prime-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema30,
      "duration": _durationSchema26,
      "first_frame_image": _firstFrameImageSchema1,
      "generate_audio": _generateAudioSchema3,
      "last_frame_image": _lastFrameImageSchema1,
      "model": _modelSchema90,
      "prompt": _promptSchema31,
      "resolution": _resolutionSchema24,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model"],
  },
  "wan3.0-prime-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema30,
      "audio_urls": _audioUrlsSchema6,
      "duration": _durationSchema27,
      "file_url": _fileUrlSchema1,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema25,
      "link_url": _linkUrlSchema1,
      "model": _modelSchema91,
      "prompt": _promptSchema32,
      "resolution": _resolutionSchema24,
      "video_urls": _videoUrlsSchema8,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model"],
  },
  "wan3.0-prime-spicy-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema30,
      "duration": _durationSchema26,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema26,
      "model": _modelSchema92,
      "prompt": _promptSchema33,
      "prompt_extend": _promptExtendSchema4,
      "resolution": _resolutionSchema24,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model", "prompt", "image_urls"],
  },
  "wan3.0-prime-spicy-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema30,
      "audio_urls": _audioUrlsSchema6,
      "duration": _durationSchema26,
      "file_url": _fileUrlSchema1,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema25,
      "link_url": _linkUrlSchema1,
      "model": _modelSchema93,
      "prompt": _promptSchema32,
      "prompt_extend": _promptExtendSchema4,
      "resolution": _resolutionSchema24,
      "video_urls": _videoUrlsSchema8,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model"],
  },
  "wan3.0-prime-spicy-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema31,
      "duration": _durationSchema28,
      "generate_audio": _generateAudioSchema6,
      "model": _modelSchema94,
      "prompt": _promptSchema34,
      "prompt_extend": _promptExtendSchema5,
      "resolution": _resolutionSchema25,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model", "prompt"],
  },
  "wan3.0-prime-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema31,
      "duration": _durationSchema28,
      "generate_audio": _generateAudioSchema6,
      "model": _modelSchema95,
      "prompt": _promptSchema34,
      "resolution": _resolutionSchema25,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model", "prompt"],
  },
  "wan3.0-pro-spicy-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema30,
      "duration": _durationSchema26,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema26,
      "model": _modelSchema96,
      "prompt": _promptSchema31,
      "prompt_extend": _promptExtendSchema4,
      "resolution": _resolutionSchema26,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model", "image_urls"],
  },
  "wan3.0-pro-spicy-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema30,
      "audio_urls": _audioUrlsSchema6,
      "duration": _durationSchema26,
      "file_url": _fileUrlSchema1,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema25,
      "link_url": _linkUrlSchema1,
      "model": _modelSchema97,
      "prompt": _promptSchema32,
      "prompt_extend": _promptExtendSchema4,
      "resolution": _resolutionSchema26,
      "video_urls": _videoUrlsSchema8,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model"],
  },
  "wan3.0-pro-spicy-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema31,
      "duration": _durationSchema28,
      "generate_audio": _generateAudioSchema6,
      "model": _modelSchema98,
      "prompt": _promptSchema34,
      "prompt_extend": _promptExtendSchema4,
      "resolution": _resolutionSchema26,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model", "prompt"],
  },
  "wan3.0-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema30,
      "audio_urls": _audioUrlsSchema6,
      "duration": _durationSchema27,
      "file_url": _fileUrlSchema1,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema25,
      "link_url": _linkUrlSchema1,
      "model": _modelSchema99,
      "prompt": _promptSchema32,
      "resolution": _resolutionSchema24,
      "video_urls": _videoUrlsSchema8,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model"],
  },
  "wan3.0-spicy-i2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema30,
      "duration": _durationSchema26,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema26,
      "model": _modelSchema100,
      "prompt": _promptSchema31,
      "prompt_extend": _promptExtendSchema4,
      "resolution": _resolutionSchema24,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model", "image_urls"],
  },
  "wan3.0-spicy-r2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema30,
      "audio_urls": _audioUrlsSchema6,
      "duration": _durationSchema26,
      "file_url": _fileUrlSchema1,
      "generate_audio": _generateAudioSchema3,
      "image_urls": _imageUrlsSchema25,
      "link_url": _linkUrlSchema1,
      "model": _modelSchema101,
      "prompt": _promptSchema32,
      "prompt_extend": _promptExtendSchema4,
      "resolution": _resolutionSchema24,
      "video_urls": _videoUrlsSchema8,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model"],
  },
  "wan3.0-spicy-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema31,
      "duration": _durationSchema28,
      "generate_audio": _generateAudioSchema6,
      "model": _modelSchema102,
      "prompt": _promptSchema34,
      "prompt_extend": _promptExtendSchema4,
      "resolution": _resolutionSchema25,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model", "prompt"],
  },
  "wan3.0-t2v": {
    "properties": {
      "aspect_ratio": _aspectRatioSchema31,
      "duration": _durationSchema28,
      "generate_audio": _generateAudioSchema6,
      "model": _modelSchema103,
      "prompt": _promptSchema34,
      "resolution": _resolutionSchema25,
      "watermark": _cameraFixedSchema2,
    },
    "required": ["model", "prompt"],
  },
};

const _aspectRatioSchema1 = <String, Object?>{
  "type": "string",
  "enum": ["16:9", "9:16"],
  "default": "16:9",
};
const _imageUrlsSchema1 = <String, Object?>{
  "type": "array",
  "description":
      "Optional,you can provide 0-5 reference images to extend video.",
  "maxItems": 5,
  "maxBytes": 5242880,
};
const _modelSchema1 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "gemini-omni-extend",
};
const _promptSchema1 = <String, Object?>{
  "type": "string",
  "default": "",
  "maxLength": 4000,
};
const _resolutionSchema1 = <String, Object?>{
  "type": "string",
  "enum": ["720p", "1080p"],
  "default": "720p",
};
const _videoUrlSchema1 = <String, Object?>{
  "type": "string",
  "description":
      "Video to be edited. The duration of the output video follows that of the source video. If the source video lasts more than 10 seconds, the output video will be capped at 10 seconds.",
};
const _modelSchema2 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "gemini-omni-flash-1.1-extend",
};
const _promptSchema2 = <String, Object?>{
  "type": "string",
  "default": "",
  "maxLength": 20000,
};
const _resolutionSchema2 = <String, Object?>{
  "type": "string",
  "enum": ["360p", "720p", "1080p", "4k"],
  "default": "720p",
};
const _videoUrlSchema2 = <String, Object?>{
  "type": "string",
  "description":
      "Source video to continue. Only the first 10 seconds of the source video are used as continuation context.",
};
const _durationSchema1 = <String, Object?>{
  "type": "integer",
  "description": "Output video duration in seconds (4, 6, 8 or 10).",
  "enum": [4, 6, 8, 10],
  "default": 10,
};
const _imageUrlsSchema2 = <String, Object?>{
  "type": "array",
  "description":
      "First and last frame urls, first frame image is must be provided.",
  "default": "",
  "maxBytes": 5242880,
};
const _modelSchema3 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "gemini-omni-flash-1.1-i2v",
};
const _durationSchema2 = <String, Object?>{
  "type": "integer",
  "enum": [10],
  "default": 10,
};
const _imageUrlsSchema3 = <String, Object?>{"type": "array"};
const _modelSchema4 = <String, Object?>{
  "type": "string",
  "const": "gemini-omni-flash-1.1-lite-i2v",
};
const _promptSchema3 = <String, Object?>{
  "type": "string",
  "default": "",
  "minLength": 1,
  "maxLength": 30000,
};
const _imageUrlsSchema4 = <String, Object?>{"type": "array", "maxItems": 7};
const _modelSchema5 = <String, Object?>{
  "type": "string",
  "const": "gemini-omni-flash-1.1-lite-r2v",
};
const _modelSchema6 = <String, Object?>{
  "type": "string",
  "const": "gemini-omni-flash-1.1-lite-t2v",
};
const _imageUrlsSchema5 = <String, Object?>{
  "type": "array",
  "description": "Reference image URLs (1-7).",
  "default": "",
  "maxItems": 5,
  "maxBytes": 5242880,
};
const _modelSchema7 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "gemini-omni-flash-1.1-r2v",
};
const _modelSchema8 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "gemini-omni-flash-1.1-t2v",
};
const _promptSchema4 = <String, Object?>{
  "type": "string",
  "default": "A cinematic shot of a robot exploring a neon city at night",
  "maxLength": 20000,
};
const _durationSchema3 = <String, Object?>{
  "type": "integer",
  "description": "Output video duration,current only support 10s.",
  "enum": [10],
  "default": 10,
};
const _modelSchema9 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "gemini-omni-i2v",
};
const _durationSchema4 = <String, Object?>{
  "type": "integer",
  "description": "Video duration,current only support 10s.",
  "enum": [10],
  "default": 10,
};
const _imageUrlsSchema6 = <String, Object?>{
  "type": "array",
  "default": "",
  "maxItems": 5,
  "maxBytes": 5242880,
};
const _modelSchema10 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "gemini-omni-r2v",
};
const _durationSchema5 = <String, Object?>{
  "type": "integer",
  "description": "Video output duration, current only support 10s.",
  "enum": [10],
  "default": 10,
};
const _modelSchema11 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "gemini-omni-t2v",
};
const _promptSchema5 = <String, Object?>{
  "type": "string",
  "default": "A cinematic shot of a robot exploring a neon city at night",
  "maxLength": 4000,
};
const _aspectRatioSchema2 = <String, Object?>{
  "type": "string",
  "enum": ["1:1", "9:16", "16:9", "3:2", "2:3"],
  "default": "16:9",
};
const _durationSchema6 = <String, Object?>{
  "type": "integer",
  "default": 10,
  "minimum": 6,
  "maximum": 30,
};
const _imageUrlsSchema7 = <String, Object?>{
  "type": "array",
  "description": "Optional, up to 7 reference images are supported.",
  "maxItems": 7,
};
const _modelSchema12 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "grok-imagine-1.5-fast",
};
const _resolutionSchema3 = <String, Object?>{
  "type": "string",
  "enum": ["480p", "720p"],
  "default": "720p",
};
const _aspectRatioSchema3 = <String, Object?>{
  "type": "string",
  "description": "Output video width height aspect ratio",
  "enum": ["1:1", "16:9", "9:16"],
  "default": "16:9",
};
const _durationSchema7 = <String, Object?>{
  "type": "integer",
  "description": "Output video length.",
  "default": 10,
  "minimum": 1,
  "maximum": 15,
};
const _imageUrlSchema1 = <String, Object?>{"type": "string", "default": ""};
const _modelSchema13 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "grok-imagine-1.5-preview",
};
const _resolutionSchema4 = <String, Object?>{
  "type": "string",
  "description": "Output resolution. Currently only 720p is supported.",
  "enum": ["480p", "720p"],
  "default": "720p",
};
const _aspectRatioSchema4 = <String, Object?>{
  "type": "string",
  "enum": ["1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3"],
  "default": "16:9",
};
const _durationSchema8 = <String, Object?>{
  "type": "integer",
  "default": 10,
  "minimum": 1,
  "maximum": 15,
};
const _modelSchema14 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "grok-imagine-1.5-vip",
};
const _promptSchema6 = <String, Object?>{
  "type": "string",
  "default": "",
  "minLength": 1,
  "maxLength": 4000,
};
const _resolutionSchema5 = <String, Object?>{
  "type": "string",
  "enum": ["480p", "720p", "1080p"],
  "default": "720p",
};
const _aspectRatioSchema5 = <String, Object?>{
  "type": "string",
  "enum": ["2:3", "3:2", "1:1", "16:9", "9:16"],
  "default": "16:9",
};
const _durationSchema9 = <String, Object?>{
  "type": "integer",
  "enum": [6, 10, 15],
  "default": 6,
  "minimum": 6,
  "maximum": 30,
};
const _imageUrlsSchema8 = <String, Object?>{
  "type": "array",
  "default": "",
  "maxItems": 7,
};
const _modelSchema15 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "grok-imagine-i2v",
};
const _resolutionSchema6 = <String, Object?>{
  "type": "string",
  "description": "Output resolution. ",
  "enum": ["480p", "720p"],
  "default": "720p",
};
const _durationSchema10 = <String, Object?>{
  "type": "integer",
  "description": "The generation video duration.",
  "enum": [6, 10, 15],
  "default": 6,
  "minimum": 6,
  "maximum": 30,
};
const _modelSchema16 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "grok-imagine-t2v",
};
const _promptSchema7 = <String, Object?>{
  "type": "string",
  "description": "The generation videos prompt.",
  "default": "三个人围坐在一起吃炸鸡，气氛友好愉悦，后画面逐渐模糊，画面中部显示文字“快乐尽在 APIPod”。",
  "maxLength": 4000,
};
const _characterOrientationSchema1 = <String, Object?>{
  "type": "string",
  "description":
      "Generate the orientation of the characters in the video. 'image': same orientation as the person in the picture (max 10s video). 'video': consistent with the orientation of the characters in the video (max 30s video).",
  "enum": ["image", "video"],
  "default": "image",
};
const _imageUrlSchema2 = <String, Object?>{
  "type": "string",
  "description":
      "Reference image. The characters, backgrounds, and other elements in the generated video are based on the reference image. Supports .jpg/.jpeg/.png, max 10MB, size needs to be greater than 300px, aspect ratio 2:5 to 5:2.",
  "default": "",
};
const _keepOriginalSoundSchema1 = <String, Object?>{
  "type": "boolean",
  "description": "Whether to keep the original audio of the video.",
  "default": true,
};
const _modelSchema17 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "kling-2.6-motion-control",
};
const _promptSchema8 = <String, Object?>{
  "type": "string",
  "description": "A text description of the desired output. ",
  "default":
      "No distortion, the character's movements are consistent with the video.",
  "maxLength": 2500,
};
const _qualitySchema1 = <String, Object?>{
  "type": "string",
  "description": "Quality of generating videos.",
  "enum": ["std", "pro"],
  "default": "std",
};
const _videoUrlSchema3 = <String, Object?>{
  "type": "string",
  "description":
      "Reference video. The character actions in the generated video are consistent with the reference video. Supports .mp4/.mov, max 100MB, 3-30 seconds duration depending on character_orientation.",
  "default": "",
};
const _durationSchema11 = <String, Object?>{
  "type": "integer",
  "description":
      "Required. Video duration in seconds, 3–15 (string, e.g. \"5\"). In multi-shot mode, output length and billing follow the sum of multi_prompt[].duration (3–15 s); set duration to the same total.",
  "default": 5,
  "minimum": 3,
  "maximum": 15,
};
const _generateAudioSchema1 = <String, Object?>{
  "type": "boolean",
  "description":
      "Required. Whether to generate audio (speech, sound effects, ambience) with the video. Affects price.",
  "default": false,
};
const _imageUrlsSchema9 = <String, Object?>{
  "type": "array",
  "description":
      "First and last frame image URLs. Optional; not required when using kling_elements. When multi_shots is false: if length is 2, index 0 is the first frame and index 1 is the last frame; if length is 1, the array item serves as the first frame. When multi_shots is true: only the first frame is supported.",
  "maxBytes": 20971520,
};
const _modelSchema18 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "kling-3.0-i2v",
};
const _multiPromptSchema1 = <String, Object?>{
  "type": "array",
  "description":
      "Shot prompts. Takes effect when multi_shots is true. Used to describe the text and duration of each shot. Supports up to 5 shots. Each shot duration is 1-12 seconds. If you need to use elements, add them after the prompt.",
  "default": 5,
};
const _multiShotSchema1 = <String, Object?>{
  "type": "boolean",
  "description":
      "Whether to use multi-shot mode. true enables multi-shot mode, false enables single-shot mode.",
  "default": false,
};
const _promptSchema9 = <String, Object?>{
  "type": "string",
  "description": "Required when multi_shots is false. Up to 2,500 characters.",
  "default": "",
  "minLength": 0,
  "maxLength": 2500,
};
const _resolutionSchema7 = <String, Object?>{
  "type": "string",
  "enum": ["720p", "1080p", "4k"],
  "default": "720p",
};
const _aspectRatioSchema6 = <String, Object?>{
  "type": "string",
  "enum": ["16:9", "9:16", "1:1"],
  "default": "16:9",
  "minLength": 1,
  "maxLength": 10,
};
const _generateAudioSchema2 = <String, Object?>{
  "type": "boolean",
  "description":
      "Required. Whether to generate audio (speech, sound effects, ambience) with the video. Affects price.",
  "default": false,
};
const _klingElementsSchema1 = <String, Object?>{
  "type": "array",
  "description":
      "Referenced elements. Detailed information about elements referenced in the prompt. A single task can reference a maximum of three elements.",
  "default": "",
};
const _modelSchema19 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "kling-3.0-t2v",
};
const _multiPromptSchema2 = <String, Object?>{
  "type": "array",
  "description":
      "Shot prompts. Takes effect when multi_shots is true. Used to describe the text and duration of each shot. Supports up to 5 shots. Each shot duration is 1-12 seconds. If you need to use elements, add them after the prompt.",
  "default": "",
};
const _multiShotSchema2 = <String, Object?>{
  "type": "boolean",
  "description":
      "Shot prompts. Takes effect when multi_shots is true. Used to describe the text and duration of each shot. Supports up to 5 shots. Each shot duration is 1-12 seconds. If you need to use elements, add them after the prompt.",
  "default": false,
};
const _resolutionSchema8 = <String, Object?>{
  "type": "string",
  "enum": ["720p", "1080p", "4k"],
  "default": "720p",
  "minLength": 0,
  "maxLength": 10,
};
const _durationSchema12 = <String, Object?>{
  "type": "integer",
  "default": 5,
  "minimum": 3,
  "maximum": 30,
};
const _keyframeUrlsSchema1 = <String, Object?>{
  "type": "array",
  "description":
      "Middle-frame image URLs, in chronological order. Up to 8 images, also limited by duration. Mention them in the prompt as @keyframe_1, @keyframe_2, ….",
  "maxItems": 8,
};
const _modelSchema20 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "kling-4.0-i2v",
};
const _promptSchema10 = <String, Object?>{
  "type": "string",
  "default": "",
  "minLength": 1,
  "maxLength": 8000,
};
const _aspectRatioSchema7 = <String, Object?>{
  "type": "string",
  "enum": ["auto", "16:9", "9:16", "1:1", "21:9"],
  "default": "auto",
};
const _imageUrlsSchema10 = <String, Object?>{
  "type": "array",
  "description":
      "Reference images, up to 10 publicly accessible URLs. Mention them in the prompt as @image_1, @image_2, … in array order. Each side must be 300–65536 pixels; aspect ratio 0.40–2.5.",
  "maxItems": 10,
};
const _keepOriginalSoundSchema2 = <String, Object?>{
  "type": "boolean",
  "description":
      "Whether to keep the original audio of the reference videos. Only takes effect when video_urls is provided. Default: false. If no reference video is provided, native audio is always generated.",
  "default": false,
};
const _klingElementsSchema2 = <String, Object?>{
  "type": "array",
  "description":
      "Subjects used only for this task. Up to 7 items, of which at most 3 can be video subjects. Mention them in the prompt as @name. image_urls, video_urls, elements, and voices together cannot exceed 15 items.",
  "default": "",
};
const _modelSchema21 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "kling-4.0-r2v",
};
const _videoUrlsSchema1 = <String, Object?>{
  "type": "array",
  "description":
      "Reference videos, up to 5 clips, each 2–30 seconds. Mention them in the prompt as @video_1, @video_2, …. Reference videos plus video subjects in elements cannot exceed 5 in total.",
  "maxItems": 5,
};
const _voicesSchema1 = <String, Object?>{
  "type": "array",
  "description":
      "Standalone voice references used only for this task. Up to 3 items. Mention them in the prompt as @name. Audio bound on a subject via voice_url is separate and does not count toward this quota.",
  "default": "",
};
const _aspectRatioSchema8 = <String, Object?>{
  "type": "string",
  "enum": ["16:9", "9:16", "1:1", "21:9"],
  "default": "16:9",
};
const _modelSchema22 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "kling-4.0-t2v",
};
const _durationSchema13 = <String, Object?>{
  "type": "integer",
  "description":
      "Duration of the generated video in seconds. Available values: 4-15.",
  "default": "",
  "minimum": 4,
  "maximum": 15,
};
const _modelSchema23 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "minimax-h3-i2v",
};
const _promptSchema11 = <String, Object?>{
  "type": "string",
  "default": "",
  "minLength": 1,
  "maxLength": 7000,
};
const _resolutionSchema9 = <String, Object?>{
  "type": "string",
  "description": "Video resolution. Available values: 768P and 2K.",
  "enum": ["768P", "2K"],
  "default": "2K",
};
const _aspectRatioSchema9 = <String, Object?>{
  "type": "string",
  "description": "Output aspect ratio.",
  "enum": ["21:9", "16:9", "4:3", "1:1", "3:4", "9:16"],
  "default": "16:9",
};
const _durationSchema14 = <String, Object?>{
  "type": "integer",
  "description":
      "Video generation duration. Content of 12‑seconds is easy to generate, while content longer than 12 seconds tends to fail due to timeout. You may try again if it fails.",
  "default": 5,
  "minimum": 5,
  "maximum": 15,
};
const _imageUrlsSchema11 = <String, Object?>{
  "type": "array",
  "default": "",
  "maxBytes": 20971520,
};
const _modelSchema24 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "minimax-h3-lite-i2v",
};
const _promptSchema12 = <String, Object?>{
  "type": "string",
  "description":
      "Input of text prompt. The character count of the prompt must not exceed 2000. It is recommended that the prompt avoid high‑risk content such as violations, infringement, political‑related and pornographic materials.",
  "default": "",
  "minLength": 1,
  "maxLength": 2000,
};
const _resolutionSchema10 = <String, Object?>{
  "type": "string",
  "description": "Output resolution,Only 2K is supported for the time being.",
  "enum": ["768P", "2K"],
  "default": "2K",
};
const _aspectRatioSchema10 = <String, Object?>{
  "type": "string",
  "enum": ["adaptive", "21:9", "16:9", "4:3", "1:1", "3:4", "9:16"],
  "default": "",
};
const _audioUrlsSchema1 = <String, Object?>{
  "type": "array",
  "maxBytes": 10485760,
};
const _durationSchema15 = <String, Object?>{
  "type": "integer",
  "default": "",
  "minimum": 4,
  "maximum": 15,
};
const _imageUrlsSchema12 = <String, Object?>{
  "type": "array",
  "maxItems": 9,
  "maxBytes": 10485760,
};
const _modelSchema25 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "minimax-h3-lite-r2v",
};
const _resolutionSchema11 = <String, Object?>{
  "type": "string",
  "enum": ["768P", "2K"],
  "default": "2K",
};
const _videoUrlsSchema2 = <String, Object?>{"type": "array", "maxItems": 3};
const _aspectRatioSchema11 = <String, Object?>{
  "type": "string",
  "description": "Output aspect ratio.",
  "enum": ["1:1", "3:4", "4:3", "9:16", "16:9", "21:9"],
  "default": "16:9",
};
const _modelSchema26 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "minimax-h3-lite-t2v",
};
const _durationSchema16 = <String, Object?>{
  "type": "integer",
  "description": "Video duration in seconds.",
  "enum": [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  "default": 5,
};
const _imageUrlsSchema13 = <String, Object?>{
  "type": "array",
  "description":
      "First frame image is required; an optional last frame enables first-to-last keyframe generation. The output aspect ratio follows the first frame.",
  "default": "",
};
const _modelSchema27 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "minimax-h3-max-i2v",
};
const _promptSchema13 = <String, Object?>{
  "type": "string",
  "description": "Text prompt for video generation.",
  "default": "",
  "minLength": 1,
  "maxLength": 7000,
};
const _promptExpansionModeSchema1 = <String, Object?>{
  "type": "string",
  "description":
      "balanced rewrites the prompt in about a second; quality spends up to ~30s on a richer prompt.",
  "enum": ["balanced", "quality"],
  "default": "balanced ",
};
const _resolutionSchema12 = <String, Object?>{
  "type": "string",
  "description": "Native generation resolution of the video.",
  "enum": ["480P", "768P"],
  "default": "768P",
};
const _aspectRatioSchema12 = <String, Object?>{
  "type": "string",
  "description": "Aspect ratio of the generated video.",
  "enum": ["21:9", "16:9", "4:3", "1:1", "3:4", "9:16"],
  "default": "16:9",
};
const _modelSchema28 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "minimax-h3-max-t2v",
};
const _promptExpansionModeSchema2 = <String, Object?>{
  "type": "string",
  "description":
      "balanced rewrites the prompt in about a second; quality spends up to ~30s on a richer prompt.",
  "enum": ["balanced", "quality"],
  "default": "balanced",
};
const _aspectRatioSchema13 = <String, Object?>{
  "type": "string",
  "description": "Aspect ratio of the generated video. Defaults to adaptive.",
  "enum": ["adaptive", "21:9", "16:9", "4:3", "1:1", "3:4", "9:16"],
  "default": "adaptive",
};
const _audioUrlsSchema2 = <String, Object?>{
  "type": "array",
  "description":
      "Audio cannot be used alone; at least one reference image or one reference video is required.",
  "maxItems": 3,
  "maxBytes": 15728640,
};
const _durationSchema17 = <String, Object?>{
  "type": "integer",
  "description":
      "Duration of the generated video in seconds. Available values: 4-15.",
  "default": 4,
  "minimum": 4,
  "maximum": 15,
};
const _imageUrlsSchema14 = <String, Object?>{
  "type": "array",
  "maxItems": 9,
  "maxBytes": 31457280,
};
const _modelSchema29 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "minimax-h3-r2v",
};
const _videoUrlsSchema3 = <String, Object?>{
  "type": "array",
  "maxItems": 3,
  "maxBytes": 52428800,
};
const _aspectRatioSchema14 = <String, Object?>{
  "type": "string",
  "description": "Aspect ratio of the generated video.",
  "enum": ["1:1", "3:4", "4:3", "9:16", "16:9", "21:9"],
  "default": "16:9",
};
const _modelSchema30 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "minimax-h3-t2v",
};
const _promptSchema14 = <String, Object?>{
  "type": "string",
  "default": "A cinematic shot of a robot exploring a neon city at night",
  "minLength": 1,
  "maxLength": 7000,
};
const _modelSchema31 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "motion-control-m1",
};
const _aspectRatioSchema15 = <String, Object?>{
  "type": "string",
  "enum": ["16:9", "9:16", "1:1", "4:3", "3:4"],
  "default": "16:9",
};
const _durationSchema18 = <String, Object?>{
  "type": "integer",
  "enum": [5, 10, 20, 30, 40, 50, 60],
  "default": 5,
};
const _generateAudioSchema3 = <String, Object?>{
  "type": "boolean",
  "default": true,
};
const _modelSchema32 = <String, Object?>{
  "type": "string",
  "const": "muse-video-i2v",
};
const _promptSchema15 = <String, Object?>{
  "type": "string",
  "default": "",
  "minLength": 1,
  "maxLength": 4005,
};
const _resolutionSchema13 = <String, Object?>{
  "type": "string",
  "enum": ["720p"],
  "default": "720p",
};
const _imageUrlsSchema15 = <String, Object?>{"type": "array", "maxItems": 4};
const _modelSchema33 = <String, Object?>{
  "type": "string",
  "const": "muse-video-r2v",
};
const _modelSchema34 = <String, Object?>{
  "type": "string",
  "const": "muse-video-t2v",
};
const _aspectRatioSchema16 = <String, Object?>{
  "type": "string",
  "enum": ["adaptive", "16:9", "4:3", "1:1", "3:4", "9:16", "21:9"],
  "default": "adaptive",
};
const _durationSchema19 = <String, Object?>{
  "type": "integer",
  "enum": [4, 5, 6, 7, 8, 9, 10, 11, 12],
  "default": 5,
};
const _imageUrlsSchema16 = <String, Object?>{
  "type": "array",
  "default": "",
  "maxItems": 4,
};
const _modelSchema35 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-1.0-lite-i2v-ref",
};
const _promptSchema16 = <String, Object?>{
  "type": "string",
  "default": "",
  "maxLength": 2000,
};
const _cameraFixedSchema1 = <String, Object?>{
  "type": "boolean",
  "default": false,
};
const _imageUrlsSchema17 = <String, Object?>{"type": "array", "default": ""};
const _modelSchema36 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-1.0-lite-i2v",
};
const _resolutionSchema14 = <String, Object?>{
  "type": "string",
  "enum": ["480p", "720p", "1080p"],
  "default": "480p",
};
const _aspectRatioSchema17 = <String, Object?>{
  "type": "string",
  "enum": ["16:9", "4:3", "1:1", "3:4", "9:16", "21:9"],
  "default": "16:9",
};
const _cameraFixedSchema2 = <String, Object?>{
  "type": "boolean",
  "default": false,
};
const _modelSchema37 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-1.0-lite-t2v",
};
const _aspectRatioSchema18 = <String, Object?>{
  "type": "string",
  "enum": ["adaptive", "21:9", "16:9", "4:3", "1:1", "3:4", "9:16"],
  "default": "adaptive",
};
const _modelSchema38 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-1.0-pro-fast-i2v",
};
const _aspectRatioSchema19 = <String, Object?>{
  "type": "string",
  "enum": ["16:9", "21:9", "4:3", "1:1", "3:4", "9:16"],
  "default": "16:9",
};
const _modelSchema39 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-1.0-pro-fast-t2v",
};
const _resolutionSchema15 = <String, Object?>{
  "type": "string",
  "enum": ["480p", "720p", "1080p"],
  "default": "1080p",
};
const _aspectRatioSchema20 = <String, Object?>{
  "type": "string",
  "enum": ["adaptive", "16:9", "21:9", "4:3", "3:4", "9:16", "1:1"],
  "default": "adaptive",
};
const _modelSchema40 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-1.0-pro-i2v",
};
const _aspectRatioSchema21 = <String, Object?>{
  "type": "string",
  "enum": ["21:9", "16:9", "4:3", "1:1", "3:4", "9:16"],
  "default": "16:9",
};
const _modelSchema41 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-1.0-pro-t2v",
};
const _aspectRatioSchema22 = <String, Object?>{
  "type": "string",
  "description":
      "Aspect ratio of the generated video,When the ratio is configured as adaptive,automatically select the closest aspect ratio based on the proportion of the uploaded first frame image.\n",
  "enum": ["adaptive", "4:3", "1:1", "3:4", "9:16", "16:9", "21:9"],
  "default": "16:9",
};
const _durationSchema20 = <String, Object?>{
  "type": "integer",
  "enum": [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  "default": 5,
  "minimum": 4,
  "maximum": 15,
};
const _generateAudioSchema4 = <String, Object?>{
  "type": "boolean",
  "description":
      "Controls whether the generated video contains audio synchronized with the visuals.",
  "default": true,
};
const _modelSchema42 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-fast-i2v",
};
const _promptSchema17 = <String, Object?>{
  "type": "string",
  "description":
      "Generation or editing instructions, up to 30000 characters. It is recommended to keep the prompt to no more than 500 Chinese characters or 1,000 English words. Lengthy text will lead to scattered information, and the model may ignore details and only focus on key points, resulting in missing elements in the generated video.",
  "default": "",
  "maxLength": 30000,
};
const _resolutionSchema16 = <String, Object?>{
  "type": "string",
  "description": "Generate video resolution.",
  "enum": ["480p", "720p"],
  "default": "720p",
};
const _webSearchSchema1 = <String, Object?>{
  "type": "boolean",
  "description":
      "After enabling, the model will independently decide whether to search Internet content (such as products, weather, etc.) based on the user's prompt. This can improve the timeliness of generated videos but will also introduce a certain degree of latency.",
  "default": false,
};
const _modelSchema43 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-fast-lite-i2v",
};
const _promptSchema18 = <String, Object?>{
  "type": "string",
  "description":
      "Generation or editing instructions, up to 30000 characters. It is recommended to keep the prompt to no more than 500 Chinese characters or 1,000 English words. Lengthy text will lead to scattered information, and the model may ignore details and only focus on key points, resulting in missing elements in the generated video.",
  "default": "",
  "minLength": 1,
  "maxLength": 30000,
};
const _resolutionSchema17 = <String, Object?>{
  "type": "string",
  "description": "Generate video resolution.",
  "enum": ["720p"],
  "default": "720p",
};
const _watermarkSchema1 = <String, Object?>{
  "type": "boolean",
  "description": "Whether the generated video contains a watermark.",
  "default": false,
};
const _aspectRatioSchema23 = <String, Object?>{
  "type": "string",
  "enum": ["adaptive", "1:1", "3:4", "4:3", "9:16", "16:9", "21:9"],
  "default": "adaptive",
};
const _audioUrlsSchema3 = <String, Object?>{
  "type": "array",
  "description":
      "Please note that audio files cannot be uploaded alone; at least one reference video or image must be included.",
  "default": "",
  "maxItems": 3,
  "maxBytes": 15728640,
};
const _generateAudioSchema5 = <String, Object?>{
  "type": "boolean",
  "description":
      "Controls whether the generated video contains audio synchronized with the visuals.",
  "default": true,
};
const _imageUrlsSchema18 = <String, Object?>{"type": "array", "maxItems": 9};
const _modelSchema44 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-fast-lite-r2v",
};
const _videoUrlsSchema4 = <String, Object?>{
  "type": "array",
  "default": "",
  "maxItems": 3,
};
const _watermarkSchema2 = <String, Object?>{
  "type": "boolean",
  "description": "Whether the generated video contains a watermark.",
  "default": false,
};
const _aspectRatioSchema24 = <String, Object?>{
  "type": "string",
  "description":
      "Aspect ratio of the generated video,When the ratio is configured as adaptive, the model will automatically adapt the aspect ratio according to the generation scenario.",
  "enum": ["adaptive", "16:9", "4:3", "1:1", "3:4", "9:16", "21:9"],
  "default": "adaptive",
};
const _modelSchema45 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-fast-lite-t2v",
};
const _promptSchema19 = <String, Object?>{
  "type": "string",
  "description":
      "Generation or editing instructions, up to 30000 characters. It is recommended to keep the prompt to no more than 500 Chinese characters or 1,000 English words. Lengthy text will lead to scattered information, and the model may ignore details and only focus on key points, resulting in missing elements in the generated video.",
  "default":
      "建筑模型炸开动画。玻璃幕墙做通透反光质感，石材外立面做哑光纹理，金属构件做细腻高光，极简深灰渐变背景，柔和顶光 + 侧光打亮材质细节。0-1 秒：慢推环绕全景，建筑整机实景展示，镜头顺时针缓慢环绕，展示玻璃幕墙反光、石材外立面、入口造型等细节；1-4 秒：建筑玻璃幕墙与石材外立面模块分区域向外悬浮分离，幕墙模块透明反光，分离处加微小白色粒子过渡，露出内部商铺 / 中庭 / 办公区功能空间，各外立面模块均匀散开定格；4-6 秒：建筑按功能分区（商业首层 / 办公层 / 中庭 / 屋顶花园）竖向 + 水平双向爆炸分离，各分区模块悬浮错开，清晰展示内部空间动线与功能布局，中庭挑空结构单独凸显；6-8 秒：建筑核心钢框架结构亮白色轮廓线强化，周边功能模块轻微虚化，同时室外广场、景观绿化、停车场等配套模块从建筑周边悬浮散开，所有模块最终呈扇形悬浮定格，镜头慢拉至全景，展示建筑实景材质、内部空间、核心结构、景观配套的完整关系，背景音为轻缓科技感 + 轻微环境音，画面右下角轻弹极简白色无衬线字幕「APIPod.ai」，无多余装饰。",
  "minLength": 1,
  "maxLength": 30000,
};
const _watermarkSchema3 = <String, Object?>{
  "type": "boolean",
  "description": "Whether the generated video contains a watermark",
  "default": false,
};
const _modelSchema46 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-fast-r2v",
};
const _webSearchSchema2 = <String, Object?>{
  "type": "boolean",
  "description":
      "After enabling, the model will independently decide whether to search Internet content (such as products, weather, etc.) based on the user's prompt. This can improve the timeliness of generated videos but will also introduce a certain degree of latency.",
  "default": false,
};
const _modelSchema47 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-fast-t2v",
};
const _promptSchema20 = <String, Object?>{
  "type": "string",
  "description":
      "Generation or editing instructions, up to 30000 characters. It is recommended to keep the prompt to no more than 500 Chinese characters or 1,000 English words. Lengthy text will lead to scattered information, and the model may ignore details and only focus on key points, resulting in missing elements in the generated video.",
  "default":
      "建筑模型炸开动画。玻璃幕墙做通透反光质感，石材外立面做哑光纹理，金属构件做细腻高光，极简深灰渐变背景，柔和顶光 + 侧光打亮材质细节。0-1 秒：慢推环绕全景，建筑整机实景展示，镜头顺时针缓慢环绕，展示玻璃幕墙反光、石材外立面、入口造型等细节；1-4 秒：建筑玻璃幕墙与石材外立面模块分区域向外悬浮分离，幕墙模块透明反光，分离处加微小白色粒子过渡，露出内部商铺 / 中庭 / 办公区功能空间，各外立面模块均匀散开定格；4-6 秒：建筑按功能分区（商业首层 / 办公层 / 中庭 / 屋顶花园）竖向 + 水平双向爆炸分离，各分区模块悬浮错开，清晰展示内部空间动线与功能布局，中庭挑空结构单独凸显；6-8 秒：建筑核心钢框架结构亮白色轮廓线强化，周边功能模块轻微虚化，同时室外广场、景观绿化、停车场等配套模块从建筑周边悬浮散开，所有模块最终呈扇形悬浮定格，镜头慢拉至全景，展示建筑实景材质、内部空间、核心结构、景观配套的完整关系，背景音为轻缓科技感 + 轻微环境音，画面右下角轻弹极简白色无衬线字幕「APIPod.ai」，无多余装饰。",
  "maxLength": 30000,
};
const _modelSchema48 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-i2v",
};
const _resolutionSchema18 = <String, Object?>{
  "type": "string",
  "description": "Generate video resolution.",
  "enum": ["480p", "720p", "1080p", "4k"],
  "default": "720p",
};
const _returnLastFrameSchema1 = <String, Object?>{
  "type": "boolean",
  "description":
      "Whether to return the last frame image of the generated video. Using this parameter enables the generation of multiple consecutive videos: taking the last frame of the previous generated video as the first frame of the next video task to quickly generate multiple consecutive videos, and the first item in the returned result is this image.",
  "default": false,
};
const _durationSchema21 = <String, Object?>{
  "type": "integer",
  "enum": [5, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, -1],
  "default": 5,
  "minimum": 4,
  "maximum": 15,
};
const _modelSchema49 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-lite-i2v",
};
const _realPersonSchema1 = <String, Object?>{
  "type": "boolean",
  "description":
      "Whether the reference materials contain real people (human faces). Defaults to true: materials are submitted to the asset review service and replaced with assetId:// references before task creation. Set to false only when the materials are confirmed face-free to skip review and pass material URLs through as-is.",
  "default": true,
};
const _modelSchema50 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-lite-r2v",
};
const _returnLastFrameSchema2 = <String, Object?>{
  "type": "boolean",
  "description":
      "Whether to return the last frame image of the generated video. Using this parameter enables the generation of multiple consecutive videos: taking the last frame of the previous generated video as the first frame of the next video task to quickly generate multiple consecutive videos, and the first item in the returned result is this image.",
  "default": false,
};
const _modelSchema51 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-lite-t2v",
};
const _modelSchema52 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-mini-i2v",
};
const _modelSchema53 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-mini-lite-i2v",
};
const _watermarkSchema4 = <String, Object?>{
  "type": "boolean",
  "description": "Whether to add upstream or platform watermarks.",
  "default": false,
};
const _modelSchema54 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-mini-lite-r2v",
};
const _modelSchema55 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-mini-lite-t2v",
};
const _modelSchema56 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-mini-r2v",
};
const _modelSchema57 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-mini-t2v",
};
const _modelSchema58 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-r2v",
};
const _resolutionSchema19 = <String, Object?>{
  "type": "string",
  "enum": ["480p", "720p", "1080p", "4k"],
  "default": "720p",
};
const _modelSchema59 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-spicy-i2v",
};
const _modelSchema60 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-spicy-r2v",
};
const _modelSchema61 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-spicy-t2v",
};
const _promptSchema21 = <String, Object?>{
  "type": "string",
  "default": "手绘漫画风格，三个人围坐在一起吃炸鸡，气氛友好愉悦，后画面逐渐模糊，画面中部显示文字“快乐尽在 APIPod”。",
  "minLength": 1,
  "maxLength": 30000,
};
const _modelSchema62 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-t2v",
};
const _aspectRatioSchema25 = <String, Object?>{
  "type": "string",
  "enum": ["16:9", "9:16", "4:3", "3:4", "1:1", "21:9"],
  "default": "16:9",
};
const _audioUrlsSchema4 = <String, Object?>{
  "type": "array",
  "description":
      "Reference audio URLs (up to 3), referenced as @Audio1, @Audio2, ... Audio cannot be used alone; include at least one image or video reference.",
  "items": {"type": "string"},
  "maxItems": 3,
};
const _durationSchema22 = <String, Object?>{
  "type": "integer",
  "description": "Video duration in seconds (5-15).",
  "enum": [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  "default": 5,
  "minimum": 5,
  "maximum": 15,
};
const _imageUrlsSchema19 = <String, Object?>{
  "type": "array",
  "description":
      "Reference image URLs (up to 9). Reference them in the prompt with @Image1, @Image2, ... in array order. Real-person images are supported.",
  "default": "",
  "maxItems": 9,
};
const _modelSchema63 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-x-r2v",
};
const _videoUrlsSchema5 = <String, Object?>{
  "type": "array",
  "description":
      "Reference video URLs (up to 3). Reference them in the prompt with @Video1, @Video2, ... in array order.",
  "maxItems": 3,
};
const _aspectRatioSchema26 = <String, Object?>{
  "type": "string",
  "description":
      "Aspect ratio of the generated video,When the ratio is configured as adaptive, the model will automatically adapt the aspect ratio according to the generation scenario.",
  "enum": ["16:9", "9:16", "4:3", "3:4", "1:1", "21:9"],
  "default": "16:9",
};
const _modelSchema64 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.0-x-t2v",
};
const _audioUrlsSchema5 = <String, Object?>{"type": "array", "maxItems": 10};
const _draftTaskIdSchema1 = <String, Object?>{
  "type": "string",
  "description":
      "Platform task ID of a completed draft created within the last 7 days by the same user. When set, creates the 1080p final video and reuses the draft prompt, media, duration, aspect ratio, seed, and audio setting; those fields cannot be set again.",
  "default": "",
};
const _durationSchema23 = <String, Object?>{
  "type": "integer",
  "default": 4,
  "minimum": 4,
  "maximum": 30,
};
const _imageUrlsSchema20 = <String, Object?>{
  "type": "array",
  "maxItems": 30,
  "maxBytes": 31457280,
};
const _modelSchema65 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-draft",
};
const _outputFormatSchema1 = <String, Object?>{
  "type": "string",
  "description": "Output container format.",
  "enum": ["mp4", "mov"],
  "default": "mp4",
};
const _promptSchema22 = <String, Object?>{
  "type": "string",
  "description":
      "Generation or editing instructions, up to 30000 characters. It is recommended to keep the prompt to no more than 500 Chinese characters or 1,000 English words. Lengthy text will lead to scattered information, and the model may ignore details and only focus on key points, resulting in missing elements in the generated video.",
  "default": "",
  "minLength": 0,
  "maxLength": 30000,
};
const _resolutionSchema20 = <String, Object?>{
  "type": "string",
  "description":
      "Draft previews support only 480p (default when omitted). Final videos created with draft_task_id support only 1080p (default when omitted).",
  "enum": ["480p", "1080p"],
  "default": "",
};
const _modelSchema66 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-edit",
};
const _videoUrlsSchema6 = <String, Object?>{
  "type": "array",
  "description":
      "Refer to at least one video, and the video duration must be 4‑30 seconds.",
  "items": {"type": "string"},
  "maxItems": 10,
};
const _modelSchema67 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-extend",
};
const _videoUrlsSchema7 = <String, Object?>{
  "type": "array",
  "description":
      "Reference video URLs; at least one is required (the source video to extend). Up to 10 videos are supported.",
  "items": {"type": "string"},
  "maxItems": 10,
};
const _aspectRatioSchema27 = <String, Object?>{
  "type": "string",
  "description":
      "In the first‑frame / first‑and‑last‑frame video generation task, the model automatically keeps the aspect ratio of the output video consistent with that of the first‑frame image, so it is fixed as adaptive.",
  "enum": ["adaptive"],
  "default": "adaptive",
};
const _modelSchema68 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-i2v",
};
const _modelSchema69 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-lite-i2v",
};
const _modelSchema70 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-lite-r2v",
};
const _modelSchema71 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-lite-t2v",
};
const _modelSchema72 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-r2v",
};
const _modelSchema73 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-spicy-edit",
};
const _modelSchema74 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-spicy-extend",
};
const _modelSchema75 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-spicy-i2v",
};
const _modelSchema76 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-spicy-r2v",
};
const _modelSchema77 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-spicy-t2v",
};
const _modelSchema78 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "seedance-2.5-t2v",
};
const _aspectRatioSchema28 = <String, Object?>{
  "type": "string",
  "description": "the generated video width and height aspect ratio.",
  "enum": ["16:9", "9:16"],
  "default": "16:9",
};
const _imageUrlsSchema21 = <String, Object?>{
  "type": "array",
  "description": "The referenced start frame or end frame image.",
  "default": "",
};
const _modelSchema79 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "veo3-1-fast-4k",
};
const _promptSchema23 = <String, Object?>{
  "type": "string",
  "description": "Describe the content of the video to be generated.",
  "default":
      "The camera performs a smooth 180-degree arc shot, starting with the front-facing view of the singer and circling around her to seamlessly end on the POV shot from behind her on stage. The singer sings “when you look me in the eyes, I can see a million stars.",
  "maxLength": 4000,
};
const _modelSchema80 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "veo3-1-fast-ref",
};
const _promptSchema24 = <String, Object?>{
  "type": "string",
  "description": "Describe the content of the video to be generated.",
  "default": "",
  "minLength": 1,
  "maxLength": 4000,
};
const _imageUrlsSchema22 = <String, Object?>{
  "type": "array",
  "description": "The referenced start frame or end frame image.",
};
const _modelSchema81 = <String, Object?>{
  "type": "string",
  "const": "veo3-1-fast",
};
const _modelSchema82 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "veo3-1-lite-4k",
};
const _modelSchema83 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "veo3-1-lite",
};
const _promptSchema25 = <String, Object?>{
  "type": "string",
  "description": "Describe the content of the video to be generated.",
  "default":
      "The camera performs a smooth 180-degree arc shot, starting with the front-facing view of the singer and circling around her to seamlessly end on the POV shot from behind her on stage. The singer sings “when you look me in the eyes, I can see a million stars.",
  "minLength": 1,
  "maxLength": 4000,
};
const _modelSchema84 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "veo3-1-quality-4k",
};
const _promptSchema26 = <String, Object?>{
  "type": "string",
  "description": "Describe the content of the video to be generated.",
  "default":
      "A movie-like close-up shot shows fingers gently touching a complex pencil sketch of an octopus on an antique manuscript. As the fingers make contact, a ripple of water spreads outward, and the 2D drawing magically and seamlessly transforms into a realistic, wet, and glistening 3D octopus. The octopus subtly raises its head, and its tentacles twitch as if coming to life. The entire scene is illuminated by a single warm light source on a dark wooden table, creating a mysterious and wonderful atmosphere. ASMR audio.",
  "maxLength": 4000,
};
const _modelSchema85 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "veo3-1-quality",
};
const _promptSchema27 = <String, Object?>{
  "type": "string",
  "description": "Describe the content of the video to be generated.",
  "default":
      "A movie-like close-up shot shows fingers gently touching a complex pencil sketch of an octopus on an antique manuscript. As the fingers make contact, a ripple of water spreads outward, and the 2D drawing magically and seamlessly transforms into a realistic, wet, and glistening 3D octopus. The octopus subtly raises its head, and its tentacles twitch as if coming to life. The entire scene is illuminated by a single warm light source on a dark wooden table, creating a mysterious and wonderful atmosphere. ASMR audio.",
  "minLength": 1,
  "maxLength": 4000,
};
const _audioUrlSchema1 = <String, Object?>{"type": "string"};
const _durationSchema24 = <String, Object?>{
  "type": "integer",
  "description": "Duration of the generated video.",
  "default": 5,
  "minimum": 2,
  "maximum": 15,
};
const _imageUrlsSchema23 = <String, Object?>{
  "type": "array",
  "description":
      "The image address of the first frame or the first and last frames.",
  "default": "",
};
const _modelSchema86 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan2.7-i2v",
};
const _negativePromptSchema1 = <String, Object?>{
  "type": "string",
  "description":
      "Whether to enable intelligent prompt rewriting. After enabling, a large model will be used to intelligently rewrite the input prompt. The generation effect is significantly improved for short prompts, but it will increase time consumption.",
  "default":
      "low resolution, errors, worst quality, poor quality, incomplete, extra fingers, poor aspect ratio.",
  "maxLength": 500,
};
const _promptSchema28 = <String, Object?>{
  "type": "string",
  "description": "Describe the content of the video to be generated.",
  "default": "",
  "maxLength": 5000,
};
const _promptExtendSchema1 = <String, Object?>{
  "type": "boolean",
  "description":
      "Whether to enable intelligent prompt rewriting. After enabling, a large model will be used to intelligently rewrite the input prompt. The generation effect is significantly improved for short prompts, but it will increase time consumption.",
  "default": "",
};
const _resolutionSchema21 = <String, Object?>{
  "type": "string",
  "description": "Duration of the generated video.",
  "enum": ["720P", "1080P"],
  "default": "1080P",
};
const _videoUrlSchema4 = <String, Object?>{
  "type": "string",
  "description":
      "Extend generating content based on the given video, with the maximum duration of the continuation controlled by the `duration` parameter. For example: when `duration=15` and the input video is 3 seconds long, the model will generate a 12-second continuation, resulting in a final output video with a total duration of 15 seconds, which will be charged as 15 seconds. Video duration: 2–10s.",
  "default": "",
  "maxBytes": 104857600,
};
const _watermarkSchema5 = <String, Object?>{
  "type": "boolean",
  "description":
      "Whether to add a watermark logo, with the watermark positioned at the bottom right corner of the video.",
  "default": false,
};
const _aspectRatioSchema29 = <String, Object?>{
  "type": "string",
  "description": "Aspect ratio of the generated video.",
  "enum": ["16:9", "9:16", "1:1", "4:3", "3:4"],
  "default": "16:9",
};
const _audioUrlSchema2 = <String, Object?>{
  "type": "string",
  "description":
      "The model will generate a video using this audio. If the audio length exceeds the duration value (e.g., 5 seconds), the first 5 seconds will be automatically captured and the rest discarded. If the audio length is shorter than the video duration, the part beyond the audio length will be silent video. For example, if the audio is 3 seconds long and the video duration is 5 seconds, the output video will have sound in the first 3 seconds and be silent in the remaining 2 seconds.",
  "default": "",
  "maxBytes": 15728640,
};
const _modelSchema87 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan2.7-t2v",
};
const _negativePromptSchema2 = <String, Object?>{
  "type": "string",
  "description":
      "Describe the content you do not wish to see in the video frame, which can be used to restrict the video frame. ",
  "default":
      "low resolution, errors, worst quality, poor quality, incomplete, extra fingers, poor aspect ratio.",
  "maxLength": 500,
};
const _promptSchema29 = <String, Object?>{
  "type": "string",
  "description": "Describe the content of the video to be generated.",
  "default":
      "ASMR，一把黑色刀具从右向左推进，切入一团白色蓬松的云朵状物体，置于浅木色砧板上。刀具接触时云朵形变，表面裂开，部分结构被切离并移位。云朵边缘持续释放轻烟向上飘散。刀具完成切割后停止，云朵被分为两部分，一侧塌陷。过程伴随轻微‘嘶’声和干冰升华的气流声。",
  "maxLength": 5000,
};
const _promptExtendSchema2 = <String, Object?>{
  "type": "boolean",
  "description":
      "Whether to enable intelligent prompt rewriting. After enabling, a large model will be used to intelligently rewrite the input prompt. The generation effect is significantly improved for short prompts, but it will increase time consumption.",
  "default": true,
};
const _resolutionSchema22 = <String, Object?>{
  "type": "string",
  "description":
      "Resolution levels for video generation, used to control the clarity (total pixels) of the video",
  "enum": ["720P", "1080P"],
  "default": "1080P",
};
const _watermarkSchema6 = <String, Object?>{
  "type": "boolean",
  "description":
      "Whether to add a watermark logo, with the watermark positioned at the bottom right corner of the video",
  "default": false,
};
const _audioSettingSchema1 = <String, Object?>{
  "type": "string",
  "description":
      "Video audio settings. auto (default): The model makes an intelligent judgment based on the prompt content. If the prompt involves audio descriptions, it may regenerate the audio; otherwise, it may retain the original audio of the input material. origin: Forcefully retain the original audio of the input video without regeneration.",
  "enum": ["auto", "origin"],
  "default": "auto",
};
const _durationSchema25 = <String, Object?>{
  "type": "integer",
  "description":
      "This parameter only needs to be configured when video truncation is required. If you want the output video to have the same duration as the input video, no setting is needed (or pass the default value 0).",
  "enum": [0, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  "default": 0,
};
const _imageUrlsSchema24 = <String, Object?>{
  "type": "array",
  "description": "The first frame or reference image.",
  "maxItems": 3,
  "maxBytes": 20971520,
};
const _modelSchema88 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan2.7-videoedit",
};
const _negativePromptSchema3 = <String, Object?>{
  "type": "string",
  "description":
      "Describe the content you do not wish to see in the video frame, which can be used to restrict the video frame.",
  "default":
      "low resolution, errors, worst quality, poor quality, incomplete, extra fingers, poor aspect ratio.",
  "maxLength": 500,
};
const _promptSchema30 = <String, Object?>{
  "type": "string",
  "default": "",
  "maxLength": 5000,
};
const _promptExtendSchema3 = <String, Object?>{
  "type": "boolean",
  "description":
      "Describe the content you do not wish to see in the video frame, which can be used to restrict the video frame.",
  "default": "",
};
const _resolutionSchema23 = <String, Object?>{
  "type": "string",
  "description":
      "Describe the content you do not wish to see in the video frame, which can be used to restrict the video frame.",
  "enum": ["720P", "1080P"],
  "default": "1080P",
};
const _videoUrlSchema5 = <String, Object?>{
  "type": "string",
  "description": "Video file to be edited, 2-10s",
  "default": "",
  "maxBytes": 104857600,
};
const _aspectRatioSchema30 = <String, Object?>{
  "type": "string",
  "enum": ["adaptive", "16:9", "4:3", "1:1", "3:4", "9:16"],
  "default": "adaptive",
};
const _durationSchema26 = <String, Object?>{
  "type": "integer",
  "enum": [-1],
  "default": 5,
  "minimum": 2,
  "maximum": 30,
};
const _firstFrameImageSchema1 = <String, Object?>{
  "type": "string",
  "default": "",
  "maxBytes": 20971520,
};
const _lastFrameImageSchema1 = <String, Object?>{
  "type": "string",
  "default": "",
  "maxBytes": 47185920,
};
const _modelSchema89 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-i2v",
};
const _promptSchema31 = <String, Object?>{
  "type": "string",
  "default": "",
  "minLength": 0,
  "maxLength": 20000,
};
const _resolutionSchema24 = <String, Object?>{
  "type": "string",
  "enum": ["480P", "720P", "1080P"],
  "default": "1080P",
};
const _modelSchema90 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-prime-i2v",
};
const _audioUrlsSchema6 = <String, Object?>{
  "type": "array",
  "description":
      "Refer to the audio, with a maximum of 5 segments and a total duration no more than 15 seconds.",
  "maxItems": 5,
  "maxBytes": 15728640,
};
const _durationSchema27 = <String, Object?>{
  "type": "integer",
  "enum": [-1],
  "default": 5,
  "minimum": 2,
  "maximum": 51,
};
const _fileUrlSchema1 = <String, Object?>{
  "type": "string",
  "description":
      "Reference File, maximum one, cannot be input together with link url. support format：docx、doc、xlsx、xls、pptx、ppt、pdf、txt、key、pages、numbers、md。",
  "default": "",
};
const _imageUrlsSchema25 = <String, Object?>{
  "type": "array",
  "description": "Refer to the images, up to 10.",
  "maxItems": 10,
  "maxBytes": 20971520,
};
const _linkUrlSchema1 = <String, Object?>{
  "type": "string",
  "description":
      "The URL address of the public web page. Only public web pages that do not require login are supported for parsing. Cannot be input together with file.",
  "default": "",
};
const _modelSchema91 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-prime-r2v",
};
const _promptSchema32 = <String, Object?>{
  "type": "string",
  "description":
      "Text prompt used to describe the expected generated video content.",
  "default": "",
  "minLength": 0,
  "maxLength": 20000,
};
const _videoUrlsSchema8 = <String, Object?>{
  "type": "array",
  "description":
      "Reference videos. Maximum 5 clips, total duration no more than 15 seconds.",
  "maxItems": 5,
  "maxBytes": 104857600,
};
const _imageUrlsSchema26 = <String, Object?>{
  "type": "array",
  "default": "",
  "maxBytes": 47185920,
};
const _modelSchema92 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-prime-spicy-i2v",
};
const _promptSchema33 = <String, Object?>{
  "type": "string",
  "default": "",
  "minLength": 1,
  "maxLength": 20000,
};
const _promptExtendSchema4 = <String, Object?>{
  "type": "boolean",
  "description":
      "Whether the upstream rewrites (expands) the prompt before generation. Omit to use the upstream default (true); set false to stay close to the literal prompt.",
  "default": "",
};
const _modelSchema93 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-prime-spicy-r2v",
};
const _aspectRatioSchema31 = <String, Object?>{
  "type": "string",
  "description": "Aspect ratio for generated videos.",
  "enum": ["adaptive", "16:9", "4:3", "1:1", "3:4", "9:16"],
  "default": "adaptive",
};
const _durationSchema28 = <String, Object?>{
  "type": "integer",
  "description": "The duration of the generated video, in seconds.",
  "enum": [-1],
  "default": 5,
  "minimum": 2,
  "maximum": 30,
};
const _generateAudioSchema6 = <String, Object?>{
  "type": "boolean",
  "description": "Does the output video contain audio?",
  "default": true,
};
const _modelSchema94 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-prime-spicy-t2v",
};
const _promptSchema34 = <String, Object?>{
  "type": "string",
  "description":
      "Text prompt used to describe the expected generated video content.",
  "default": "",
  "minLength": 1,
  "maxLength": 20000,
};
const _promptExtendSchema5 = <String, Object?>{
  "type": "boolean",
  "description":
      "Whether the upstream rewrites (expands) the prompt before generation. Omit to use the upstream default (true); set false to stay close to the literal prompt.",
  "default": false,
};
const _resolutionSchema25 = <String, Object?>{
  "type": "string",
  "description":
      "Resolution levels for video generation. The default value is 1080p.",
  "enum": ["480P", "720P", "1080P"],
  "default": "1080P",
};
const _modelSchema95 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-prime-t2v",
};
const _modelSchema96 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-pro-spicy-i2v",
};
const _resolutionSchema26 = <String, Object?>{
  "type": "string",
  "description": "Output resolution tier (case-insensitive).",
  "enum": ["1080P", "2K", "4K"],
  "default": "1080P",
};
const _modelSchema97 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-pro-spicy-r2v",
};
const _modelSchema98 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-pro-spicy-t2v",
};
const _modelSchema99 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-r2v",
};
const _modelSchema100 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-spicy-i2v",
};
const _modelSchema101 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-spicy-r2v",
};
const _modelSchema102 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-spicy-t2v",
};
const _modelSchema103 = <String, Object?>{
  "type": "string",
  "description": "模型标识符",
  "const": "wan3.0-t2v",
};
