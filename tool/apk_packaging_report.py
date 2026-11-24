#!/usr/bin/env python3
"""Report native library packaging of one or two APKs.

Usage: tool/apk_packaging_report.py A.apk [B.apk] [--out report.md]

Prints total size, per-category sizes, and for every lib/*/*.so entry the
stored size, uncompressed size, ZIP method, ratio and ELF PT_LOAD p_align.
Also runs apksigner verify and zipalign -c -P 16 when the Android SDK is
available (ANDROID_HOME or ANDROID_SDK_ROOT). Read only: never modifies APKs.
"""
import glob, os, re, subprocess, sys, tempfile, zipfile

METHODS = {0: "stored", 8: "deflate"}


def sdk_tool(name, sub="build-tools"):
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        return None
    found = sorted(glob.glob(os.path.join(sdk, sub, "*", name)))
    return found[-1] if found else None


def readelf():
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if sdk:
        found = glob.glob(os.path.join(sdk, "ndk", "*", "toolchains/llvm/prebuilt/*/bin/llvm-readelf"))
        if found:
            return sorted(found)[-1]
    return "llvm-readelf"


def run(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True)
        return p.returncode, (p.stdout + p.stderr).strip()
    except FileNotFoundError:
        return 127, "tool not found: " + cmd[0]


def elf_aligns(data, tmpdir):
    path = os.path.join(tmpdir, "lib.so")
    with open(path, "wb") as f:
        f.write(data)
    rc, out = run([readelf(), "-lW", path])
    if rc != 0:
        return "n/a"
    aligns = []
    for line in out.splitlines():
        parts = line.split()
        if parts and parts[0] == "LOAD":
            aligns.append(parts[-1])
    return ",".join(sorted(set(aligns))) or "n/a"


def categorize(name):
    if name.startswith("lib/") and name.endswith(".so"):
        return "native libs"
    if re.match(r"classes\d*\.dex$", name):
        return "dex"
    if name.startswith("assets/"):
        return "assets"
    if name.startswith("res/") or name == "resources.arsc":
        return "resources"
    if name.startswith("META-INF/"):
        return "META-INF"
    return "other"


def report(apk):
    lines = []
    size = os.path.getsize(apk)
    lines.append(f"## {os.path.basename(apk)}\n")
    lines.append(f"- Path: `{apk}`")
    lines.append(f"- Total bytes: {size:,}")
    with zipfile.ZipFile(apk) as z:
        infos = z.infolist()
        cats = {}
        for i in infos:
            c = cats.setdefault(categorize(i.filename), [0, 0, 0])
            c[0] += 1
            c[1] += i.compress_size
            c[2] += i.file_size
        entries_total = sum(i.compress_size for i in infos)
        lines.append(f"- Entry data bytes (stored sizes): {entries_total:,}")
        lines.append(f"- Packaging overhead (file minus entry data: headers, directory, signing block, padding): {size - entries_total:,}\n")
        lines.append("| Category | Entries | Stored | Uncompressed |")
        lines.append("| --- | ---: | ---: | ---: |")
        for k in sorted(cats):
            n, s, u = cats[k]
            lines.append(f"| {k} | {n} | {s:,} | {u:,} |")
        lines.append("")
        lines.append("| Library | Stored | Uncompressed | Method | Ratio | ELF PT_LOAD p_align | Data offset mod 16384 |")
        lines.append("| --- | ---: | ---: | --- | ---: | --- | ---: |")
        with tempfile.TemporaryDirectory() as tmp:
            for i in infos:
                if categorize(i.filename) != "native libs":
                    continue
                ratio = i.compress_size / i.file_size if i.file_size else 1
                align = elf_aligns(z.read(i), tmp)
                with open(apk, "rb") as f:
                    f.seek(i.header_offset + 26)
                    nl = int.from_bytes(f.read(2), "little")
                    el = int.from_bytes(f.read(2), "little")
                    off = i.header_offset + 30 + nl + el
                lines.append(
                    f"| {i.filename} | {i.compress_size:,} | {i.file_size:,} | "
                    f"{METHODS.get(i.compress_type, i.compress_type)} | {ratio:.3f} | {align} | {off % 16384} |")
    lines.append("")
    signer = sdk_tool("apksigner")
    if signer:
        rc, out = run([signer, "verify", "--verbose", "--print-certs", apk])
        lines.append(f"apksigner verify exit {rc}:\n```\n{out}\n```")
    else:
        lines.append("apksigner: NOT AVAILABLE")
    za = sdk_tool("zipalign")
    if za:
        rc, out = run([za, "-c", "-P", "16", "-v", "4", apk])
        tail = "\n".join(out.splitlines()[-4:])
        bad = [l for l in out.splitlines() if "(BAD" in l]
        lines.append(f"zipalign -c -P 16 -v 4 exit {rc}; BAD entries: {len(bad)}\n```\n" + "\n".join(bad[:20] + [tail]) + "\n```")
    else:
        lines.append("zipalign: NOT AVAILABLE")
    return "\n".join(lines) + "\n"


def main(argv):
    out = None
    if "--out" in argv:
        k = argv.index("--out")
        out = argv[k + 1]
        argv = argv[:k] + argv[k + 2:]
    if not argv:
        print(__doc__)
        return 2
    text = "# APK packaging report\n\n" + "\n".join(report(a) for a in argv)
    if len(argv) == 2:
        a, b = (os.path.getsize(x) for x in argv)
        text += f"\n## Delta\n\nB - A = {b - a:,} bytes ({(b - a) / a * 100:.2f}%)\n"
    if out:
        with open(out, "w") as f:
            f.write(text)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
