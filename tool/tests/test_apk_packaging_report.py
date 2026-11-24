"""Tests for tool/apk_packaging_validate.py using synthetic APKs and AABs.

External Android tools are replaced by a fake runner, so no SDK is needed.
Run: python3 -m pytest tool/tests -q   or   python3 -m unittest discover tool/tests
"""
import json, os, struct, subprocess, sys, tempfile, time, unittest, zipfile

TOOL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, TOOL_DIR)
import apk_packaging_validate as v  # noqa: E402

TOOLS = {n: "/fake/" + n for n in v.REQUIRED_TOOLS}
CERT = "ab" * 32
MACHINE = {"arm64-v8a": 183, "armeabi-v7a": 40, "x86_64": 62}


def make_elf(abi="arm64-v8a", align=0x4000, seed=b"", congruent=True):
    """Tiny ELF with one PT_LOAD. 64-bit for arm64/x86_64, 32-bit for armv7."""
    is64 = abi != "armeabi-v7a"
    va = 0x4000 if congruent else 0x4010  # p_offset is 0, so va must be a multiple of p_align
    if is64:
        hdr = b"\x7fELF" + bytes([2, 1, 1]) + bytes(9)
        hdr += struct.pack("<HHIQQQIHHHHHH", 3, MACHINE.get(abi, 3), 1, 0, 64, 0, 0, 64, 56, 1, 0, 0, 0)
        ph = struct.pack("<IIQQQQQQ", 1, 5, 0, va, 0, 100, 100, align)
    else:
        hdr = b"\x7fELF" + bytes([1, 1, 1]) + bytes(9)
        hdr += struct.pack("<HHIIIIIHHHHHH", 3, MACHINE.get(abi, 3), 1, 0, 52, 0, 0, 52, 32, 1, 0, 0, 0)
        ph = struct.pack("<IIIIIIII", 1, 0, va, 0, 100, 100, 5, align)
    return hdr + ph + seed


def fake_runner(cert=CERT, package="com.arcpdf.app", version=2001, zipalign_rc=0,
                verify_rc=0, versions=None):
    def runner(cmd):
        tool = os.path.basename(cmd[0])
        if tool == "llvm-readelf":
            with open(cmd[-1], "rb") as f:
                elf = v.parse_elf(f.read())
            lines = [f"  LOAD 0x0 0x0 0x0 0x64 0x64 R E {hex(a)}" for (_o, _v, a) in elf["loads"]]
            return 0, "\n".join(lines)
        apk = cmd[-1]
        if tool == "apksigner":
            return verify_rc, ("Verifies\nVerified using v2 scheme (APK Signature Scheme v2): true\n"
                               f"Number of signers: 1\nSigner #1 certificate SHA-256 digest: {cert}\n")
        if tool == "zipalign":
            return zipalign_rc, "Verification " + ("succesful" if zipalign_rc == 0 else "FAILED")
        if tool == "aapt2":
            vc = (versions or {}).get(os.path.basename(apk), version)
            return 0, f"package: name='{package}' versionCode='{vc}' versionName='1.0'\n"
        raise AssertionError(cmd)
    return runner


def write_apk(path, abis, method=zipfile.ZIP_STORED,
              extra_entries=(), omit=(), elf_align=0x4000, seed=b"", aligned=True):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("classes.dex", b"dex")
        for abi in abis:
            for lib in v.EXPECTED_LIBS:
                name = f"lib/{abi}/{lib}"
                if name in omit:
                    continue
                data = make_elf(abi, elf_align, seed + lib.encode())
                info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
                info.compress_type = method
                if method == zipfile.ZIP_STORED and aligned:
                    pos = z.fp.tell()
                    pad = (-(pos + 30 + len(name))) % 16384
                    while pad < 4:
                        pad += 16384
                    info.extra = struct.pack("<HH", 0xD935, pad - 4) + bytes(pad - 4)
                z.writestr(info, data)
        for n in extra_entries:
            z.writestr(n, b"x")


