#!/usr/bin/env python3
"""Strict, machine-readable validation of A/B native packaging builds.

Run through `tool/apk_packaging_report.py validate ...`. Read only: never
modifies APKs or AABs. Writes a JSON verdict and exits 1 when any check fails
or a required Android tool is missing, 2 on usage errors.

A is the modern packaging build (stored, page aligned native libraries).
B is the experimental compressed build. Checks:

* required tools exist (apksigner, zipalign, aapt2, llvm-readelf)
* output directories contain exactly the expected APK names and none is older
  than --not-before (stale output guard)
* exact ABI and native library set per APK
* ZIP method of every native library (stored in A, deflate in B)
* ELF PT_LOAD p_align and 16 KB conditions (parsed in Python, cross-checked
  with llvm-readelf), zipalign -c -P 16
* SHA-256 of uncompressed native library contents equal between A and B
* same package name, versionCode and signing certificate in A and B
* no bundled OCR library or model assets
* AAB equivalence (normalized entries and native packaging config)

Signed archives are never compared byte for byte.
"""
import argparse, glob, hashlib, json, os, re, struct, subprocess, sys, tempfile, zipfile

ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")
EXPECTED_LIBS = (
    "libapp.so", "libflutter.so", "libpdfium.so",
    "libarcpdf_indexer.so", "libdartjni.so", "libpdfrx_pdfium_gate.so",
)
FORBIDDEN_LIB = "libmlkit_google_ocr_pipeline.so"
FORBIDDEN_ASSET = "assets/mlkit-google-ocr-models"
PAGE_16K = 16384
ELF_MACHINE = {"arm64-v8a": 183, "armeabi-v7a": 40, "x86_64": 62}
ELF_64BIT = {"arm64-v8a": True, "armeabi-v7a": False, "x86_64": True}
METHOD_NAMES = {0: "stored", 8: "deflate"}
EXPECT_METHOD = {"stored": 0, "deflate": 8}
REQUIRED_TOOLS = ("apksigner", "zipalign", "aapt2", "llvm-readelf")


# ---------------------------------------------------------------- tools

def _sdk():
    return os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")


def find_tool(name):
    sdk = _sdk()
    if sdk:
        if name == "llvm-readelf":
            pats = [os.path.join(sdk, "ndk", "*", "toolchains/llvm/prebuilt/*/bin/llvm-readelf")]
        else:
            pats = [os.path.join(sdk, "build-tools", "*", name)]
        for pat in pats:
            found = sorted(glob.glob(pat))
            if found:
                return found[-1]
    for d in os.environ.get("PATH", "").split(os.pathsep):
        cand = os.path.join(d, name)
        if d and os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return None


def run(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True)
        return p.returncode, (p.stdout + p.stderr)
    except OSError as e:
        return 127, f"cannot run {cmd[0]}: {e}"


# ---------------------------------------------------------------- ELF

def parse_elf(data):
    """Return dict(bits, machine, loads=[(offset, vaddr, align)]) or raise ValueError."""
    if len(data) < 64 or data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    cls, enc = data[4], data[5]
    if cls not in (1, 2) or enc not in (1, 2):
        raise ValueError("unsupported ELF class or encoding")
    e = "<" if enc == 1 else ">"
    machine = struct.unpack_from(e + "H", data, 18)[0]
    try:
        if cls == 2:
            phoff = struct.unpack_from(e + "Q", data, 32)[0]
            phentsize, phnum = struct.unpack_from(e + "HH", data, 54)
            minsize = 56
        else:
            phoff = struct.unpack_from(e + "I", data, 28)[0]
            phentsize, phnum = struct.unpack_from(e + "HH", data, 42)
            minsize = 32
        if phentsize < minsize:
            raise ValueError("bad program header entry size")
        loads = []
        for n in range(phnum):
            o = phoff + n * phentsize
            if cls == 2:
                ptype, _fl, off, va, _pa, _fs, _ms, al = struct.unpack_from(e + "IIQQQQQQ", data, o)
            else:
                ptype, off, va, _pa, _fs, _ms, _fl, al = struct.unpack_from(e + "IIIIIIII", data, o)
            if ptype == 1:
                loads.append((off, va, al))
    except struct.error:
        raise ValueError("truncated ELF program headers")
    return {"bits": 64 if cls == 2 else 32, "machine": machine, "loads": loads}


