import '../core/async_work_pool.dart';

// Reference probes and generated filmstrips share one budget. Completed-byte
// caches cannot constrain the media decoders allocated by in-flight work.
final mediaPreviewWork = AsyncWorkPool(maximumConcurrent: 2);