def build_dirs(root, all_abis=False, a_method=zipfile.ZIP_STORED, b_method=zipfile.ZIP_DEFLATED, **kw):
    names = v.expected_apk_names(all_abis)
    for label, method in (("A", a_method), ("B", b_method)):
        d = os.path.join(root, label)
        os.makedirs(d, exist_ok=True)
        for n, abis in names.items():
            write_apk(os.path.join(d, n), abis, method, aligned=(method == zipfile.ZIP_STORED), **kw)
    return os.path.join(root, "A"), os.path.join(root, "B")


def ids(result, ok=False):
    return [c["id"] for c in result["checks"] if c["ok"] == ok]


class Base(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.root = self._t.name

    def tearDown(self):
        self._t.cleanup()

    def run_validate(self, a, b, runner=None, tools=None, **kw):
        return v.validate(a, b, tools=TOOLS if tools is None else tools,
                          runner=runner or fake_runner(), **kw)

    def assertFailed(self, result, fragment):
        self.assertFalse(result["ok"])
        self.assertTrue(any(fragment in c["id"] for c in result["failures"]),
                        f"{fragment} not in {[c['id'] for c in result['failures']]}")


class HappyPathTests(Base):
    def test_arm64_passes(self):
        a, b = build_dirs(self.root)
        r = self.run_validate(a, b)
        self.assertTrue(r["ok"], r["failures"])

    def test_all_abis_and_universal_pass(self):
        a, b = build_dirs(self.root, all_abis=True)
        r = self.run_validate(a, b, all_abis=True)
        self.assertTrue(r["ok"], r["failures"])
        self.assertEqual(set(r["apks"]["A"]), set(v.expected_apk_names(True)))
        uni = r["apks"]["A"]["app-universal-release.apk"]["native_libs"]
        self.assertEqual(len(uni), 18)

    def test_json_serializable(self):
        a, b = build_dirs(self.root)
        json.dumps(self.run_validate(a, b))


class ToolTests(Base):
    def test_missing_tool_fails(self):
        a, b = build_dirs(self.root)
        tools = dict(TOOLS)
        del tools["apksigner"]
        self.assertFailed(self.run_validate(a, b, tools=tools), "tools:available")

    def test_missing_readelf_fails(self):
        a, b = build_dirs(self.root)
        tools = dict(TOOLS, **{"llvm-readelf": None})
        self.assertFailed(self.run_validate(a, b, tools=tools), "tools:available")

    def test_apksigner_failure(self):
        a, b = build_dirs(self.root)
        self.assertFailed(self.run_validate(a, b, runner=fake_runner(verify_rc=1)), "apksigner-verify")

    def test_zipalign_failure(self):
        a, b = build_dirs(self.root)
        self.assertFailed(self.run_validate(a, b, runner=fake_runner(zipalign_rc=1)), "zipalign-16k")


class ElfTests(Base):
    def test_parse_elf64_and_32(self):
        self.assertEqual(v.parse_elf(make_elf("arm64-v8a", 0x4000))["loads"][0][2], 0x4000)
        e = v.parse_elf(make_elf("armeabi-v7a", 0x1000))
        self.assertEqual((e["bits"], e["machine"], e["loads"][0][2]), (32, 40, 0x1000))

    def test_parse_rejects_garbage(self):
        with self.assertRaises(ValueError):
            v.parse_elf(b"not an elf" * 10)
        with self.assertRaises(ValueError):
            v.parse_elf(make_elf()[:70])

    def test_4k_align_fails_on_64bit(self):
        a, b = build_dirs(self.root, elf_align=0x1000)
        self.assertFailed(self.run_validate(a, b), "palign-16k")

    def test_4k_align_ok_on_armv7(self):
        a, b = build_dirs(self.root, all_abis=True, elf_align=0x1000)
        r = self.run_validate(a, b, all_abis=True)
        self.assertTrue(any("palign-16k" in i for i in ids(r, False)))
        self.assertFalse(any("armeabi-v7a" in i and "palign" in i for i in ids(r, False)))

    def test_wrong_machine_fails(self):
        a, b = build_dirs(self.root)
        p = os.path.join(a, "app-arm64-v8a-release.apk")
        write_apk(p, ("arm64-v8a",))
        with zipfile.ZipFile(p, "a") as z:
            pass
        os.remove(p)
        with zipfile.ZipFile(p, "w") as z:
            for lib in v.EXPECTED_LIBS:
                z.writestr(zipfile.ZipInfo(f"lib/arm64-v8a/{lib}"), make_elf("x86_64"))
        self.assertFailed(self.run_validate(a, b), "elf-machine")

    def test_non_congruent_load_fails(self):
        a, b = build_dirs(self.root)
        p = os.path.join(a, "app-arm64-v8a-release.apk")
        os.remove(p)
        with zipfile.ZipFile(p, "w") as z:
            for lib in v.EXPECTED_LIBS:
                z.writestr(zipfile.ZipInfo(f"lib/arm64-v8a/{lib}"), make_elf(congruent=False))
        self.assertFailed(self.run_validate(a, b), "elf-congruent")


class ModeTests(Base):
    def test_modern_apk_with_compressed_libs_fails(self):
        a, b = build_dirs(self.root, a_method=zipfile.ZIP_DEFLATED)
        self.assertFailed(self.run_validate(a, b), "A:app-arm64-v8a-release.apk:lib/arm64-v8a/libapp.so:method")

    def test_compressed_apk_with_stored_libs_fails(self):
        a, b = build_dirs(self.root, b_method=zipfile.ZIP_STORED)
        self.assertFailed(self.run_validate(a, b), "B:app-arm64-v8a-release.apk:lib/arm64-v8a/libapp.so:method")

    def test_unaligned_stored_lib_fails(self):
        a, b = build_dirs(self.root)
        write_apk(os.path.join(a, "app-arm64-v8a-release.apk"), ("arm64-v8a",), aligned=False)
        self.assertFailed(self.run_validate(a, b), "zip-offset-16k")

    def test_expect_override(self):
        a, b = build_dirs(self.root, a_method=zipfile.ZIP_DEFLATED, b_method=zipfile.ZIP_DEFLATED)
        r = self.run_validate(a, b, expect_a="deflate")
        self.assertTrue(r["ok"], r["failures"])


class AbiTests(Base):
    def test_missing_abi_fails_in_universal(self):
        a, b = build_dirs(self.root, all_abis=True)
        write_apk(os.path.join(a, "app-universal-release.apk"), ("arm64-v8a", "x86_64"))
        self.assertFailed(self.run_validate(a, b, all_abis=True), "app-universal-release.apk:abi-set")

    def test_x86_is_rejected(self):
        a, b = build_dirs(self.root)
        write_apk(os.path.join(a, "app-arm64-v8a-release.apk"), ("arm64-v8a", "x86"))
        self.assertFailed(self.run_validate(a, b), "abi-set")

    def test_missing_lib_fails(self):
        a, b = build_dirs(self.root)
        write_apk(os.path.join(b, "app-arm64-v8a-release.apk"), ("arm64-v8a",),
                  zipfile.ZIP_DEFLATED, omit=("lib/arm64-v8a/libdartjni.so",))
        self.assertFailed(self.run_validate(a, b), "arm64-v8a:lib-set")

    def test_extra_lib_fails(self):
        a, b = build_dirs(self.root)
        write_apk(os.path.join(b, "app-arm64-v8a-release.apk"), ("arm64-v8a",),
                  zipfile.ZIP_DEFLATED, extra_entries=("lib/arm64-v8a/libsurprise.so",))
        self.assertFailed(self.run_validate(a, b), "arm64-v8a:lib-set")

    def test_all_abis_expected_but_only_arm64_present(self):
        a, b = build_dirs(self.root)
        self.assertFailed(self.run_validate(a, b, all_abis=True), "exact-files")


class SignerParsingTests(unittest.TestCase):
    OTHER = "cd" * 32

    def test_single_scheme(self):
        out = f"Verifies\nNumber of signers: 1\nSigner #1 certificate SHA-256 digest: {CERT}\n"
        self.assertEqual(v.signer_cert_digests(out), [CERT])

    def test_all_schemes_same_signer(self):
        out = (f"Verifies\nVerified using v1 scheme (JAR signing): true\n"
               f"Verified using v2 scheme (APK Signature Scheme v2): true\n"
               f"Verified using v3 scheme (APK Signature Scheme v3): true\n"
               f"Number of signers: 1\n"
               f"Signer #1 certificate DN: CN=x\n"
               f"Signer #1 certificate SHA-256 digest: {CERT}\n"
               f"Signer (minSdkVersion=24, maxSdkVersion=2147483647) certificate SHA-256 digest: {CERT.upper()}\n"
               f"Signer #1 certificate SHA-256 digest: {CERT}\n")
        self.assertEqual(v.signer_cert_digests(out), [CERT])

    def test_v3_only_format(self):
        out = f"Signer (minSdkVersion=24, maxSdkVersion=2147483647) certificate SHA-256 digest: {CERT}\n"
        self.assertEqual(v.signer_cert_digests(out), [CERT])

    def test_two_different_signers(self):
        out = (f"Number of signers: 2\nSigner #1 certificate SHA-256 digest: {CERT}\n"
               f"Signer #2 certificate SHA-256 digest: {self.OTHER}\n")
        self.assertEqual(v.signer_cert_digests(out), [CERT, self.OTHER])

    def test_no_signer(self):
        self.assertEqual(v.signer_cert_digests("Verifies\n"), [])

    def test_check_flags(self):
        for out, ok in ((f"Signer (minSdkVersion=24, maxSdkVersion=2147483647) certificate SHA-256 digest: {CERT}\n"
                         f"Signer #1 certificate SHA-256 digest: {CERT}\n", True),
                        (f"Signer #1 certificate SHA-256 digest: {CERT}\n"
                         f"Signer #2 certificate SHA-256 digest: {self.OTHER}\n", False)):
            res = _Res()
            v._check_signing(res, "A", "a.apk", TOOLS, lambda cmd: (0, "Verified using v2 scheme: true\n" + out), {})
            self.assertEqual(res.results["A:single-signer"], ok)


class _Res:
    def __init__(self):
        self.results = {}

    def check(self, cid, cond, detail=""):
        self.results[cid] = bool(cond)


class HashTests(Base):
    def test_content_difference_fails(self):
        a, b = build_dirs(self.root)
        write_apk(os.path.join(b, "app-arm64-v8a-release.apk"), ("arm64-v8a",),
                  zipfile.ZIP_DEFLATED, seed=b"different")
        self.assertFailed(self.run_validate(a, b), "sha256-equal")

    def test_identical_content_ignores_compression_and_timestamps(self):
        a, b = build_dirs(self.root)
        r = self.run_validate(a, b)
        self.assertIn("A-B:app-arm64-v8a-release.apk:sha256-equal", ids(r, True))


class IdentityTests(Base):
    def test_package_mismatch(self):
        a, b = build_dirs(self.root)

        def runner(cmd):
            if os.path.basename(cmd[0]) == "aapt2" and "/B/" in cmd[-1]:
                return 0, "package: name='com.other' versionCode='2001' versionName='1'"
            return fake_runner()(cmd)
        self.assertFailed(self.run_validate(a, b, runner=runner), ":package")

    def test_version_code_mismatch(self):
        a, b = build_dirs(self.root)

        def runner(cmd):
            if os.path.basename(cmd[0]) == "aapt2" and "/B/" in cmd[-1]:
                return 0, "package: name='com.arcpdf.app' versionCode='2002' versionName='1'"
            return fake_runner()(cmd)
        self.assertFailed(self.run_validate(a, b, runner=runner), ":versionCode")

    def test_signing_cert_mismatch(self):
        a, b = build_dirs(self.root)

        def runner(cmd):
            if os.path.basename(cmd[0]) == "apksigner" and "/B/" in cmd[-1]:
                return fake_runner(cert="cd" * 32)(cmd)
            return fake_runner()(cmd)
        r = self.run_validate(a, b, runner=runner)
        self.assertFailed(r, ":signing-cert")
        self.assertFailed(r, "all:single-signing-cert")

    def test_split_version_codes_may_differ_across_abis(self):
        a, b = build_dirs(self.root, all_abis=True)
        vc = {n: 3000 + i for i, n in enumerate(sorted(v.expected_apk_names(True)))}
        r = self.run_validate(a, b, all_abis=True, runner=fake_runner(versions=vc))
        self.assertTrue(r["ok"], r["failures"])


class OcrTests(Base):
    def test_ocr_library_fails(self):
        a, b = build_dirs(self.root)
        write_apk(os.path.join(a, "app-arm64-v8a-release.apk"), ("arm64-v8a",),
                  extra_entries=("lib/arm64-v8a/libmlkit_google_ocr_pipeline.so",))
        self.assertFailed(self.run_validate(a, b), "no-ocr-bundle")

    def test_ocr_models_fail(self):
        a, b = build_dirs(self.root)
        write_apk(os.path.join(b, "app-arm64-v8a-release.apk"), ("arm64-v8a",), zipfile.ZIP_DEFLATED,
                  extra_entries=("assets/mlkit-google-ocr-models/latin/model.tflite",))
        self.assertFailed(self.run_validate(a, b), "no-ocr-bundle")

    def test_forbidden_entries_helper(self):
        self.assertEqual(v.forbidden_entries(["base/assets/mlkit-google-ocr-models/x", "lib/a/libapp.so"]),
                         ["base/assets/mlkit-google-ocr-models/x"])


class StaleTests(Base):
    def test_extra_file_fails(self):
        a, b = build_dirs(self.root)
        write_apk(os.path.join(a, "app-armeabi-v7a-release.apk"), ("armeabi-v7a",))
        self.assertFailed(self.run_validate(a, b), "A:exact-files")

    def test_missing_file_fails(self):
        a, b = build_dirs(self.root)
        os.remove(os.path.join(b, "app-arm64-v8a-release.apk"))
        self.assertFailed(self.run_validate(a, b), "B:exact-files")

    def test_old_file_fails_not_before(self):
        a, b = build_dirs(self.root)
        old = time.time() - 1000
        os.utime(os.path.join(a, "app-arm64-v8a-release.apk"), (old, old))
        self.assertFailed(self.run_validate(a, b, not_before=time.time() - 100), "A:app-arm64-v8a-release.apk:fresh")

    def test_fresh_files_pass_not_before(self):
        a, b = build_dirs(self.root)
        r = self.run_validate(a, b, not_before=time.time() - 100)
        self.assertTrue(r["ok"], r["failures"])

    def test_missing_dir_fails(self):
        r = self.run_validate(os.path.join(self.root, "nope"), os.path.join(self.root, "nope2"))
        self.assertFailed(r, ":dir")


def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def ld(num, payload):
    return varint(num << 3 | 2) + varint(len(payload)) + payload


def bundle_config(uncompress=None, version=b"1.0"):
    cfg = ld(1, ld(2, version))
    if uncompress is not None:
        cfg += ld(2, ld(2, varint(1 << 3) + varint(1 if uncompress else 0)))
    return cfg


def write_aab(path, config=None, libs=None, extra=(), sig=b"s"):
    config = bundle_config() if config is None else config
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("BundleConfig.pb", config)
        z.writestr("base/manifest/AndroidManifest.xml", b"manifest")
        for n, d in (libs or {"base/lib/arm64-v8a/libapp.so": b"app"}).items():
            z.writestr(n, d)
        z.writestr("META-INF/MANIFEST.MF", sig)
        z.writestr("META-INF/COMPARE.SF", sig)
        for n in extra:
            z.writestr(n, b"x")


class AabTests(Base):
    def check(self, off, on):
        res = v.Results()
        v.check_aab(res, off, on)
        return res

    def paths(self):
        return os.path.join(self.root, "off.aab"), os.path.join(self.root, "on.aab")

    def test_equivalent_aabs_pass_despite_signature_differences(self):
        off, on = self.paths()
        write_aab(off, sig=b"one")
        write_aab(on, sig=b"two")
        self.assertEqual(self.check(off, on).failures, [])

    def test_content_difference_fails(self):
        off, on = self.paths()
        write_aab(off)
        write_aab(on, libs={"base/lib/arm64-v8a/libapp.so": b"other"})
        ids_ = [c["id"] for c in self.check(off, on).failures]
        self.assertIn("aab:same-entry-content", ids_)

    def test_extra_entry_fails(self):
        off, on = self.paths()
        write_aab(off)
        write_aab(on, extra=("base/lib/arm64-v8a/libextra.so",))
        self.assertIn("aab:same-entry-names", [c["id"] for c in self.check(off, on).failures])

    def test_native_packaging_config_difference_fails(self):
        off, on = self.paths()
        write_aab(off, config=bundle_config(uncompress=False))
        write_aab(on, config=bundle_config(uncompress=True))
        ids_ = [c["id"] for c in self.check(off, on).failures]
        self.assertIn("aab:native-packaging-config", ids_)
        self.assertIn("aab:bundle-config-identical", ids_)

    def test_ocr_in_aab_fails(self):
        off, on = self.paths()
        write_aab(off)
        write_aab(on, extra=("base/assets/mlkit-google-ocr-models/m.bin",))
        self.assertIn("aab:on:no-ocr-bundle", [c["id"] for c in self.check(off, on).failures])

    def test_missing_aab_fails(self):
        off, on = self.paths()
        write_aab(off)
        self.assertIn("aab:on:exists", [c["id"] for c in self.check(off, on).failures])

    def test_proto_field(self):
        cfg = bundle_config(uncompress=True)
        self.assertEqual(v.proto_field(cfg, (2, 2, 1)), 1)
        self.assertIsNone(v.proto_field(bundle_config(), (2, 2, 1)))
        with self.assertRaises(ValueError):
            v.proto_field(b"\x0a\x05ab", (1,))

    def test_validate_includes_aab(self):
        a, b = build_dirs(self.root)
        off, on = self.paths()
        write_aab(off)
        write_aab(on, extra=("base/lib/arm64-v8a/libextra.so",))
        r = self.run_validate(a, b, aab_off=off, aab_on=on)
        self.assertFalse(r["ok"])


class CliTests(Base):
    def test_help(self):
        p = subprocess.run([sys.executable, os.path.join(TOOL_DIR, "apk_packaging_report.py"), "validate", "--help"],
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 0)
        self.assertIn("--a-dir", p.stdout)

    def test_cli_exits_nonzero_and_writes_json(self):
        out = os.path.join(self.root, "r.json")
        env = dict(os.environ, PATH="/nonexistent", ANDROID_HOME="", ANDROID_SDK_ROOT="")
        p = subprocess.run([sys.executable, os.path.join(TOOL_DIR, "apk_packaging_report.py"), "validate",
                            "--a-dir", self.root, "--b-dir", self.root, "--json", out],
                           capture_output=True, text=True, env=env)
        self.assertEqual(p.returncode, 1)
        with open(out) as f:
            data = json.load(f)
        self.assertFalse(data["ok"])
        self.assertIn("tools:available", [c["id"] for c in data["failures"]])

    def test_legacy_usage_still_works(self):
        p = subprocess.run([sys.executable, os.path.join(TOOL_DIR, "apk_packaging_report.py")],
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 2)


if __name__ == "__main__":
    unittest.main()