def readelf_aligns(readelf, data, tmpdir, runner):
    path = os.path.join(tmpdir, "lib.so")
    with open(path, "wb") as f:
        f.write(data)
    rc, out = runner([readelf, "-lW", path])
    if rc != 0:
        return None
    aligns = []
    for line in out.splitlines():
        parts = line.split()
        if parts and parts[0] == "LOAD":
            try:
                aligns.append(int(parts[-1], 16))
            except ValueError:
                return None
    return aligns


# ---------------------------------------------------------------- results

class Results:
    def __init__(self):
        self.checks = []

    def check(self, cid, ok, detail=""):
        self.checks.append({"id": cid, "ok": bool(ok), "detail": detail})
        return bool(ok)

    @property
    def failures(self):
        return [c for c in self.checks if not c["ok"]]


def expected_apk_names(all_abis):
    names = {f"app-{a}-release.apk": (a,) for a in (ABIS if all_abis else ("arm64-v8a",))}
    if all_abis:
        names["app-universal-release.apk"] = ABIS
    return names


def zip_data_offset(apk, info):
    with open(apk, "rb") as f:
        f.seek(info.header_offset + 26)
        nl, el = struct.unpack("<HH", f.read(4))
    return info.header_offset + 30 + nl + el


def lib_entries(z):
    return [i for i in z.infolist() if i.filename.startswith("lib/") and i.filename.endswith(".so")]


def forbidden_entries(names):
    bad = []
    for n in names:
        if n.rsplit("/", 1)[-1] == FORBIDDEN_LIB:
            bad.append(n)
        elif FORBIDDEN_ASSET in n:
            bad.append(n)
    return sorted(bad)


# ---------------------------------------------------------------- stale guard

def check_directory(res, label, directory, names, not_before):
    if not os.path.isdir(directory):
        res.check(f"{label}:dir", False, f"missing directory {directory}")
        return {}
    present = sorted(f for f in os.listdir(directory))
    expected = sorted(names)
    res.check(f"{label}:exact-files", present == expected,
              f"expected {expected}, found {present}")
    found = {}
    for n in expected:
        p = os.path.join(directory, n)
        if os.path.isfile(p):
            found[n] = p
            if not_before is not None:
                m = os.path.getmtime(p)
                res.check(f"{label}:{n}:fresh", m >= not_before,
                          f"mtime {int(m)} vs not-before {int(not_before)}")
    return found


# ---------------------------------------------------------------- per APK

def inspect_apk(res, label, apk, abis, expect_method, tools, runner):
    """Run all single-APK checks. Returns facts used for A/B comparison."""
    facts = {"hashes": {}, "methods": {}, "package": None, "version_code": None, "cert": None}
    p = f"{label}"
    try:
        z = zipfile.ZipFile(apk)
    except (zipfile.BadZipFile, OSError) as e:
        res.check(f"{p}:zip", False, str(e))
        return facts
    with z:
        bad = z.testzip()
        res.check(f"{p}:zip-crc", bad is None, f"bad entry {bad}")
        names = [i.filename for i in z.infolist()]
        res.check(f"{p}:no-ocr-bundle", not forbidden_entries(names),
                  f"forbidden entries: {forbidden_entries(names)}")
        libs = lib_entries(z)
        found = {}
        for i in libs:
            parts = i.filename.split("/")
            found.setdefault(parts[1] if len(parts) > 2 else "?", set()).add(parts[-1])
        res.check(f"{p}:abi-set", set(found) == set(abis),
                  f"expected {sorted(abis)}, found {sorted(found)}")
        for abi in abis:
            res.check(f"{p}:{abi}:lib-set", found.get(abi) == set(EXPECTED_LIBS),
                      f"expected {sorted(EXPECTED_LIBS)}, found {sorted(found.get(abi, []))}")
        want = EXPECT_METHOD[expect_method]
        readelf = tools.get("llvm-readelf")
        with tempfile.TemporaryDirectory() as tmp:
            for i in libs:
                parts = i.filename.split("/")
                abi = parts[1]
                data = z.read(i)
                facts["hashes"][i.filename] = hashlib.sha256(data).hexdigest()
                facts["methods"][i.filename] = METHOD_NAMES.get(i.compress_type, i.compress_type)
                res.check(f"{p}:{i.filename}:method", i.compress_type == want,
                          f"expected {expect_method}, found {facts['methods'][i.filename]}")
                if i.compress_type == 0:
                    off = zip_data_offset(apk, i)
                    res.check(f"{p}:{i.filename}:zip-offset-16k", off % PAGE_16K == 0,
                              f"data offset mod 16384 = {off % PAGE_16K}")
                _check_elf(res, p, i.filename, abi, data, readelf, tmp, runner)
    _check_signing(res, p, apk, tools, runner, facts)
    _check_badging(res, p, apk, tools, runner, facts)
    rc, out = runner([tools["zipalign"], "-c", "-P", "16", "-v", "4", apk]) if "zipalign" in tools else (127, "")
    res.check(f"{p}:zipalign-16k", rc == 0, out.strip().splitlines()[-1] if out.strip() else f"exit {rc}")
    return facts


