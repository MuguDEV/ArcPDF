import 'dart:async';

class JobProgress {
  final double percentage;
  final String stage;

  const JobProgress({required this.percentage, required this.stage});
}

abstract class Job<T> {
  Future<T> run(void Function(JobProgress progress)? onProgress, Future<void> Function()? checkCancelled);
}

class JobQueue {
  static final JobQueue _instance = JobQueue._internal();
  factory JobQueue() => _instance;
  JobQueue._internal();

  final int _concurrencyLimit = 2;
  int _activeJobs = 0;
  final _queue = <_JobEntry>[];

  Future<T> enqueue<T>(Job<T> job, {void Function(JobProgress progress)? onProgress, Future<void> Function()? checkCancelled}) {
    final completer = Completer<T>();
    _queue.add(_JobEntry<T>(
      job: job,
      completer: completer,
      onProgress: onProgress,
      checkCancelled: checkCancelled,
    ));
    _processQueue();
    return completer.future;
  }

  void _processQueue() {
    if (_activeJobs >= _concurrencyLimit || _queue.isEmpty) return;

    _activeJobs++;
    final entry = _queue.removeAt(0);

    _runJob(entry).whenComplete(() {
      _activeJobs--;
      _processQueue();
    });
  }

  Future<void> _runJob(_JobEntry entry) async {
    try {
      final result = await entry.job.run(
        entry.onProgress,
        entry.checkCancelled
      );
      entry.completer.complete(result);
    } catch (e, st) {
      entry.completer.completeError(e, st);
    }
  }
}

class _JobEntry<T> {
  final Job<T> job;
  final Completer<T> completer;
  final void Function(JobProgress progress)? onProgress;
  final Future<void> Function()? checkCancelled;

  _JobEntry({
    required this.job,
    required this.completer,
    this.onProgress,
    this.checkCancelled,
  });
}
