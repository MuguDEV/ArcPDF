import 'dart:async';

enum JobState { queued, running, cancelling, completed, failed, cancelled }

class JobProgress {
  final double percentage;
  final String stage;

  const JobProgress({required this.percentage, required this.stage});
}

class JobCancelledException implements Exception {
  const JobCancelledException();
}

class JobHandle<T> {
  JobHandle(this._entry);
  final JobEntry<T> _entry;

  Future<T> get future => _entry.completer.future;
  JobState get state => _entry.state;

  void cancel() {
    if (_entry.state == JobState.completed ||
        _entry.state == JobState.failed ||
        _entry.state == JobState.cancelled) {
      return;
    }
    _entry.cancel?.call();
  }
}

abstract class Job<T> {
  Future<T> run(void Function(JobProgress progress)? onProgress,
      Future<void> Function()? checkCancelled);
}

class JobQueue {
  static final JobQueue _instance = JobQueue._internal();
  factory JobQueue() => _instance;
  JobQueue._internal();

  final int _concurrencyLimit = 2;
  int _activeJobs = 0;
  final _queue = <JobEntry>[];

  Future<T> enqueue<T>(Job<T> job,
      {void Function(JobProgress progress)? onProgress,
      Future<void> Function()? checkCancelled,
      void Function(JobHandle<T> handle)? onHandle}) {
    final completer = Completer<T>();
    final entry = JobEntry<T>(
      job: job,
      completer: completer,
      onProgress: onProgress,
      checkCancelled: checkCancelled,
    );
    entry.cancel = () => _cancel(entry);
    onHandle?.call(JobHandle<T>(entry));
    _queue.add(entry);
    _processQueue();
    return completer.future;
  }

  void _cancel<T>(JobEntry<T> entry) {
    if (entry.state == JobState.queued) {
      _queue.remove(entry);
      entry.cancelRequested = true;
      entry.state = JobState.cancelled;
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(const JobCancelledException());
      }
      _processQueue();
      return;
    }
    if (entry.state == JobState.running) {
      entry.cancelRequested = true;
      entry.state = JobState.cancelling;
    }
  }

  void _processQueue() {
    if (_activeJobs >= _concurrencyLimit || _queue.isEmpty) return;

    _activeJobs++;
    final entry = _queue.removeAt(0);
    entry.state = JobState.running;

    _runJob(entry).whenComplete(() {
      _activeJobs--;
      _processQueue();
    });
  }

  Future<void> _runJob(JobEntry entry) async {
    try {
      final result = await entry.job.run(entry.onProgress, () async {
        if (entry.cancelRequested) throw const JobCancelledException();
        await entry.checkCancelled?.call();
        if (entry.cancelRequested) throw const JobCancelledException();
      });
      if (entry.cancelRequested) throw const JobCancelledException();
      entry.state = JobState.completed;
      entry.completer.complete(result);
    } catch (e, st) {
      entry.state =
          e is JobCancelledException ? JobState.cancelled : JobState.failed;
      if (!entry.completer.isCompleted) entry.completer.completeError(e, st);
    }
  }
}

class JobEntry<T> {
  final Job<T> job;
  final Completer<T> completer;
  final void Function(JobProgress progress)? onProgress;
  final Future<void> Function()? checkCancelled;
  JobState state = JobState.queued;
  bool cancelRequested = false;
  void Function()? cancel;

  JobEntry({
    required this.job,
    required this.completer,
    this.onProgress,
    this.checkCancelled,
  });
}
