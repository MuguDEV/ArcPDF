import 'package:flutter_test/flutter_test.dart';
import 'package:arcpdf/src/features/tools/job_queue.dart';

class TestJob extends Job<String> {
  final String id;
  final Duration delay;
  final bool fail;

  TestJob(this.id, {this.delay = const Duration(milliseconds: 10), this.fail = false});

  @override
  Future<String> run(void Function(JobProgress progress)? onProgress, Future<void> Function()? checkCancelled) async {
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
}
