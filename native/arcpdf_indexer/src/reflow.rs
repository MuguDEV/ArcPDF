use super::*;
use serde::Serialize;
use std::cmp::Ordering as CmpOrdering;

const ENGINE_VERSION: i32 = 4;

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct SourceAnchor {
    page: i32,
    bounds: [f64; 4],
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct Glyph {
    text: String,
    bounds: [f64; 4],
    font_name: String,
    font_size: f64,
    baseline: f64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Block {
    #[serde(rename = "type")]
    kind: &'static str,
    anchor: SourceAnchor,
    text: String,
    glyphs: Vec<Glyph>,
    rows: Vec<Vec<String>>,
    caption: Option<String>,
    heading_level: Option<i32>,
    confidence: f64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Document {
    file_hash: String,
    engine_version: i32,
    settings_key: String,
    page_count: i32,
    blocks: Vec<Block>,
    ocr_pages: Vec<i32>,
}

#[derive(Clone)]
struct Line {
    page: i32,
    text: String,
    bounds: [f64; 4],
    font_name: String,
    font_size: f64,
    glyphs: Vec<Glyph>,
    cells: Vec<String>,
    confidence: f64,
}

struct PageLayout {
    number: i32,
    width: f64,
    height: f64,
    lines: Vec<Line>,
    images: Vec<[f64; 4]>,
    vector_regions: Vec<[f64; 4]>,
}

pub(super) fn run(
    request: ReflowRequest,
    record: &Arc<JobRecord>,
) -> Result<serde_json::Value, JobFailure> {
    if record.is_cancelled() {
        return Err(JobFailure::Cancelled);
    }
    record.update("Hashing document", None, 0, None);
    let hash = hash_input(&request.input_path, record)?;
    if let Some(cache_path) = request.cache_path.as_deref() {
        if let Some(value) = read_cache(cache_path, &hash, &request.settings_key) {
            record.update("Loaded reflow cache", Some(1.0), 1, Some(1));
            return Ok(value);
        }
    }

    let api = pdfium()?;
    let document = open_pdf(api, &request.input_path)?;
    let page_count = unsafe { (api.get_page_count)(document) };
    if page_count <= 0 {
        unsafe { (api.close_document)(document) };
        return Err(JobFailure::External(JobError {
            code: "empty_pdf".into(),
            message: "This PDF has no readable pages.".into(),
            retryable: false,
        }));
    }

    let mut pages = Vec::with_capacity(page_count as usize);
    for index in 0..page_count {
        if record.is_cancelled() {
            unsafe { (api.close_document)(document) };
            return Err(JobFailure::Cancelled);
        }
        record.update(
            "Extracting text geometry",
            Some(index as f64 / page_count as f64 * 0.72),
            index as usize,
            Some(page_count as usize),
        );
        match extract_page(api, document, index) {
            Ok(page) => pages.push(page),
            Err(error) => {
                unsafe { (api.close_document)(document) };
                return Err(error);
            }
        }
    }
    unsafe { (api.close_document)(document) };

    record.update(
        "Reconstructing reading order",
        Some(0.78),
        page_count as usize,
        Some(page_count as usize),
    );
    merge_ocr_lines(&mut pages, &request.ocr_pages);
    let ocr_pages = pages_requiring_ocr(&pages);
    let repeated = if request.remove_repeated_headers {
        repeated_running_content(&pages)
    } else {
        HashSet::new()
    };
    let mut blocks = Vec::new();
    for (done, mut page) in pages.into_iter().enumerate() {
        if record.is_cancelled() {
            return Err(JobFailure::Cancelled);
        }
        page.lines
            .retain(|line| !repeated.contains(&running_key(&line.text)));
        order_lines(&mut page.lines, page.width);
        build_page_blocks(
            &page,
            request.detect_tables,
            request.detect_figures,
            &mut blocks,
        );
        blocks.push(Block {
            kind: "pageBreak",
            anchor: SourceAnchor {
                page: page.number,
                bounds: [0.0, page.height, page.width, page.height],
            },
            text: String::new(),
            glyphs: Vec::new(),
            rows: Vec::new(),
            caption: None,
            heading_level: None,
            confidence: 1.0,
        });
        record.update(
            "Building structured blocks",
            Some(0.78 + 0.20 * (done + 1) as f64 / page_count as f64),
            done + 1,
            Some(page_count as usize),
        );
    }

    let result = serde_json::to_value(Document {
        file_hash: hash,
        engine_version: ENGINE_VERSION,
        settings_key: request.settings_key,
        page_count,
        blocks,
        ocr_pages: if request.ocr_pages.is_empty() {
            ocr_pages.clone()
        } else {
            Vec::new()
        },
    })
    .map_err(|_| JobFailure::Serialization)?;
    if (ocr_pages.is_empty() || !request.ocr_pages.is_empty())
        && request.cache_path.as_deref().is_some()
    {
        let cache_path = request.cache_path.as_deref().unwrap();
        record.update(
            "Saving reflow cache",
            Some(0.99),
            page_count as usize,
            Some(page_count as usize),
        );
        write_cache(cache_path, &result)?;
    }
    Ok(result)
}

fn hash_input(path: &str, record: &Arc<JobRecord>) -> Result<String, JobFailure> {
    let mut file = File::open(path).map_err(|error| input_error(error, path))?;
    let mut hasher = blake3::Hasher::new();
    let mut buffer = vec![0_u8; 256 * 1024];
    loop {
        if record.is_cancelled() {
            return Err(JobFailure::Cancelled);
        }
        let count = file
            .read(&mut buffer)
            .map_err(|error| input_error(error, path))?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    Ok(hasher.finalize().to_hex().to_string())
}

fn input_error(error: io::Error, path: &str) -> JobFailure {
    JobFailure::External(JobError {
        code: if error.kind() == io::ErrorKind::PermissionDenied {
            "permission_denied".into()
        } else {
            "missing_input".into()
        },
        message: format!("Could not read {path}: {error}"),
        retryable: true,
    })
}

fn read_cache(path: &str, hash: &str, settings: &str) -> Option<serde_json::Value> {
    let bytes = fs::read(path).ok()?;
    let value: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    if value.get("fileHash")?.as_str()? == hash
        && value.get("engineVersion")?.as_i64()? == ENGINE_VERSION as i64
        && value.get("settingsKey")?.as_str()? == settings
    {
        Some(value)
    } else {
        None
    }
}

fn write_cache(path: &str, value: &serde_json::Value) -> Result<(), JobFailure> {
    let target = Path::new(path);
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(output_io_failure)?;
    }
    let temporary = PathBuf::from(format!("{path}.arcpdf-part"));
    let bytes = serde_json::to_vec(value).map_err(|_| JobFailure::Serialization)?;
    fs::write(&temporary, bytes).map_err(output_io_failure)?;
    fs::rename(&temporary, target).map_err(|error| {
        let _ = fs::remove_file(&temporary);
        output_io_failure(error)
    })
}

fn extract_page(
    api: &PdfiumApi,
    document: PdfDocumentHandle,
    index: i32,
) -> Result<PageLayout, JobFailure> {
    let page = unsafe { (api.load_page)(document, index) };
    if page.is_null() {
        return Err(pdfium_failure(api, "loading a page for reflow"));
    }
    let width = unsafe { (api.get_page_width)(page) };
    let height = unsafe { (api.get_page_height)(page) };
    let text_page = unsafe { (api.text_load_page)(page) };
    if text_page.is_null() {
        unsafe { (api.close_page)(page) };
        return Err(pdfium_failure(api, "loading page text"));
    }
    let count = unsafe { (api.text_count_chars)(text_page) }.max(0);
    let mut glyphs = Vec::with_capacity(count as usize);
    for char_index in 0..count {
        let scalar = unsafe { (api.text_get_unicode)(text_page, char_index) } as u32;
        let Some(character) = char::from_u32(scalar) else {
            continue;
        };
        if character == '\r' || character == '\n' || character == '\0' {
            continue;
        }
        let mut left = 0.0;
        let mut right = 0.0;
        let mut bottom = 0.0;
        let mut top = 0.0;
        let valid = unsafe {
            (api.text_get_char_box)(
                text_page,
                char_index,
                &mut left,
                &mut right,
                &mut bottom,
                &mut top,
            )
        } != 0;
        if !valid || !left.is_finite() || !top.is_finite() {
            continue;
        }
        let font_size = unsafe { (api.text_get_font_size)(text_page, char_index) };
        glyphs.push(Glyph {
            text: character.to_string(),
            bounds: [left, height - top, right, height - bottom],
            font_name: font_name(api, text_page, char_index),
            font_size: if font_size.is_finite() {
                font_size
            } else {
                0.0
            },
            baseline: height - bottom,
        });
    }
    unsafe {
        (api.text_close_page)(text_page);
    }
    let (images, vector_regions) = page_regions(api, page, width, height);
    unsafe { (api.close_page)(page) };
    Ok(PageLayout {
        number: index + 1,
        width,
        height,
        lines: cluster_lines(index + 1, glyphs),
        images,
        vector_regions,
    })
}

fn page_regions(
    api: &PdfiumApi,
    page: PdfPageHandle,
    width: f64,
    height: f64,
) -> (Vec<[f64; 4]>, Vec<[f64; 4]>) {
    let count = unsafe { (api.page_count_objects)(page) }.max(0);
    let mut images = Vec::new();
    let mut paths = Vec::new();
    for index in 0..count {
        let object = unsafe { (api.page_get_object)(page, index) };
        if object.is_null() {
            continue;
        }
        let object_type = unsafe { (api.page_object_get_type)(object) };
        if object_type != 2 && object_type != 3 {
            continue;
        }
        let mut left = 0_f32;
        let mut bottom = 0_f32;
        let mut right = 0_f32;
        let mut top = 0_f32;
        if unsafe {
            (api.page_object_get_bounds)(object, &mut left, &mut bottom, &mut right, &mut top)
        } == 0
        {
            continue;
        }
        let bounds = [
            left as f64,
            height - top as f64,
            right as f64,
            height - bottom as f64,
        ];
        let area = (bounds[2] - bounds[0]).max(0.0) * (bounds[3] - bounds[1]).max(0.0);
        if object_type == 3 && area >= width * height * 0.008 {
            images.push(bounds);
        } else if object_type == 2 && area > 1.0 && area < width * height * 0.9 {
            paths.push(bounds);
        }
    }
    (images, cluster_vector_regions(paths, width, height))
}

fn cluster_vector_regions(
    paths: Vec<[f64; 4]>,
    page_width: f64,
    page_height: f64,
) -> Vec<[f64; 4]> {
    let mut clusters: Vec<([f64; 4], usize)> = Vec::new();
    for bounds in paths {
        let matching = clusters
            .iter()
            .position(|(region, _)| regions_near(*region, bounds, 10.0));
        if let Some(index) = matching {
            clusters[index].0 = union(clusters[index].0, bounds);
            clusters[index].1 += 1;
        } else {
            clusters.push((bounds, 1));
        }
    }
    // A second merge joins groups connected transitively by axes, grid lines,
    // legends, and plot marks encountered in a different object order.
    let mut changed = true;
    while changed {
        changed = false;
        'outer: for left in 0..clusters.len() {
            for right in left + 1..clusters.len() {
                if regions_near(clusters[left].0, clusters[right].0, 14.0) {
                    let other = clusters.remove(right);
                    clusters[left].0 = union(clusters[left].0, other.0);
                    clusters[left].1 += other.1;
                    changed = true;
                    break 'outer;
                }
            }
        }
    }
    clusters
        .into_iter()
        .filter_map(|(bounds, objects)| {
            let area = (bounds[2] - bounds[0]).max(0.0) * (bounds[3] - bounds[1]).max(0.0);
            let page_area = page_width * page_height;
            // Page borders, form decorations, and background paths can connect
            // otherwise unrelated vectors into one page-sized cluster. Such a
            // cluster is not a useful chart crop and caused reflow to render the
            // whole PDF page as every chart preview.
            if objects >= 4 && area >= page_area * 0.02 && area <= page_area * 0.80 {
                Some(bounds)
            } else {
                None
            }
        })
        .collect()
}

fn regions_near(a: [f64; 4], b: [f64; 4], padding: f64) -> bool {
    a[0] - padding <= b[2]
        && a[2] + padding >= b[0]
        && a[1] - padding <= b[3]
        && a[3] + padding >= b[1]
}

fn pages_requiring_ocr(pages: &[PageLayout]) -> Vec<i32> {
    pages
        .iter()
        .filter(|page| {
            let text_characters: usize = page.lines.iter().map(|line| line.text.len()).sum();
            let image_area: f64 = page
                .images
                .iter()
                .map(|bounds| (bounds[2] - bounds[0]).max(0.0) * (bounds[3] - bounds[1]).max(0.0))
                .sum();
            text_characters < 24 && image_area >= page.width * page.height * 0.35
        })
        .map(|page| page.number)
        .collect()
}

fn merge_ocr_lines(pages: &mut [PageLayout], ocr_pages: &[ReflowOcrPage]) {
    for recognized in ocr_pages {
        let Some(page) = pages.iter_mut().find(|page| page.number == recognized.page) else {
            continue;
        };
        if recognized.lines.is_empty() {
            continue;
        }
        let extracted_characters: usize = page.lines.iter().map(|line| line.text.len()).sum();
        if extracted_characters >= 24 {
            continue;
        }
        page.lines = recognized
            .lines
            .iter()
            .filter_map(|line| ocr_line(page.number, page.width, page.height, line))
            .collect();
    }
}

fn ocr_line(page: i32, width: f64, height: f64, source: &ReflowOcrLine) -> Option<Line> {
    let text = source.text.trim();
    if text.is_empty() || source.bounds.iter().any(|value| !value.is_finite()) {
        return None;
    }
    let bounds = [
        source.bounds[0].clamp(0.0, width),
        source.bounds[1].clamp(0.0, height),
        source.bounds[2].clamp(0.0, width),
        source.bounds[3].clamp(0.0, height),
    ];
    if bounds[2] <= bounds[0] || bounds[3] <= bounds[1] {
        return None;
    }
    let font_size = (bounds[3] - bounds[1]).max(6.0);
    let element_confidences: Vec<f64> = source
        .elements
        .iter()
        .filter_map(|element| element.confidence)
        .collect();
    let inferred_confidence = if element_confidences.is_empty() {
        0.72
    } else {
        element_confidences.iter().sum::<f64>() / element_confidences.len() as f64
    };
    let confidence = source
        .confidence
        .unwrap_or(inferred_confidence)
        .clamp(0.0, 1.0);
    let mut glyphs: Vec<Glyph> = source
        .elements
        .iter()
        .filter_map(|element| {
            let value = element.text.trim();
            if value.is_empty() || element.bounds.iter().any(|value| !value.is_finite()) {
                return None;
            }
            let element_bounds = [
                element.bounds[0].clamp(bounds[0], bounds[2]),
                element.bounds[1].clamp(bounds[1], bounds[3]),
                element.bounds[2].clamp(bounds[0], bounds[2]),
                element.bounds[3].clamp(bounds[1], bounds[3]),
            ];
            if element_bounds[2] <= element_bounds[0] || element_bounds[3] <= element_bounds[1] {
                return None;
            }
            let size = (element_bounds[3] - element_bounds[1]).max(6.0);
            Some(Glyph {
                text: value.to_string(),
                bounds: element_bounds,
                font_name: "ArcPDF OCR".into(),
                font_size: size,
                baseline: element_bounds[3],
            })
        })
        .collect();
    glyphs.sort_by(|a, b| {
        a.bounds[0]
            .partial_cmp(&b.bounds[0])
            .unwrap_or(CmpOrdering::Equal)
    });
    if glyphs.is_empty() {
        glyphs.push(Glyph {
            text: text.to_string(),
            bounds,
            font_name: "ArcPDF OCR".into(),
            font_size,
            baseline: bounds[3],
        });
    }
    let cells = ocr_cells(&glyphs, font_size);
    Some(Line {
        page,
        text: text.to_string(),
        bounds,
        font_name: "ArcPDF OCR".into(),
        font_size,
        glyphs,
        cells,
        confidence,
    })
}

fn ocr_cells(elements: &[Glyph], font_size: f64) -> Vec<String> {
    if elements.len() < 2 {
        return Vec::new();
    }
    let mut cells = Vec::new();
    let mut current = elements[0].text.clone();
    let mut previous_right = elements[0].bounds[2];
    for element in &elements[1..] {
        let gap = element.bounds[0] - previous_right;
        if gap > font_size.max(8.0) * 1.8 {
            cells.push(current.trim().to_string());
            current = element.text.clone();
        } else {
            current.push(' ');
            current.push_str(&element.text);
        }
        previous_right = element.bounds[2];
    }
    cells.push(current.trim().to_string());
    if cells.len() > 1 {
        cells
    } else {
        Vec::new()
    }
}

fn font_name(api: &PdfiumApi, text_page: PdfTextPageHandle, index: i32) -> String {
    let mut flags = 0;
    let length =
        unsafe { (api.text_get_font_info)(text_page, index, std::ptr::null_mut(), 0, &mut flags) };
    if length <= 1 || length > 512 {
        return String::new();
    }
    let mut bytes = vec![0_u8; length as usize];
    unsafe {
        (api.text_get_font_info)(
            text_page,
            index,
            bytes.as_mut_ptr() as *mut c_void,
            length,
            &mut flags,
        );
    }
    while bytes.last() == Some(&0) {
        bytes.pop();
    }
    String::from_utf8_lossy(&bytes).into_owned()
}

fn cluster_lines(page: i32, mut glyphs: Vec<Glyph>) -> Vec<Line> {
    glyphs.sort_by(|a, b| {
        a.bounds[1]
            .partial_cmp(&b.bounds[1])
            .unwrap_or(CmpOrdering::Equal)
            .then_with(|| {
                a.bounds[0]
                    .partial_cmp(&b.bounds[0])
                    .unwrap_or(CmpOrdering::Equal)
            })
    });
    let mut groups: Vec<Vec<Glyph>> = Vec::new();
    for glyph in glyphs {
        let center = (glyph.bounds[1] + glyph.bounds[3]) * 0.5;
        let target = groups.iter().position(|line| {
            let sample = &line[0];
            let sample_center = (sample.bounds[1] + sample.bounds[3]) * 0.5;
            (center - sample_center).abs() <= glyph.font_size.max(sample.font_size).max(6.0) * 0.55
        });
        match target {
            Some(index) => groups[index].push(glyph),
            None => groups.push(vec![glyph]),
        }
    }
    groups
        .into_iter()
        .filter_map(|mut glyphs| {
            glyphs.sort_by(|a, b| {
                a.bounds[0]
                    .partial_cmp(&b.bounds[0])
                    .unwrap_or(CmpOrdering::Equal)
            });
            let visible: Vec<&Glyph> = glyphs
                .iter()
                .filter(|glyph| !glyph.text.trim().is_empty())
                .collect();
            if visible.is_empty() {
                return None;
            }
            let font_size = median(
                visible
                    .iter()
                    .map(|glyph| glyph.font_size)
                    .filter(|v| *v > 0.0)
                    .collect(),
            );
            let mut text = String::new();
            let mut cells = Vec::new();
            let mut cell = String::new();
            let mut previous_right: Option<f64> = None;
            for glyph in &glyphs {
                if glyph.text.trim().is_empty() {
                    if !text.ends_with(' ') {
                        text.push(' ');
                    }
                    if !cell.ends_with(' ') {
                        cell.push(' ');
                    }
                    continue;
                }
                if let Some(right) = previous_right {
                    let gap = glyph.bounds[0] - right;
                    if gap > font_size.max(8.0) * 1.8 && !cell.trim().is_empty() {
                        cells.push(cell.trim().to_string());
                        cell.clear();
                        if !text.ends_with(' ') {
                            text.push(' ');
                        }
                    } else if gap > font_size.max(8.0) * 0.28 && !text.ends_with(' ') {
                        text.push(' ');
                        cell.push(' ');
                    }
                }
                text.push_str(&glyph.text);
                cell.push_str(&glyph.text);
                previous_right = Some(glyph.bounds[2]);
            }
            if !cell.trim().is_empty() {
                cells.push(cell.trim().to_string());
            }
            if cells.len() < 2 {
                cells.clear();
            }
            let bounds = glyphs.iter().fold(
                [
                    f64::INFINITY,
                    f64::INFINITY,
                    f64::NEG_INFINITY,
                    f64::NEG_INFINITY,
                ],
                |mut rect, glyph| {
                    rect[0] = rect[0].min(glyph.bounds[0]);
                    rect[1] = rect[1].min(glyph.bounds[1]);
                    rect[2] = rect[2].max(glyph.bounds[2]);
                    rect[3] = rect[3].max(glyph.bounds[3]);
                    rect
                },
            );
            let font_name = visible
                .iter()
                .find(|glyph| !glyph.font_name.is_empty())
                .map(|glyph| glyph.font_name.clone())
                .unwrap_or_default();
            Some(Line {
                page,
                text: text.trim().to_string(),
                bounds,
                font_name,
                font_size,
                glyphs,
                cells,
                confidence: 0.99,
            })
        })
        .collect()
}

fn median(mut values: Vec<f64>) -> f64 {
    if values.is_empty() {
        return 11.0;
    }
    values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(CmpOrdering::Equal));
    values[values.len() / 2]
}

fn repeated_running_content(pages: &[PageLayout]) -> HashSet<String> {
    if pages.len() < 3 {
        return HashSet::new();
    }
    let mut occurrences: HashMap<String, HashSet<i32>> = HashMap::new();
    for page in pages {
        for line in &page.lines {
            if line.bounds[1] <= page.height * 0.13 || line.bounds[3] >= page.height * 0.88 {
                let key = running_key(&line.text);
                if key.len() >= 3 {
                    occurrences.entry(key).or_default().insert(page.number);
                }
            }
        }
    }
    let threshold = ((pages.len() as f64 * 0.6).ceil() as usize).max(2);
    occurrences
        .into_iter()
        .filter(|(_, pages)| pages.len() >= threshold)
        .map(|(key, _)| key)
        .collect()
}

fn running_key(value: &str) -> String {
    let mut result = String::new();
    let mut in_space = false;
    for character in value.to_lowercase().chars() {
        if character.is_ascii_digit() {
            if !result.ends_with('#') {
                result.push('#');
            }
            in_space = false;
        } else if character.is_whitespace() {
            if !in_space {
                result.push(' ');
            }
            in_space = true;
        } else {
            result.push(character);
            in_space = false;
        }
    }
    result.trim().to_string()
}

fn order_lines(lines: &mut [Line], page_width: f64) {
    let is_spanning = |line: &Line| {
        let width = line.bounds[2] - line.bounds[0];
        width > page_width * 0.68
            || (line.bounds[0] < page_width * 0.42 && line.bounds[2] > page_width * 0.58)
    };
    let mut spanning: Vec<Line> = lines
        .iter()
        .filter(|line| is_spanning(line))
        .cloned()
        .collect();
    let columns: Vec<Line> = lines
        .iter()
        .filter(|line| !is_spanning(line))
        .cloned()
        .collect();
    spanning.sort_by(vertical_order);

    let mut ordered = Vec::with_capacity(lines.len());
    let mut consumed = vec![false; columns.len()];
    let mut band_top = f64::NEG_INFINITY;
    for separator in spanning {
        append_column_band(
            &columns,
            &mut consumed,
            band_top,
            separator.bounds[1],
            page_width,
            &mut ordered,
        );
        band_top = separator.bounds[3];
        ordered.push(separator);
    }
    append_column_band(
        &columns,
        &mut consumed,
        band_top,
        f64::INFINITY,
        page_width,
        &mut ordered,
    );
    // Overlapping text boxes can cross a spanning separator. Keep any such
    // lines instead of dropping content when the source PDF has loose boxes.
    let mut leftovers: Vec<Line> = columns
        .into_iter()
        .enumerate()
        .filter(|(index, _)| !consumed[*index])
        .map(|(_, line)| line)
        .collect();
    leftovers.sort_by(vertical_order);
    ordered.extend(leftovers);
    lines.clone_from_slice(&ordered);
}

fn append_column_band(
    source: &[Line],
    consumed: &mut [bool],
    top: f64,
    bottom: f64,
    page_width: f64,
    output: &mut Vec<Line>,
) {
    let mut band: Vec<(usize, Line)> = source
        .iter()
        .enumerate()
        .filter(|(index, line)| {
            if consumed[*index] {
                return false;
            }
            let center = (line.bounds[1] + line.bounds[3]) * 0.5;
            center >= top && center < bottom
        })
        .map(|(index, line)| (index, line.clone()))
        .collect();
    band.sort_by(|(_, a), (_, b)| {
        let column = |line: &Line| {
            if (line.bounds[0] + line.bounds[2]) * 0.5 < page_width * 0.5 {
                0
            } else {
                1
            }
        };
        column(a).cmp(&column(b)).then_with(|| vertical_order(a, b))
    });
    for (index, line) in band {
        consumed[index] = true;
        output.push(line);
    }
}

fn vertical_order(a: &Line, b: &Line) -> CmpOrdering {
    a.bounds[1]
        .partial_cmp(&b.bounds[1])
        .unwrap_or(CmpOrdering::Equal)
        .then_with(|| {
            a.bounds[0]
                .partial_cmp(&b.bounds[0])
                .unwrap_or(CmpOrdering::Equal)
        })
}

fn build_page_blocks(
    page: &PageLayout,
    detect_tables: bool,
    detect_figures: bool,
    output: &mut Vec<Block>,
) {
    if page.lines.is_empty() && (!detect_figures || page.images.is_empty()) {
        output.push(block(
            "fallbackRegion",
            page.number,
            [0.0, 0.0, page.width, page.height],
            String::new(),
            Vec::new(),
            Vec::new(),
            None,
            None,
            0.55,
        ));
    }
    let start = output.len();
    let body = median(
        page.lines
            .iter()
            .map(|line| line.font_size)
            .filter(|v| *v > 0.0)
            .collect(),
    );
    let mut index = 0;
    while index < page.lines.len() {
        let line = &page.lines[index];
        if detect_tables && line.cells.len() > 1 {
            let mut next = index + 1;
            let mut rows = vec![line.cells.clone()];
            let mut bounds = line.bounds;
            let mut glyphs = line.glyphs.clone();
            while next < page.lines.len() {
                let candidate = &page.lines[next];
                if candidate.cells.len() < 2
                    || (candidate.cells.len() as i32 - rows[0].len() as i32).abs() > 1
                    || candidate.bounds[1] - bounds[3] > body.max(10.0) * 2.8
                {
                    break;
                }
                rows.push(candidate.cells.clone());
                bounds = union(bounds, candidate.bounds);
                glyphs.extend(candidate.glyphs.clone());
                next += 1;
            }
            if rows.len() >= 2 {
                let text = rows
                    .iter()
                    .map(|row| row.join(" | "))
                    .collect::<Vec<_>>()
                    .join("\n");
                let confidence = average_confidence(&page.lines[index..next]);
                output.push(block(
                    "table",
                    line.page,
                    bounds,
                    text,
                    glyphs,
                    rows,
                    None,
                    None,
                    confidence * 0.9,
                ));
                index = next;
                continue;
            }
        }
        let kind = classify(line, body, page.height);
        if kind == "paragraph" {
            let mut next = index + 1;
            let mut text = line.text.clone();
            let mut bounds = line.bounds;
            let mut glyphs = line.glyphs.clone();
            while next < page.lines.len() {
                let candidate = &page.lines[next];
                if classify(candidate, body, page.height) != "paragraph" {
                    break;
                }
                let aligned = (candidate.bounds[0] - line.bounds[0]).abs() < body.max(8.0) * 1.5;
                if !aligned || candidate.bounds[1] - bounds[3] > body.max(10.0) * 1.3 {
                    break;
                }
                if text.ends_with('-') && !text.ends_with(" -") {
                    text.pop();
                } else {
                    text.push(' ');
                }
                text.push_str(candidate.text.trim_start());
                bounds = union(bounds, candidate.bounds);
                glyphs.extend(candidate.glyphs.clone());
                next += 1;
            }
            output.push(block(
                kind,
                line.page,
                bounds,
                text,
                glyphs,
                Vec::new(),
                None,
                None,
                average_confidence(&page.lines[index..next]) * 0.95,
            ));
            index = next;
            continue;
        }
        let level = if kind == "heading" {
            Some(if line.font_size >= body * 1.7 { 1 } else { 2 })
        } else {
            None
        };
        output.push(block(
            kind,
            line.page,
            line.bounds,
            line.text.clone(),
            line.glyphs.clone(),
            Vec::new(),
            None,
            level,
            line.confidence * 0.96,
        ));
        index += 1;
    }
    if detect_figures {
        for bounds in &page.images {
            let caption = closest_caption(*bounds, &page.lines);
            let kind = if caption.as_deref().is_some_and(|value| {
                let lower = value.to_lowercase();
                lower.contains("chart") || lower.contains("graph") || lower.contains("plot")
            }) {
                "chart"
            } else {
                "image"
            };
            output.push(block(
                kind,
                page.number,
                *bounds,
                String::new(),
                Vec::new(),
                Vec::new(),
                caption,
                None,
                0.94,
            ));
        }
        for bounds in &page.vector_regions {
            if page
                .images
                .iter()
                .any(|image| overlap_ratio(*bounds, *image) > 0.8)
            {
                continue;
            }
            output.push(block(
                "chart",
                page.number,
                *bounds,
                String::new(),
                Vec::new(),
                Vec::new(),
                closest_caption(*bounds, &page.lines),
                None,
                0.76,
            ));
        }
    }
    output[start..].sort_by(|a, b| {
        a.anchor.bounds[1]
            .partial_cmp(&b.anchor.bounds[1])
            .unwrap_or(CmpOrdering::Equal)
            .then_with(|| {
                a.anchor.bounds[0]
                    .partial_cmp(&b.anchor.bounds[0])
                    .unwrap_or(CmpOrdering::Equal)
            })
    });
}

fn overlap_ratio(subject: [f64; 4], other: [f64; 4]) -> f64 {
    let width = (subject[2].min(other[2]) - subject[0].max(other[0])).max(0.0);
    let height = (subject[3].min(other[3]) - subject[1].max(other[1])).max(0.0);
    let subject_area = (subject[2] - subject[0]).max(0.0) * (subject[3] - subject[1]).max(0.0);
    if subject_area <= 0.0 {
        0.0
    } else {
        width * height / subject_area
    }
}

fn average_confidence(lines: &[Line]) -> f64 {
    if lines.is_empty() {
        return 0.5;
    }
    lines.iter().map(|line| line.confidence).sum::<f64>() / lines.len() as f64
}

fn closest_caption(bounds: [f64; 4], lines: &[Line]) -> Option<String> {
    lines
        .iter()
        .filter_map(|line| {
            let lower = line.text.to_lowercase();
            let is_caption = ["figure", "fig.", "fig ", "image", "chart", "graph", "plot"]
                .iter()
                .any(|prefix| lower.trim_start().starts_with(prefix));
            if !is_caption {
                return None;
            }
            let vertical = if line.bounds[1] >= bounds[3] {
                line.bounds[1] - bounds[3]
            } else if line.bounds[3] <= bounds[1] {
                bounds[1] - line.bounds[3]
            } else {
                0.0
            };
            let horizontal_overlap = line.bounds[2] >= bounds[0] && line.bounds[0] <= bounds[2];
            if horizontal_overlap && vertical <= line.font_size.max(10.0) * 4.0 {
                Some((vertical, line.text.clone()))
            } else {
                None
            }
        })
        .min_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(CmpOrdering::Equal))
        .map(|(_, text)| text)
}