def _check_elf(res, p, name, abi, data, readelf, tmp, runner):
    cid = f"{p}:{name}:elf"
    try:
        elf = parse_elf(data)
    except ValueError as e:
        res.check(cid, False, str(e))
        return
    res.check(cid + "-machine", abi in ELF_MACHINE and elf["machine"] == ELF_MACHINE[abi]
              and (elf["bits"] == 64) == ELF_64BIT[abi],
              f"machine {elf['machine']}, {elf['bits']}-bit does not match {abi}")
    loads = elf["loads"]
    res.check(cid + "-has-load", bool(loads), "no PT_LOAD segments")
    aligns = [a for (_o, _v, a) in loads]
    if ELF_64BIT.get(abi, True):
        # 16 KB page size devices: 64-bit ARM and x86_64 segments must be 16 KB aligned.
        res.check(cid + "-palign-16k", all(a >= PAGE_16K and a % PAGE_16K == 0 for a in aligns),
                  f"PT_LOAD p_align {[hex(a) for a in aligns]}, need multiple of 0x4000")
    else:
        # 32-bit ARM does not run on 16 KB page kernels. Require the 4 KB minimum.
        res.check(cid + "-palign-4k", all(a >= 4096 and a % 4096 == 0 for a in aligns),
                  f"PT_LOAD p_align {[hex(a) for a in aligns]}, need multiple of 0x1000")
    res.check(cid + "-congruent",
              all(a <= 1 or (v % a) == (o % a) for (o, v, a) in loads),
              "PT_LOAD p_vaddr and p_offset not congruent modulo p_align")
    if readelf:
        tool_aligns = readelf_aligns(readelf, data, tmp, runner)
        res.check(cid + "-readelf", tool_aligns is not None and tool_aligns == aligns,
                  f"llvm-readelf {tool_aligns} vs parsed {aligns}")


def signer_cert_digests(out):
    """Distinct signer certificate SHA-256 digests in apksigner --print-certs output.

    apksigner repeats the signer once per scheme, as "Signer #1 certificate ..."
    (v1/v2) or "Signer (minSdkVersion=24, maxSdkVersion=...) certificate ..." (v3).
    The first digest seen is listed first, duplicates are dropped.
    """
    digests = []
    for d in re.findall(r"^\s*Signer\b[^\n]*?certificate SHA-256 digest:\s*([0-9a-fA-F]{64})",
                        out, re.M):
        d = d.lower()
        if d not in digests:
            digests.append(d)
    return digests


def _check_signing(res, p, apk, tools, runner, facts):
    if "apksigner" not in tools:
        return
    rc, out = runner([tools["apksigner"], "verify", "--verbose", "--print-certs", apk])
    res.check(f"{p}:apksigner-verify", rc == 0, out.strip()[:300])
    schemes = re.findall(r"Verified using v(\d) scheme.*?: true", out)
    res.check(f"{p}:signature-scheme", any(s in ("2", "3", "4") for s in schemes),
              f"verified schemes: {schemes}")
    certs = signer_cert_digests(out)
    res.check(f"{p}:signer-cert-parsed", bool(certs), "no certificate SHA-256 digest in apksigner output")
    facts["cert"] = certs[0] if certs else None
    res.check(f"{p}:single-signer", len(certs) == 1,
              f"expected exactly one signer, found {len(certs)} distinct certificates: {certs}")


def _check_badging(res, p, apk, tools, runner, facts):
    if "aapt2" not in tools:
        return
    rc, out = runner([tools["aapt2"], "dump", "badging", apk])
    m = re.search(r"package: name='([^']+)' versionCode='(\d+)'", out)
    res.check(f"{p}:badging", rc == 0 and bool(m), out.strip()[:300] if not m else "")
    if m:
        facts["package"], facts["version_code"] = m.group(1), int(m.group(2))


# ---------------------------------------------------------------- A/B

