import 'package:flutter_test/flutter_test.dart';
import 'package:arcpdf/src/features/tools/job_queue.dart';

class TestJob extends Job<String> {
  final String id;
  final Duration delay;
  final bool fail;

  TestJob(this.id,
      {this.delay = const Duration(milliseconds: 10), this.fail = false});

  @override
  Future<String> run(void Function(JobProgress progress)? onProgress,
      Future<void> Function()? checkCancelled) async {
    await Future.delayed(delay);
    if (fail) throw Exception("Job failed");
    return id;
  }
}

void main() {
  test('JobQueue executes sequentially within concurrency limits', () async {
    final queue = JobQueue();
    final j1 = queue.enqueue(TestJob("1"));
    final j2 = queue.enqueue(TestJob("2"));
    final j3 = queue.enqueue(TestJob("3"));

    expect(await j1, "1");
    expect(await j2, "2");
    expect(await j3, "3");
  });

  test('cancelling a running job never reports success', () async {
    final queue = JobQueue();
    late JobHandle<String> handle;
    final future = queue.enqueue(
      TestJob('result', delay: const Duration(milliseconds: 30)),
      onHandle: (value) => handle = value,
    );

    handle.cancel();

    await expectLater(future, throwsA(isA<JobCancelledException>()));
    expect(handle.state, JobState.cancelled);
  });

  test('cancelling a queued job removes it from the queue', () async {
    final queue = JobQueue();
    final first = queue
        .enqueue(TestJob('first', delay: const Duration(milliseconds: 50)));
    final second = queue
        .enqueue(TestJob('second', delay: const Duration(milliseconds: 50)));
    late JobHandle<String> handle;
    final queued =
        queue.enqueue(TestJob('queued'), onHandle: (value) => handle = value);

    handle.cancel();

    await expectLater(queued, throwsA(isA<JobCancelledException>()));
    expect(handle.state, JobState.cancelled);
    await Future.wait([first, second]);
  });
}