fn classify(line: &Line, body: f64, page_height: f64) -> &'static str {
    let value = line.text.trim();
    if looks_like_equation(value) {
        return "equation";
    }
    if looks_like_list(value) {
        return "list";
    }
    let font = line.font_name.to_lowercase();
    if line.font_size >= body * 1.25
        || ((font.contains("bold") || font.contains("semibold")) && value.len() < 120)
    {
        return "heading";
    }
    if line.font_size > 0.0 && line.font_size <= body * 0.78 && line.bounds[1] > page_height * 0.65
    {
        return "footnote";
    }
    "paragraph"
}

fn looks_like_list(value: &str) -> bool {
    let trimmed = value.trim_start();
    if trimmed
        .chars()
        .next()
        .is_some_and(|character| "•●▪◦‣–-".contains(character))
    {
        return true;
    }
    let prefix = trimmed.split_whitespace().next().unwrap_or("");
    (prefix.ends_with('.') || prefix.ends_with(')'))
        && prefix
            .trim_matches(|c: char| !c.is_alphanumeric())
            .chars()
            .all(|c| c.is_alphanumeric())
        && prefix.len() <= 5
}

fn looks_like_equation(value: &str) -> bool {
    if value.len() > 160 {
        return false;
    }
    let symbols = value
        .chars()
        .filter(|c| "=∑∫√≈≠≤≥±×÷^_".contains(*c))
        .count();
    symbols >= 2 || (symbols == 1 && value.chars().any(|c| c.is_ascii_alphabetic()))
}

