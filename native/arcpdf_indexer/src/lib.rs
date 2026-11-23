use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, VecDeque};
use std::ffi::{CStr, CString};
use std::fs::{self, File};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::raw::{c_char, c_int, c_ulong, c_void};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{mpsc, Arc, Condvar, Mutex, OnceLock};
use std::thread;
use std::time::{Instant, UNIX_EPOCH};

mod reflow;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ScanRequest {
    roots: Vec<String>,
    #[serde(default)]
    excluded_roots: Vec<String>,
    cache_path: Option<String>,
    max_workers: Option<usize>,
}

#[derive(Deserialize)]
#[serde(tag = "kind", content = "payload", rename_all = "camelCase")]
enum JobSubmitRequest {
    Scan(ScanRequest),
    External(ExternalRequest),
    NativePdf(NativePdfRequest),
    Reflow(ReflowRequest),
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExternalRequest {
    operation: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativePdfRequest {
    operation: String,
    #[serde(default)]
    input_paths: Vec<String>,
    input_path: Option<String>,
    output_path: String,
    #[serde(default)]
    pages: Vec<i32>,
    #[serde(default)]
    groups: Vec<NativePdfPageGroup>,
    selection: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativePdfPageGroup {
    start: i32,
    end: i32,
    pages: Vec<i32>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReflowRequest {
    input_path: String,
    cache_path: Option<String>,
    settings_key: String,
    #[serde(default = "default_true")]
    detect_tables: bool,
    #[serde(default = "default_true")]
    detect_figures: bool,
    #[serde(default = "default_true")]
    remove_repeated_headers: bool,
    #[serde(default)]
    ocr_pages: Vec<ReflowOcrPage>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReflowOcrPage {
    page: i32,
    #[serde(default)]
    lines: Vec<ReflowOcrLine>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReflowOcrLine {
    text: String,
    bounds: [f64; 4],
    confidence: Option<f64>,
    #[serde(default)]
    elements: Vec<ReflowOcrElement>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReflowOcrElement {
    text: String,
    bounds: [f64; 4],
    confidence: Option<f64>,
}

fn default_true() -> bool {
    true
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct PdfEntry {
    path: String,
    name: String,
    size_bytes: u64,
    modified_millis: i64,
    location_label: String,
    is_encrypted: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DuplicateGroup {
    digest: String,
    size_bytes: u64,
    reclaimable_bytes: u64,
    paths: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ScanStats {
    elapsed_millis: u128,
    files_considered: usize,
    files_hashed: usize,
    cache_hits: usize,
    workers: usize,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ScanResponse {
    files: Vec<PdfEntry>,
    duplicate_groups: Vec<DuplicateGroup>,
    stats: ScanStats,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct CacheEntry {
    size_bytes: u64,
    modified_millis: i64,
    digest: String,
}

struct WalkState {
    dirs: VecDeque<PathBuf>,
    seen_dirs: HashSet<PathBuf>,
    active: usize,
    done: bool,
}

struct WalkQueue {
    state: Mutex<WalkState>,
    changed: Condvar,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct JobError {
    code: String,
    message: String,
    retryable: bool,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct JobSnapshot {
    job_id: u64,
    kind: String,
    state: String,
    stage: String,
    progress: Option<f64>,
    processed: usize,
    total: Option<usize>,
    error: Option<JobError>,
    result: Option<serde_json::Value>,
}

struct JobRecord {
    snapshot: Mutex<JobSnapshot>,
    cancelled: AtomicBool,
    external_result: Mutex<Option<Result<serde_json::Value, JobError>>>,
    changed: Condvar,
}

impl JobRecord {
    fn update(&self, stage: &str, progress: Option<f64>, processed: usize, total: Option<usize>) {
        let mut snapshot = self.snapshot.lock().unwrap();
        snapshot.stage = stage.into();
        snapshot.progress = progress;
        snapshot.processed = processed;
        snapshot.total = total;
    }

    fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Relaxed)
    }
}

enum JobCommand {
    Scan(ScanRequest),
    External,
    NativePdf(NativePdfRequest),
    Reflow(ReflowRequest),
}

struct JobEnvelope {
    id: u64,
    command: JobCommand,
}

struct JobRuntime {
    next_id: AtomicU64,
    jobs: Arc<Mutex<HashMap<u64, Arc<JobRecord>>>>,
    sender: mpsc::Sender<JobEnvelope>,
}

static JOB_RUNTIME: OnceLock<JobRuntime> = OnceLock::new();

fn job_runtime() -> &'static JobRuntime {
    JOB_RUNTIME.get_or_init(|| {
        let (sender, receiver) = mpsc::channel::<JobEnvelope>();
        let receiver = Arc::new(Mutex::new(receiver));
        let jobs = Arc::new(Mutex::new(HashMap::<u64, Arc<JobRecord>>::new()));
        for worker in 0..2 {
            let receiver = Arc::clone(&receiver);
            let jobs = Arc::clone(&jobs);
            thread::Builder::new()
                .name(format!("arcpdf-job-{worker}"))
                .spawn(move || loop {
                    let envelope = match receiver.lock().unwrap().recv() {
                        Ok(value) => value,
                        Err(_) => return,
                    };
                    let Some(record) = jobs.lock().unwrap().get(&envelope.id).cloned() else {
                        continue;
                    };
                    if record.is_cancelled() {
                        finish_cancelled(&record);
                        continue;
                    }
                    record.snapshot.lock().unwrap().state = "running".into();
                    let result = match envelope.command {
                        JobCommand::Scan(request) => scan_controlled(request, Some(&record))
                            .and_then(|value| {
                                serde_json::to_value(value).map_err(|_| JobFailure::Serialization)
                            }),
                        JobCommand::External => run_external(&record),
                        JobCommand::NativePdf(request) => run_native_pdf(request, &record),
                        JobCommand::Reflow(request) => run_reflow(request, &record),
                    };
                    let mut snapshot = record.snapshot.lock().unwrap();
                    match result {
                        Ok(value) if !record.is_cancelled() => {
                            snapshot.state = "completed".into();
                            snapshot.stage = "Completed".into();
                            snapshot.progress = Some(1.0);
                            snapshot.result = Some(value);
                        }
                        Ok(_) | Err(JobFailure::Cancelled) => {
                            snapshot.state = "cancelled".into();
                            snapshot.stage = "Cancelled".into();
                            snapshot.progress = None;
                        }
                        Err(error) => {
                            snapshot.state = "failed".into();
                            snapshot.stage = "Failed".into();
                            snapshot.progress = None;
                            snapshot.error = Some(error.details());
                        }
                    }
                })
                .expect("ArcPDF job worker must start");
        }
        JobRuntime {
            next_id: AtomicU64::new(1),
            jobs,
            sender,
        }
    })
}

#[derive(Debug)]
enum JobFailure {
    Cancelled,
    Serialization,
    External(JobError),
}

impl JobFailure {
    fn details(&self) -> JobError {
        match self {
            Self::Cancelled => JobError {
                code: "cancelled".into(),
                message: "The operation was cancelled.".into(),
                retryable: true,
            },
            Self::Serialization => JobError {
                code: "result_serialization_failed".into(),
                message: "The operation completed but its result could not be returned.".into(),
                retryable: true,
            },
            Self::External(error) => error.clone(),
        }
    }
}

fn run_external(record: &Arc<JobRecord>) -> Result<serde_json::Value, JobFailure> {
    record.update("Starting operation", None, 0, None);
    let mut result = record.external_result.lock().unwrap();
    loop {
        if record.is_cancelled() {
            return Err(JobFailure::Cancelled);
        }
        if let Some(value) = result.take() {
            return value.map_err(JobFailure::External);
        }
        result = record
            .changed
            .wait_timeout(result, std::time::Duration::from_millis(100))
            .unwrap()
            .0;
    }
}

fn finish_cancelled(record: &JobRecord) {
    let mut snapshot = record.snapshot.lock().unwrap();
    snapshot.state = "cancelled".into();
    snapshot.stage = "Cancelled".into();
    snapshot.progress = None;
}

fn normalized_absolute(path: &Path) -> Option<PathBuf> {
    if path.is_absolute() {
        Some(path.components().collect())
    } else {
        std::env::current_dir()
            .ok()
            .map(|cwd| cwd.join(path).components().collect())
    }
}

fn excluded(path: &Path, exclusions: &[PathBuf]) -> bool {
    let Some(absolute) = normalized_absolute(path) else {
        return true;
    };
    if exclusions
        .iter()
        .any(|root| absolute == *root || absolute.starts_with(root))
    {
        return true;
    }
    let segments: Vec<String> = absolute
        .components()
        .map(|part| part.as_os_str().to_string_lossy().to_ascii_lowercase())
        .collect();
    if segments.iter().any(|part| {
        part == ".trash"
            || part == ".trashes"
            || part.starts_with(".trashed-")
            || part.starts_with(".pending-")
    }) {
        return true;
    }
    segments
        .windows(2)
        .any(|pair| pair[0] == "android" && (pair[1] == "data" || pair[1] == "obb"))
}

fn inspect_pdf(path: &Path, size: u64) -> Option<bool> {
    if size < 5 {
        return None;
    }
    let mut file = File::open(path).ok()?;
    let mut head = vec![0_u8; 4096.min(size as usize)];
    file.read_exact(&mut head).ok()?;
    if !head.starts_with(b"%PDF-") {
        return None;
    }
    if head.windows(8).any(|part| part == b"/Encrypt") {
        return Some(true);
    }
    if size > 4096 {
        file.seek(SeekFrom::End(-4096)).ok()?;
        let mut tail = vec![0_u8; 4096];
        file.read_exact(&mut tail).ok()?;
        if tail.windows(8).any(|part| part == b"/Encrypt") {
            return Some(true);
        }
    }
    Some(false)
}

fn validate_pdf(path: &Path) -> Option<PdfEntry> {
    let metadata = fs::symlink_metadata(path).ok()?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return None;
    }
    let size = metadata.len();
    let encrypted = inspect_pdf(path, size)?;
    let modified_millis = metadata
        .modified()
        .ok()?
        .duration_since(UNIX_EPOCH)
        .ok()?
        .as_millis() as i64;
    Some(PdfEntry {
        path: path.to_string_lossy().into_owned(),
        name: path.file_name()?.to_string_lossy().into_owned(),
        size_bytes: size,
        modified_millis,
        location_label: path
            .parent()
            .and_then(Path::file_name)
            .map(|v| v.to_string_lossy().into_owned())
            .unwrap_or_else(|| "Storage".into()),
        is_encrypted: encrypted,
    })
}

fn walk_concurrently(
    roots: &[String],
    exclusions: &[PathBuf],
    workers: usize,
    control: Option<&Arc<JobRecord>>,
) -> Result<Vec<PdfEntry>, JobFailure> {
    let mut dirs = VecDeque::new();
    let mut seen_dirs = HashSet::new();
    for root in roots {
        let path = PathBuf::from(root);
        let Ok(meta) = fs::symlink_metadata(&path) else {
            continue;
        };
        if meta.file_type().is_symlink() || !meta.is_dir() || excluded(&path, exclusions) {
            continue;
        }
        let Some(path) = normalized_absolute(&path) else {
            continue;
        };
        if seen_dirs.insert(path.clone()) {
            dirs.push_back(path);
        }
    }
    let queue = Arc::new(WalkQueue {
        state: Mutex::new(WalkState {
            done: dirs.is_empty(),
            dirs,
            seen_dirs,
            active: 0,
        }),
        changed: Condvar::new(),
    });
    let output = Arc::new(Mutex::new(Vec::new()));
    thread::scope(|scope| {
        for _ in 0..workers {
            let queue = Arc::clone(&queue);
            let output = Arc::clone(&output);
            scope.spawn(move || loop {
                let dir = {
                    let mut state = queue.state.lock().unwrap();
                    if control.is_some_and(|record| record.is_cancelled()) {
                        state.done = true;
                        queue.changed.notify_all();
                        return;
                    }
                    while state.dirs.is_empty() && !state.done {
                        state = queue.changed.wait(state).unwrap();
                    }
                    if state.done {
                        return;
                    }
                    state.active += 1;
                    state.dirs.pop_front().unwrap()
                };
                let mut child_dirs = Vec::new();
                let mut found = Vec::new();
                if let Ok(entries) = fs::read_dir(&dir) {
                    for entry in entries.flatten() {
                        if control.is_some_and(|record| record.is_cancelled()) {
                            break;
                        }
                        let path = entry.path();
                        let Ok(kind) = entry.file_type() else {
                            continue;
                        };
                        if kind.is_symlink() || excluded(&path, exclusions) {
                            continue;
                        }
                        if kind.is_dir() {
                            child_dirs.push(path);
                        } else if kind.is_file()
                            && path
                                .extension()
                                .is_some_and(|ext| ext.eq_ignore_ascii_case("pdf"))
                        {
                            if let Some(pdf) = validate_pdf(&path) {
                                found.push(pdf);
                            }
                        }
                    }
                }
                if !found.is_empty() {
                    let mut values = output.lock().unwrap();
                    values.extend(found);
                    if let Some(record) = control {
                        record.update("Discovering PDFs", None, values.len(), None);
                    }
                }
                let mut state = queue.state.lock().unwrap();
                for child in child_dirs {
                    if let Some(child) = normalized_absolute(&child) {
                        if state.seen_dirs.insert(child.clone()) {
                            state.dirs.push_back(child);
                        }
                    }
                }
                state.active -= 1;
                if control.is_some_and(|record| record.is_cancelled())
                    || (state.dirs.is_empty() && state.active == 0)
                {
                    state.done = true;
                }
                queue.changed.notify_all();
            });
        }
    });
    if control.is_some_and(|record| record.is_cancelled()) {
        return Err(JobFailure::Cancelled);
    }
    Ok(Arc::try_unwrap(output).unwrap().into_inner().unwrap())
}

fn hash_file(path: &str, control: Option<&Arc<JobRecord>>) -> Option<String> {
    let mut file = File::open(path).ok()?;
    let mut hasher = blake3::Hasher::new();
    let mut buffer = vec![0_u8; 256 * 1024];
    loop {
        if control.is_some_and(|record| record.is_cancelled()) {
            return None;
        }
        let count = file.read(&mut buffer).ok()?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    Some(hasher.finalize().to_hex().to_string())
}

fn load_cache(path: Option<&str>) -> HashMap<String, CacheEntry> {
    path.and_then(|value| fs::read(value).ok())
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

fn save_cache(path: Option<&str>, cache: &HashMap<String, CacheEntry>) {
    let Some(path) = path else { return };
    let target = Path::new(path);
    if let Some(parent) = target.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let temporary = target.with_extension("tmp");
    if let Ok(bytes) = serde_json::to_vec(cache) {
        if fs::write(&temporary, bytes).is_ok() {
            let _ = fs::rename(temporary, target);
        }
    }
}

fn find_duplicates(
    files: &[PdfEntry],
    cache_path: Option<&str>,
    workers: usize,
    control: Option<&Arc<JobRecord>>,
) -> Result<(Vec<DuplicateGroup>, usize, usize), JobFailure> {
    let mut by_size: HashMap<u64, Vec<PdfEntry>> = HashMap::new();
    for file in files {
        by_size
            .entry(file.size_bytes)
            .or_default()
            .push(file.clone());
    }
    let candidates: Vec<PdfEntry> = by_size
        .into_values()
        .filter(|group| group.len() > 1)
        .flatten()
        .collect();
    let old_cache = Arc::new(load_cache(cache_path));
    let fresh_cache = Arc::new(Mutex::new(HashMap::new()));
    let hashes = Arc::new(Mutex::new(Vec::<(PdfEntry, String)>::new()));
    let index = Arc::new(AtomicUsize::new(0));
    let hashed = Arc::new(AtomicUsize::new(0));
    let hits = Arc::new(AtomicUsize::new(0));
    let completed = Arc::new(AtomicUsize::new(0));
    if let Some(record) = control {
        record.update(
            "Hashing duplicate candidates",
            Some(if candidates.is_empty() { 1.0 } else { 0.0 }),
            0,
            Some(candidates.len()),
        );
    }
    thread::scope(|scope| {
        for _ in 0..workers {
            let candidates = &candidates;
            let old_cache = Arc::clone(&old_cache);
            let fresh_cache = Arc::clone(&fresh_cache);
            let hashes = Arc::clone(&hashes);
            let index = Arc::clone(&index);
            let hashed = Arc::clone(&hashed);
            let hits = Arc::clone(&hits);
            let completed = Arc::clone(&completed);
            scope.spawn(move || loop {
                if control.is_some_and(|record| record.is_cancelled()) {
                    return;
                }
                let next = index.fetch_add(1, Ordering::Relaxed);
                let Some(file) = candidates.get(next) else {
                    return;
                };
                let digest = match old_cache.get(&file.path) {
                    Some(cached)
                        if cached.size_bytes == file.size_bytes
                            && cached.modified_millis == file.modified_millis =>
                    {
                        hits.fetch_add(1, Ordering::Relaxed);
                        cached.digest.clone()
                    }
                    _ => {
                        let Some(value) = hash_file(&file.path, control) else {
                            return;
                        };
                        hashed.fetch_add(1, Ordering::Relaxed);
                        value
                    }
                };
                fresh_cache.lock().unwrap().insert(
                    file.path.clone(),
                    CacheEntry {
                        size_bytes: file.size_bytes,
                        modified_millis: file.modified_millis,
                        digest: digest.clone(),
                    },
                );
                hashes.lock().unwrap().push((file.clone(), digest));
                let done = completed.fetch_add(1, Ordering::Relaxed) + 1;
                if let Some(record) = control {
                    record.update(
                        "Hashing duplicate candidates",
                        Some(done as f64 / candidates.len() as f64),
                        done,
                        Some(candidates.len()),
                    );
                }
            });
        }
    });
    if control.is_some_and(|record| record.is_cancelled()) {
        return Err(JobFailure::Cancelled);
    }
    let mut grouped: HashMap<(u64, String), Vec<String>> = HashMap::new();
    for (file, digest) in hashes.lock().unwrap().iter() {
        grouped
            .entry((file.size_bytes, digest.clone()))
            .or_default()
            .push(file.path.clone());
    }
    let mut groups: Vec<DuplicateGroup> = grouped
        .into_iter()
        .filter_map(|((size, digest), mut paths)| {
            if paths.len() < 2 {
                return None;
            }
            paths.sort();
            Some(DuplicateGroup {
                digest,
                size_bytes: size,
                reclaimable_bytes: size.saturating_mul((paths.len() - 1) as u64),
                paths,
            })
        })
        .collect();
    groups.sort_by(|a, b| b.reclaimable_bytes.cmp(&a.reclaimable_bytes));
    save_cache(cache_path, &fresh_cache.lock().unwrap());
    Ok((
        groups,
        hashed.load(Ordering::Relaxed),
        hits.load(Ordering::Relaxed),
    ))
}

fn scan(request: ScanRequest) -> ScanResponse {
    scan_controlled(request, None).expect("uncontrolled scan cannot be cancelled")
}

fn scan_controlled(
    request: ScanRequest,
    control: Option<&Arc<JobRecord>>,
) -> Result<ScanResponse, JobFailure> {
    let started = Instant::now();
    let available = thread::available_parallelism()
        .map(usize::from)
        .unwrap_or(2);
    let workers = request.max_workers.unwrap_or(available).clamp(1, 6);
    let exclusions: Vec<PathBuf> = request
        .excluded_roots
        .iter()
        .filter_map(|value| normalized_absolute(Path::new(value)))
        .collect();
    if let Some(record) = control {
        record.update("Discovering PDFs", None, 0, None);
    }
    let mut files = walk_concurrently(&request.roots, &exclusions, workers, control)?;
    files.sort_by(|a, b| b.modified_millis.cmp(&a.modified_millis));
    let (duplicate_groups, files_hashed, cache_hits) =
        find_duplicates(&files, request.cache_path.as_deref(), workers, control)?;
    if let Some(record) = control {
        record.update("Finalizing index", None, files.len(), Some(files.len()));
    }
    Ok(ScanResponse {
        stats: ScanStats {
            elapsed_millis: started.elapsed().as_millis(),
            files_considered: files.len(),
            files_hashed,
            cache_hits,
            workers,
        },
        files,
        duplicate_groups,
    })
}

type PdfDocumentHandle = *mut c_void;
type PdfPageHandle = *mut c_void;
type PdfTextPageHandle = *mut c_void;
type PdfLoadDocument = unsafe extern "C" fn(*const c_char, *const c_char) -> PdfDocumentHandle;
type PdfCreateDocument = unsafe extern "C" fn() -> PdfDocumentHandle;
type PdfCloseDocument = unsafe extern "C" fn(PdfDocumentHandle);
type PdfGetPageCount = unsafe extern "C" fn(PdfDocumentHandle) -> c_int;
type PdfImportPages =
    unsafe extern "C" fn(PdfDocumentHandle, PdfDocumentHandle, *const c_char, c_int) -> c_int;
type PdfImportPagesByIndex = unsafe extern "C" fn(
    PdfDocumentHandle,
    PdfDocumentHandle,
    *const c_int,
    c_ulong,
    c_int,
) -> c_int;
type PdfSaveAsCopy = unsafe extern "C" fn(PdfDocumentHandle, *mut PdfFileWrite, c_ulong) -> c_int;
type PdfGetLastError = unsafe extern "C" fn() -> c_ulong;
type PdfInitLibrary = unsafe extern "C" fn();
type PdfLoadPage = unsafe extern "C" fn(PdfDocumentHandle, c_int) -> PdfPageHandle;
type PdfClosePage = unsafe extern "C" fn(PdfPageHandle);
type PdfGetPageWidth = unsafe extern "C" fn(PdfPageHandle) -> f64;
type PdfGetPageHeight = unsafe extern "C" fn(PdfPageHandle) -> f64;
type PdfTextLoadPage = unsafe extern "C" fn(PdfPageHandle) -> PdfTextPageHandle;
type PdfTextClosePage = unsafe extern "C" fn(PdfTextPageHandle);
type PdfTextCountChars = unsafe extern "C" fn(PdfTextPageHandle) -> c_int;
type PdfTextGetUnicode = unsafe extern "C" fn(PdfTextPageHandle, c_int) -> c_ulong;
type PdfTextGetCharBox =
    unsafe extern "C" fn(PdfTextPageHandle, c_int, *mut f64, *mut f64, *mut f64, *mut f64) -> c_int;
type PdfTextGetFontSize = unsafe extern "C" fn(PdfTextPageHandle, c_int) -> f64;
type PdfTextGetFontInfo =
    unsafe extern "C" fn(PdfTextPageHandle, c_int, *mut c_void, c_ulong, *mut c_int) -> c_ulong;
type PdfPageCountObjects = unsafe extern "C" fn(PdfPageHandle) -> c_int;
type PdfPageGetObject = unsafe extern "C" fn(PdfPageHandle, c_int) -> *mut c_void;
type PdfPageObjectGetType = unsafe extern "C" fn(*mut c_void) -> c_int;
type PdfPageObjectGetBounds =
    unsafe extern "C" fn(*mut c_void, *mut f32, *mut f32, *mut f32, *mut f32) -> c_int;

#[repr(C)]
struct PdfFileWrite {
    version: c_int,
    write_block: Option<unsafe extern "C" fn(*mut PdfFileWrite, *const c_void, c_ulong) -> c_int>,
}

#[repr(C)]
struct FileWriter {
    base: PdfFileWrite,
    file: File,
    error: Option<io::Error>,
}

unsafe extern "C" fn write_pdf_block(
    writer: *mut PdfFileWrite,
    data: *const c_void,
    size: c_ulong,
) -> c_int {
    if writer.is_null() || data.is_null() {
        return 0;
    }
    let writer = &mut *(writer as *mut FileWriter);
    let bytes = std::slice::from_raw_parts(data as *const u8, size as usize);
    match writer.file.write_all(bytes) {
        Ok(()) => 1,
        Err(error) => {
            writer.error = Some(error);
            0
        }
    }
}

struct PdfiumApi {
    _library: libloading::Library,
    load_document: PdfLoadDocument,
    create_document: PdfCreateDocument,
    close_document: PdfCloseDocument,
    get_page_count: PdfGetPageCount,
    import_pages: PdfImportPages,
    import_pages_by_index: PdfImportPagesByIndex,
    save_as_copy: PdfSaveAsCopy,
    get_last_error: PdfGetLastError,
    load_page: PdfLoadPage,
    close_page: PdfClosePage,
    get_page_width: PdfGetPageWidth,
    get_page_height: PdfGetPageHeight,
    text_load_page: PdfTextLoadPage,
    text_close_page: PdfTextClosePage,
    text_count_chars: PdfTextCountChars,
    text_get_unicode: PdfTextGetUnicode,
    text_get_char_box: PdfTextGetCharBox,
    text_get_font_size: PdfTextGetFontSize,
    text_get_font_info: PdfTextGetFontInfo,
    page_count_objects: PdfPageCountObjects,
    page_get_object: PdfPageGetObject,
    page_object_get_type: PdfPageObjectGetType,
    page_object_get_bounds: PdfPageObjectGetBounds,
}

unsafe fn pdfium_symbol<T: Copy>(library: &libloading::Library, name: &[u8]) -> Result<T, String> {
    library
        .get::<T>(name)
        .map(|symbol| *symbol)
        .map_err(|error| error.to_string())
}

fn pdfium() -> Result<&'static PdfiumApi, JobFailure> {
    static PDFIUM: OnceLock<Result<PdfiumApi, String>> = OnceLock::new();
    PDFIUM
        .get_or_init(|| unsafe {
            let library =
                libloading::Library::new("libpdfium.so").map_err(|error| error.to_string())?;
            let init_library: PdfInitLibrary = pdfium_symbol(&library, b"FPDF_InitLibrary\0")?;
            init_library();
            Ok(PdfiumApi {
                load_document: pdfium_symbol(&library, b"FPDF_LoadDocument\0")?,
                create_document: pdfium_symbol(&library, b"FPDF_CreateNewDocument\0")?,
                close_document: pdfium_symbol(&library, b"FPDF_CloseDocument\0")?,
                get_page_count: pdfium_symbol(&library, b"FPDF_GetPageCount\0")?,
                import_pages: pdfium_symbol(&library, b"FPDF_ImportPages\0")?,
                import_pages_by_index: pdfium_symbol(&library, b"FPDF_ImportPagesByIndex\0")?,
                save_as_copy: pdfium_symbol(&library, b"FPDF_SaveAsCopy\0")?,
                get_last_error: pdfium_symbol(&library, b"FPDF_GetLastError\0")?,
                load_page: pdfium_symbol(&library, b"FPDF_LoadPage\0")?,
                close_page: pdfium_symbol(&library, b"FPDF_ClosePage\0")?,
                get_page_width: pdfium_symbol(&library, b"FPDF_GetPageWidth\0")?,
                get_page_height: pdfium_symbol(&library, b"FPDF_GetPageHeight\0")?,
                text_load_page: pdfium_symbol(&library, b"FPDFText_LoadPage\0")?,
                text_close_page: pdfium_symbol(&library, b"FPDFText_ClosePage\0")?,
                text_count_chars: pdfium_symbol(&library, b"FPDFText_CountChars\0")?,
                text_get_unicode: pdfium_symbol(&library, b"FPDFText_GetUnicode\0")?,
                text_get_char_box: pdfium_symbol(&library, b"FPDFText_GetCharBox\0")?,
                text_get_font_size: pdfium_symbol(&library, b"FPDFText_GetFontSize\0")?,
                text_get_font_info: pdfium_symbol(&library, b"FPDFText_GetFontInfo\0")?,
                page_count_objects: pdfium_symbol(&library, b"FPDFPage_CountObjects\0")?,
                page_get_object: pdfium_symbol(&library, b"FPDFPage_GetObject\0")?,
                page_object_get_type: pdfium_symbol(&library, b"FPDFPageObj_GetType\0")?,
                page_object_get_bounds: pdfium_symbol(&library, b"FPDFPageObj_GetBounds\0")?,
                _library: library,
            })
        })
        .as_ref()
        .map_err(|message| {
            JobFailure::External(JobError {
                code: "native_backend_unavailable".into(),
                message: message.clone(),
                retryable: true,
            })
        })
}

fn pdfium_failure(api: &PdfiumApi, action: &str) -> JobFailure {
    let code = unsafe { (api.get_last_error)() };
    let (kind, message) = match code {
        2 => (
            "missing_input",
            format!("Could not open a source file while {action}."),
        ),
        3 => (
            "corrupted_pdf",
            format!("A source PDF is damaged or invalid while {action}."),
        ),
        4 => (
            "encrypted_pdf",
            format!("A source PDF requires a password before {action}."),
        ),
        5 => (
            "unsupported_pdf",
            format!("A PDF security scheme is unsupported while {action}."),
        ),
        _ => (
            "native_pdf_failed",
            format!("Native PDF operation failed while {action}."),
        ),
    };
    JobFailure::External(JobError {
        code: kind.into(),
        message,
        retryable: code != 4,
    })
}

fn c_path(path: &str) -> Result<CString, JobFailure> {
    CString::new(path).map_err(|_| {
        JobFailure::External(JobError {
            code: "invalid_path".into(),
            message: "A selected file path contains unsupported characters.".into(),
            retryable: false,
        })
    })
}

fn open_pdf(api: &PdfiumApi, path: &str) -> Result<PdfDocumentHandle, JobFailure> {
    let path = c_path(path)?;
    let document = unsafe { (api.load_document)(path.as_ptr(), std::ptr::null()) };
    if document.is_null() {
        Err(pdfium_failure(api, "opening the PDF"))
    } else {
        Ok(document)
    }
}

fn output_io_failure(error: io::Error) -> JobFailure {
    let code = match error.raw_os_error() {
        Some(28 | 112) => "storage_full",
        Some(13 | 30) => "permission_denied",
        _ if error.kind() == io::ErrorKind::PermissionDenied => "permission_denied",
        _ => "output_unavailable",
    };
    let message = match code {
        "storage_full" => "There is not enough free storage for this output.".into(),
        "permission_denied" => "ArcPDF cannot write to the selected output location.".into(),
        _ => format!("Could not write the output: {error}"),
    };
    JobFailure::External(JobError {
        code: code.into(),
        message,
        retryable: true,
    })
}

fn save_pdf_atomic(
    api: &PdfiumApi,
    document: PdfDocumentHandle,
    output_path: &str,
) -> Result<(), JobFailure> {
    let output = Path::new(output_path);
    if output.exists() {
        return Err(JobFailure::External(JobError {
            code: "output_exists".into(),
            message: "The output file already exists.".into(),
            retryable: true,
        }));
    }
    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent).map_err(output_io_failure)?;
    }
    let temporary = PathBuf::from(format!("{output_path}.arcpdf-part"));
    let _ = fs::remove_file(&temporary);
    let file = File::create(&temporary).map_err(output_io_failure)?;
    let mut writer = FileWriter {
        base: PdfFileWrite {
            version: 1,
            write_block: Some(write_pdf_block),
        },
        file,
        error: None,
    };
    let saved = unsafe { (api.save_as_copy)(document, &mut writer.base, 0) } != 0;
    if saved {
        if let Err(error) = writer.file.flush() {
            drop(writer);
            let _ = fs::remove_file(&temporary);
            return Err(output_io_failure(error));
        }
    } else if let Some(error) = writer.error.take() {
        drop(writer);
        let _ = fs::remove_file(&temporary);
        return Err(output_io_failure(error));
    }
    drop(writer);
    if !saved {
        let _ = fs::remove_file(&temporary);
        return Err(pdfium_failure(api, "saving the PDF"));
    }
    fs::rename(&temporary, output).map_err(|error| {
        let _ = fs::remove_file(&temporary);
        output_io_failure(error)
    })
}

fn run_native_pdf(
    request: NativePdfRequest,
    record: &Arc<JobRecord>,
) -> Result<serde_json::Value, JobFailure> {
    let api = pdfium()?;
    match request.operation.as_str() {
        "merge" => native_merge(api, &request, record),
        "organize" => native_organize(api, &request, record),
        "split" => native_split(api, &request, record),
        _ => Err(JobFailure::External(JobError {
            code: "unsupported_operation".into(),
            message: "The requested native PDF operation is not supported.".into(),
            retryable: false,
        })),
    }
}

fn run_reflow(
    request: ReflowRequest,
    record: &Arc<JobRecord>,
) -> Result<serde_json::Value, JobFailure> {
    reflow::run(request, record)
}

fn native_merge(
    api: &PdfiumApi,
    request: &NativePdfRequest,
    record: &Arc<JobRecord>,
) -> Result<serde_json::Value, JobFailure> {
    if request.input_paths.len() < 2 {
        return Err(JobFailure::External(JobError {
            code: "missing_input".into(),
            message: "Select at least two PDFs to merge.".into(),
            retryable: true,
        }));
    }
    let output = unsafe { (api.create_document)() };
    if output.is_null() {
        return Err(pdfium_failure(api, "creating the merged PDF"));
    }
    let result = (|| {
        for (index, path) in request.input_paths.iter().enumerate() {
            if record.is_cancelled() {
                return Err(JobFailure::Cancelled);
            }
            record.update(
                &format!(
                    "Merging file {} of {}",
                    index + 1,
                    request.input_paths.len()
                ),
                Some(index as f64 / request.input_paths.len() as f64),
                index,
                Some(request.input_paths.len()),
            );
            let source = open_pdf(api, path)?;
            let page_count = unsafe { (api.get_page_count)(output) };
            let imported =
                unsafe { (api.import_pages)(output, source, std::ptr::null(), page_count) } != 0;
            unsafe { (api.close_document)(source) };
            if !imported {
                return Err(pdfium_failure(api, "importing pages"));
            }
        }
        record.update(
            "Writing merged PDF",
            Some(0.95),
            request.input_paths.len(),
            Some(request.input_paths.len()),
        );
        save_pdf_atomic(api, output, &request.output_path)?;
        Ok(serde_json::json!({ "outputPath": request.output_path }))
    })();
    unsafe { (api.close_document)(output) };
    result
}

fn native_organize(
    api: &PdfiumApi,
    request: &NativePdfRequest,
    record: &Arc<JobRecord>,
) -> Result<serde_json::Value, JobFailure> {
    let input = request.input_path.as_deref().ok_or_else(|| {
        JobFailure::External(JobError {
            code: "missing_input".into(),
            message: "No source PDF was provided.".into(),
            retryable: true,
        })
    })?;
    if request.pages.is_empty() {
        return Err(JobFailure::External(JobError {
            code: "invalid_selection".into(),
            message: "Select at least one page.".into(),
            retryable: true,
        }));
    }
    let source = open_pdf(api, input)?;
    let output = unsafe { (api.create_document)() };
    if output.is_null() {
        unsafe { (api.close_document)(source) };
        return Err(pdfium_failure(api, "creating the organized PDF"));
    }
    let zero_based: Vec<c_int> = request.pages.iter().map(|page| page - 1).collect();
    record.update(
        "Importing selected pages",
        Some(0.35),
        0,
        Some(zero_based.len()),
    );
    let imported = unsafe {
        (api.import_pages_by_index)(
            output,
            source,
            zero_based.as_ptr(),
            zero_based.len() as c_ulong,
            0,
        )
    } != 0;
    let result = if !imported {
        Err(pdfium_failure(api, "organizing pages"))
    } else if record.is_cancelled() {
        Err(JobFailure::Cancelled)
    } else {
        record.update(
            "Writing PDF",
            Some(0.9),
            zero_based.len(),
            Some(zero_based.len()),
        );
        save_pdf_atomic(api, output, &request.output_path)
            .map(|_| serde_json::json!({ "outputPath": request.output_path }))
    };
    unsafe {
        (api.close_document)(output);
        (api.close_document)(source);
    }
    result
}

fn native_split(
    api: &PdfiumApi,
    request: &NativePdfRequest,
    record: &Arc<JobRecord>,
) -> Result<serde_json::Value, JobFailure> {
    let input = request.input_path.as_deref().ok_or_else(|| {
        JobFailure::External(JobError {
            code: "missing_input".into(),
            message: "No source PDF was provided.".into(),
            retryable: true,
        })
    })?;
    let source = open_pdf(api, input)?;
    let page_count = unsafe { (api.get_page_count)(source) };
    let parsed_groups;
    let groups = if request.groups.is_empty() {
        parsed_groups = match parse_native_page_groups(
            request.selection.as_deref().unwrap_or_default(),
            page_count,
        ) {
            Ok(groups) => groups,
            Err(error) => {
                unsafe { (api.close_document)(source) };
                return Err(error);
            }
        };
        &parsed_groups
    } else {
        &request.groups
    };
    let output_dir = Path::new(&request.output_path);
    if let Err(error) = fs::create_dir_all(output_dir) {
        unsafe { (api.close_document)(source) };
        return Err(output_io_failure(error));
    }
    let mut outputs = Vec::new();
    let result = (|| {
        for (index, group) in groups.iter().enumerate() {
            if record.is_cancelled() {
                return Err(JobFailure::Cancelled);
            }
            record.update(
                &format!("Creating file {} of {}", index + 1, groups.len()),
                Some(index as f64 / groups.len().max(1) as f64),
                index,
                Some(groups.len()),
            );
            let output = unsafe { (api.create_document)() };
            if output.is_null() {
                return Err(pdfium_failure(api, "creating a split PDF"));
            }
            let pages: Vec<c_int> = group.pages.iter().map(|page| page - 1).collect();
            let imported = unsafe {
                (api.import_pages_by_index)(
                    output,
                    source,
                    pages.as_ptr(),
                    pages.len() as c_ulong,
                    0,
                )
            } != 0;
            if !imported {
                unsafe { (api.close_document)(output) };
                return Err(pdfium_failure(api, "splitting pages"));
            }
            let name = if group.start == group.end {
                format!("page_{}.pdf", group.start)
            } else {
                format!("pages_{}-{}.pdf", group.start, group.end)
            };
            let path = output_dir.join(name);
            let path_string = path.to_string_lossy().into_owned();
            let save_result = save_pdf_atomic(api, output, &path_string);
            unsafe { (api.close_document)(output) };
            save_result?;
            outputs.push(path_string);
        }
        Ok(serde_json::json!({
            "outputPath": request.output_path,
            "outputFiles": outputs,
        }))
    })();
    unsafe { (api.close_document)(source) };
    if result.is_err() {
        let _ = fs::remove_dir_all(output_dir);
    }
    result
}

fn parse_native_page_groups(
    selection: &str,
    page_count: c_int,
) -> Result<Vec<NativePdfPageGroup>, JobFailure> {
    let mut groups = Vec::new();
    let mut claimed = HashSet::new();
    for raw in selection.split(',') {
        let token = raw.trim();
        if token.is_empty() {
            return Err(invalid_page_selection());
        }
        let (start, end) = match token.split_once('-') {
            Some((start, end)) => (
                start.trim().parse::<i32>().ok(),
                end.trim().parse::<i32>().ok(),
            ),
            None => {
                let value = token.parse::<i32>().ok();
                (value, value)
            }
        };
        let (Some(start), Some(end)) = (start, end) else {
            return Err(invalid_page_selection());
        };
        if start < 1 || end < start || end > page_count {
            return Err(invalid_page_selection());
        }
        let pages: Vec<i32> = (start..=end).filter(|page| claimed.insert(*page)).collect();
        if !pages.is_empty() {
            groups.push(NativePdfPageGroup { start, end, pages });
        }
    }
    if groups.is_empty() {
        return Err(invalid_page_selection());
    }
    Ok(groups)
}

fn invalid_page_selection() -> JobFailure {
    JobFailure::External(JobError {
        code: "invalid_selection".into(),
        message: "Enter valid page numbers or ranges, such as 1, 3-5, 8.".into(),
        retryable: true,
    })
}

fn error_json(message: &str) -> String {
    serde_json::json!({ "error": message }).to_string()
}

#[no_mangle]
pub unsafe extern "C" fn arcpdf_scan_json(request: *const c_char) -> *mut c_char {
    let response = if request.is_null() {
        error_json("request pointer was null")
    } else {
        match CStr::from_ptr(request)
            .to_str()
            .ok()
            .and_then(|value| serde_json::from_str::<ScanRequest>(value).ok())
        {
            Some(request) => serde_json::to_string(&scan(request))
                .unwrap_or_else(|_| error_json("response serialization failed")),
            None => error_json("invalid scan request"),
        }
    };
    CString::new(response).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn arcpdf_job_submit_json(request: *const c_char) -> u64 {
    if request.is_null() {
        return 0;
    }
    let Some((kind, command)) = CStr::from_ptr(request)
        .to_str()
        .ok()
        .and_then(|value| serde_json::from_str::<JobSubmitRequest>(value).ok())
        .map(|value| match value {
            JobSubmitRequest::Scan(request) => ("scan".to_string(), JobCommand::Scan(request)),
            JobSubmitRequest::External(request) => (request.operation, JobCommand::External),
            JobSubmitRequest::NativePdf(request) => {
                (request.operation.clone(), JobCommand::NativePdf(request))
            }
            JobSubmitRequest::Reflow(request) => {
                ("reflow".to_string(), JobCommand::Reflow(request))
            }
        })
    else {
        return 0;
    };
    let runtime = job_runtime();
    let id = runtime.next_id.fetch_add(1, Ordering::Relaxed);
    let record = Arc::new(JobRecord {
        snapshot: Mutex::new(JobSnapshot {
            job_id: id,
            kind,
            state: "queued".into(),
            stage: "Waiting".into(),
            progress: None,
            processed: 0,
            total: None,
            error: None,
            result: None,
        }),
        cancelled: AtomicBool::new(false),
        external_result: Mutex::new(None),
        changed: Condvar::new(),
    });
    runtime.jobs.lock().unwrap().insert(id, record);
    if runtime.sender.send(JobEnvelope { id, command }).is_err() {
        runtime.jobs.lock().unwrap().remove(&id);
        return 0;
    }
    id
}

#[no_mangle]
pub extern "C" fn arcpdf_job_snapshot_json(job_id: u64) -> *mut c_char {
    let runtime = job_runtime();
    let value = runtime.jobs.lock().unwrap().get(&job_id).cloned();
    let json = match value {
        Some(record) => serde_json::to_string(&record.snapshot.lock().unwrap().clone())
            .unwrap_or_else(|_| error_json("job snapshot serialization failed")),
        None => error_json("job not found"),
    };
    CString::new(json).unwrap().into_raw()
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExternalJobUpdate {
    stage: String,
    progress: Option<f64>,
    #[serde(default)]
    processed: usize,
    total: Option<usize>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExternalJobCompletion {
    result: Option<serde_json::Value>,
    error: Option<JobError>,
}

#[no_mangle]
pub unsafe extern "C" fn arcpdf_job_update_json(job_id: u64, update: *const c_char) -> bool {
    if update.is_null() {
        return false;
    }
    let Some(update) = CStr::from_ptr(update)
        .to_str()
        .ok()
        .and_then(|value| serde_json::from_str::<ExternalJobUpdate>(value).ok())
    else {
        return false;
    };
    let runtime = job_runtime();
    let Some(record) = runtime.jobs.lock().unwrap().get(&job_id).cloned() else {
        return false;
    };
    if record.is_cancelled() {
        return false;
    }
    record.update(
        &update.stage,
        update.progress.map(|value| value.clamp(0.0, 1.0)),
        update.processed,
        update.total,
    );
    true
}

#[no_mangle]
pub unsafe extern "C" fn arcpdf_job_complete_json(job_id: u64, completion: *const c_char) -> bool {
    if completion.is_null() {
        return false;
    }
    let Some(completion) = CStr::from_ptr(completion)
        .to_str()
        .ok()
        .and_then(|value| serde_json::from_str::<ExternalJobCompletion>(value).ok())
    else {
        return false;
    };
    let runtime = job_runtime();
    let Some(record) = runtime.jobs.lock().unwrap().get(&job_id).cloned() else {
        return false;
    };
    if record.is_cancelled() {
        return false;
    }
    let value = match (completion.result, completion.error) {
        (Some(result), None) => Ok(result),
        (_, Some(error)) => Err(error),
        _ => Err(JobError {
            code: "invalid_completion".into(),
            message: "The operation returned no result.".into(),
            retryable: true,
        }),
    };
    *record.external_result.lock().unwrap() = Some(value);
    record.changed.notify_all();
    true
}

#[no_mangle]
pub extern "C" fn arcpdf_job_cancel(job_id: u64) -> bool {
    let runtime = job_runtime();
    let Some(record) = runtime.jobs.lock().unwrap().get(&job_id).cloned() else {
        return false;
    };
    let state = record.snapshot.lock().unwrap().state.clone();
    if matches!(state.as_str(), "completed" | "failed" | "cancelled") {
        return false;
    }
    record.cancelled.store(true, Ordering::Relaxed);
    record.changed.notify_all();
    if state == "queued" {
        finish_cancelled(&record);
    }
    true
}

#[no_mangle]
pub extern "C" fn arcpdf_job_release(job_id: u64) {
    let runtime = job_runtime();
    let removable = runtime
        .jobs
        .lock()
        .unwrap()
        .get(&job_id)
        .is_some_and(|record| {
            matches!(
                record.snapshot.lock().unwrap().state.as_str(),
                "completed" | "failed" | "cancelled"
            )
        });
    if removable {
        runtime.jobs.lock().unwrap().remove(&job_id);
    }
}

#[no_mangle]
pub unsafe extern "C" fn arcpdf_free_string(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn detects_exact_duplicates_but_not_same_size_files() {
        let root = std::env::temp_dir().join(format!("arcpdf-indexer-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        let pdf = b"%PDF-1.7\nidentical document\n%%EOF";
        fs::write(root.join("a.pdf"), pdf).unwrap();
        fs::write(root.join("b.pdf"), pdf).unwrap();
        let mut other = File::create(root.join("c.pdf")).unwrap();
        other
            .write_all(b"%PDF-1.7\ndifferent document!\n%%EOF")
            .unwrap();
        let response = scan(ScanRequest {
            roots: vec![root.to_string_lossy().into_owned()],
            excluded_roots: vec![],
            cache_path: None,
            max_workers: Some(2),
        });
        assert_eq!(response.files.len(), 3);
        assert_eq!(response.duplicate_groups.len(), 1);
        assert_eq!(response.duplicate_groups[0].paths.len(), 2);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn split_selection_preserves_range_groups_and_deduplicates_pages() {
        let groups = parse_native_page_groups("1, 3-5, 5, 7", 8).unwrap();
        assert_eq!(groups.len(), 3);
        assert_eq!(groups[0].pages, vec![1]);
        assert_eq!(groups[1].pages, vec![3, 4, 5]);
        assert_eq!(groups[2].pages, vec![7]);
        assert!(parse_native_page_groups("1, 9", 8).is_err());
    }
}