def compare_ab(res, name, fa, fb):
    p = f"A-B:{name}"
    res.check(f"{p}:same-lib-names", sorted(fa["hashes"]) == sorted(fb["hashes"]),
              f"only in A {sorted(set(fa['hashes']) - set(fb['hashes']))}, "
              f"only in B {sorted(set(fb['hashes']) - set(fa['hashes']))}")
    diff = sorted(k for k in fa["hashes"] if k in fb["hashes"] and fa["hashes"][k] != fb["hashes"][k])
    res.check(f"{p}:sha256-equal", not diff, f"content differs: {diff}")
    res.check(f"{p}:package", fa["package"] is not None and fa["package"] == fb["package"],
              f"A {fa['package']} vs B {fb['package']}")
    res.check(f"{p}:versionCode", fa["version_code"] is not None and fa["version_code"] == fb["version_code"],
              f"A {fa['version_code']} vs B {fb['version_code']}")
    res.check(f"{p}:signing-cert", fa["cert"] is not None and fa["cert"] == fb["cert"],
              f"A {fa['cert']} vs B {fb['cert']}")


# ---------------------------------------------------------------- AAB

def _varint(buf, pos):
    shift = val = 0
    while True:
        if pos >= len(buf):
            raise ValueError("truncated varint")
        b = buf[pos]
        pos += 1
        val |= (b & 0x7F) << shift
        if not b & 0x80:
            return val, pos
        shift += 7
        if shift > 63:
            raise ValueError("varint too long")


def proto_field(buf, path):
    """Return the last value found at a field-number path in a protobuf message.

    Varints give int, length-delimited fields give bytes (or are descended into).
    Returns None when the path is absent. Raises ValueError on malformed input.
    """
    want, rest = path[0], path[1:]
    pos, found = 0, None
    while pos < len(buf):
        key, pos = _varint(buf, pos)
        num, wt = key >> 3, key & 7
        if wt == 0:
            v, pos = _varint(buf, pos)
        elif wt == 1:
            v, pos = buf[pos:pos + 8], pos + 8
        elif wt == 5:
            v, pos = buf[pos:pos + 4], pos + 4
        elif wt == 2:
            n, pos = _varint(buf, pos)
            v, pos = buf[pos:pos + n], pos + n
            if len(v) != n:
                raise ValueError("truncated field")
        else:
            raise ValueError("unsupported wire type")
        if num == want:
            if not rest:
                found = v
            elif wt == 2:
                sub = proto_field(v, rest)
                if sub is not None:
                    found = sub
    return found


def aab_facts(aab):
    entries, config = {}, None
    with zipfile.ZipFile(aab) as z:
        for i in z.infolist():
            if i.is_dir():
                continue
            n = i.filename
            # Signature files and the jar manifest legitimately differ between signings.
            if n.startswith("META-INF/"):
                continue
            entries[n] = (i.file_size, i.CRC)
            if n == "BundleConfig.pb":
                config = z.read(i)
    native = alignment = None
    if config is not None:
        # BundleConfig.optimizations (2) . uncompress_native_libraries (2) . enabled (1), alignment (2)
        native = proto_field(config, (2, 2, 1))
        alignment = proto_field(config, (2, 2, 2))
    return {"entries": entries, "bundle_config": config, "uncompress_native_libs": native,
            "native_alignment": alignment}


def check_aab(res, off_path, on_path):
    for label, path in (("off", off_path), ("on", on_path)):
        if not os.path.isfile(path):
            res.check(f"aab:{label}:exists", False, f"missing {path}")
            return
    try:
        off, on = aab_facts(off_path), aab_facts(on_path)
    except (zipfile.BadZipFile, ValueError) as e:
        res.check("aab:readable", False, str(e))
        return
    res.check("aab:has-bundle-config", off["bundle_config"] is not None and on["bundle_config"] is not None,
              "BundleConfig.pb missing")
    for label, f in (("off", off), ("on", on)):
        res.check(f"aab:{label}:no-ocr-bundle", not forbidden_entries(f["entries"]),
                  f"forbidden entries: {forbidden_entries(f['entries'])}")
    res.check("aab:same-entry-names", sorted(off["entries"]) == sorted(on["entries"]),
              f"only off {sorted(set(off['entries']) - set(on['entries']))[:10]}, "
              f"only on {sorted(set(on['entries']) - set(off['entries']))[:10]}")
    diff = sorted(k for k in off["entries"] if k in on["entries"] and off["entries"][k] != on["entries"][k])
    res.check("aab:same-entry-content", not diff, f"size or CRC differs: {diff[:10]}")
    res.check("aab:native-packaging-config",
              off["uncompress_native_libs"] == on["uncompress_native_libs"],
              f"uncompress_native_libraries.enabled off={off['uncompress_native_libs']} on={on['uncompress_native_libs']}")
    res.check("aab:native-alignment-config", off["native_alignment"] == on["native_alignment"],
              f"uncompress_native_libraries.alignment off={off['native_alignment']} on={on['native_alignment']}")
    res.check("aab:bundle-config-identical", off["bundle_config"] == on["bundle_config"],
              "BundleConfig.pb differs")