fn block(
    kind: &'static str,
    page: i32,
    bounds: [f64; 4],
    text: String,
    glyphs: Vec<Glyph>,
    rows: Vec<Vec<String>>,
    caption: Option<String>,
    heading_level: Option<i32>,
    confidence: f64,
) -> Block {
    Block {
        kind,
        anchor: SourceAnchor { page, bounds },
        text,
        glyphs,
        rows,
        caption,
        heading_level,
        confidence,
    }
}

fn union(a: [f64; 4], b: [f64; 4]) -> [f64; 4] {
    [
        a[0].min(b[0]),
        a[1].min(b[1]),
        a[2].max(b[2]),
        a[3].max(b[3]),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn glyph(text: &str, left: f64, top: f64) -> Glyph {
        Glyph {
            text: text.into(),
            bounds: [left, top, left + 5.0, top + 10.0],
            font_name: "Test".into(),
            font_size: 10.0,
            baseline: top + 10.0,
        }
    }

    fn line(text: &str, left: f64, top: f64, right: f64) -> Line {
        Line {
            page: 1,
            text: text.into(),
            bounds: [left, top, right, top + 10.0],
            font_name: "Test".into(),
            font_size: 10.0,
            glyphs: vec![glyph(text, left, top)],
            cells: Vec::new(),
            confidence: 0.99,
        }
    }

    #[test]
    fn geometry_is_grouped_into_lines_and_table_cells() {
        let lines = cluster_lines(
            1,
            vec![
                glyph("A", 10.0, 10.0),
                glyph("B", 20.0, 10.0),
                glyph("C", 80.0, 10.0),
            ],
        );
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].text, "A B C");
        assert_eq!(lines[0].cells, vec!["A B", "C"]);
    }

    #[test]
    fn running_page_numbers_are_normalized() {
        assert_eq!(running_key("ArcPDF 12"), running_key("ArcPDF 93"));
    }

    #[test]
    fn two_column_pages_read_down_the_left_column_first() {
        let mut lines = vec![
            line("Right one", 320.0, 50.0, 550.0),
            line("Left two", 30.0, 90.0, 260.0),
            line("Left one", 30.0, 50.0, 260.0),
            line("Right two", 320.0, 90.0, 550.0),
        ];
        order_lines(&mut lines, 600.0);
        assert_eq!(
            lines
                .iter()
                .map(|line| line.text.as_str())
                .collect::<Vec<_>>(),
            vec!["Left one", "Left two", "Right one", "Right two"]
        );
    }

    #[test]
    fn nearby_figure_caption_is_attached_to_image() {
        let lines = vec![line("Figure 2. Architecture", 40.0, 220.0, 300.0)];
        assert_eq!(
            closest_caption([40.0, 50.0, 300.0, 200.0], &lines).as_deref(),
            Some("Figure 2. Architecture")
        );
    }

    #[test]
    fn scan_detection_and_ocr_merge_preserve_source_coordinates() {
        let mut pages = vec![PageLayout {
            number: 1,
            width: 600.0,
            height: 800.0,
            lines: Vec::new(),
            images: vec![[0.0, 0.0, 600.0, 800.0]],
            vector_regions: Vec::new(),
        }];
        assert_eq!(pages_requiring_ocr(&pages), vec![1]);
        merge_ocr_lines(
            &mut pages,
            &[ReflowOcrPage {
                page: 1,
                lines: vec![ReflowOcrLine {
                    text: "Recognized text".into(),
                    bounds: [40.0, 60.0, 240.0, 82.0],
                    confidence: Some(0.84),
                    elements: Vec::new(),
                }],
            }],
        );
        assert_eq!(pages[0].lines[0].text, "Recognized text");
        assert_eq!(pages[0].lines[0].bounds, [40.0, 60.0, 240.0, 82.0]);
        assert_eq!(pages[0].lines[0].confidence, 0.84);
    }

    #[test]
    fn connected_vector_objects_form_chart_regions() {
        let paths = vec![
            [20.0, 20.0, 22.0, 180.0],
            [20.0, 178.0, 220.0, 180.0],
            [40.0, 80.0, 80.0, 178.0],
            [90.0, 50.0, 130.0, 178.0],
            [140.0, 100.0, 180.0, 178.0],
        ];
        let regions = cluster_vector_regions(paths, 300.0, 300.0);
        assert_eq!(regions.len(), 1);
        assert_eq!(regions[0], [20.0, 20.0, 220.0, 180.0]);
    }

    #[test]
    fn page_spanning_vector_cluster_is_not_a_chart_region() {
        let paths = vec![
            [5.0, 5.0, 595.0, 8.0],
            [592.0, 5.0, 595.0, 795.0],
            [5.0, 792.0, 595.0, 795.0],
            [5.0, 5.0, 8.0, 795.0],
        ];

        assert!(cluster_vector_regions(paths, 600.0, 800.0).is_empty());
    }
}