# ---------------------------------------------------------------- driver

def validate(a_dir, b_dir, all_abis=False, expect_a="stored", expect_b="deflate",
             not_before=None, aab_off=None, aab_on=None, tools=None, runner=run):
    res = Results()
    if tools is None:
        tools = {n: find_tool(n) for n in REQUIRED_TOOLS}
    missing = [n for n in REQUIRED_TOOLS if not tools.get(n)]
    res.check("tools:available", not missing, f"missing required tools: {missing}")
    tools = {k: v for k, v in tools.items() if v}
    names = expected_apk_names(all_abis)
    files = {}
    for label, d in (("A", a_dir), ("B", b_dir)):
        files[label] = check_directory(res, label, d, names, not_before)
    facts = {"A": {}, "B": {}}
    for label, expect in (("A", expect_a), ("B", expect_b)):
        for n, path in sorted(files[label].items()):
            facts[label][n] = inspect_apk(res, f"{label}:{n}", path, names[n], expect, tools, runner)
    for n in sorted(names):
        if n in facts["A"] and n in facts["B"]:
            compare_ab(res, n, facts["A"][n], facts["B"][n])
    certs = {f["cert"] for lab in facts.values() for f in lab.values() if f["cert"]}
    res.check("all:single-signing-cert", len(certs) <= 1, f"distinct certificates: {sorted(certs)}")
    if aab_off or aab_on:
        check_aab(res, aab_off or "", aab_on or "")
    return {
        "ok": not res.failures,
        "failure_count": len(res.failures),
        "failures": res.failures,
        "checks": res.checks,
        "tools": {n: tools.get(n) for n in REQUIRED_TOOLS},
        "apks": {lab: {n: {"native_libs": f["hashes"], "methods": f["methods"],
                           "package": f["package"], "version_code": f["version_code"],
                           "cert_sha256": f["cert"]}
                       for n, f in d.items()} for lab, d in facts.items()},
    }


def main(argv):
    ap = argparse.ArgumentParser(prog="apk_packaging_report.py validate", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--a-dir", required=True, help="directory with the modern packaging APKs")
    ap.add_argument("--b-dir", required=True, help="directory with the compressed packaging APKs")
    ap.add_argument("--all-abis", action="store_true", help="expect arm64-v8a, armeabi-v7a, x86_64 and universal APKs")
    ap.add_argument("--expect-a", choices=sorted(EXPECT_METHOD), default="stored")
    ap.add_argument("--expect-b", choices=sorted(EXPECT_METHOD), default="deflate")
    ap.add_argument("--not-before", type=float, help="epoch seconds; APKs older than this are stale")
    ap.add_argument("--aab-off", help="AAB built with the switch off")
    ap.add_argument("--aab-on", help="AAB built with the switch on")
    ap.add_argument("--json", help="write the JSON verdict here")
    ap.add_argument("--md", help="write the Markdown report here")
    args = ap.parse_args(argv)
    result = validate(args.a_dir, args.b_dir, args.all_abis, args.expect_a, args.expect_b,
                      args.not_before, args.aab_off, args.aab_on)
    text = json.dumps(result, indent=2, sort_keys=True)
    if args.json:
        with open(args.json, "w") as f:
            f.write(text + "\n")
    if args.md:
        import apk_packaging_report as rep
        paths = [os.path.join(d, n) for d in (args.a_dir, args.b_dir)
                 for n in sorted(expected_apk_names(args.all_abis)) if os.path.isfile(os.path.join(d, n))]
        md = "# APK packaging report\n\n"
        md += f"Strict validation: {'PASS' if result['ok'] else 'FAIL'} ({result['failure_count']} failed checks)\n\n"
        for c in result["failures"]:
            md += f"- FAIL `{c['id']}`: {c['detail']}\n"
        md += "\n" + "\n".join(rep.report(x) for x in paths)
        with open(args.md, "w") as f:
            f.write(md)
    for c in result["failures"]:
        print(f"FAIL {c['id']}: {c['detail']}", file=sys.stderr)
    print(f"packaging validation: {'PASS' if result['ok'] else 'FAIL'} "
          f"({len(result['checks'])} checks, {result['failure_count']} failed)")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
