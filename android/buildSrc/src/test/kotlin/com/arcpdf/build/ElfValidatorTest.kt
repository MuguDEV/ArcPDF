package com.arcpdf.build

import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class ElfValidatorTest {
    private fun failure(block: () -> Unit): String {
        try {
            block()
        } catch (e: IllegalStateException) {
            return e.message.orEmpty()
        }
        fail("expected validation failure")
        return ""
    }

    @Test fun acceptsMatchingLibraryForEachAbi() {
        ElfValidator.validate("a.so", ElfFixtures.elf(true, 183), RustAbi.ARM64)
        ElfValidator.validate("a.so", ElfFixtures.elf(true, 62), RustAbi.X64)
        ElfValidator.validate("a.so", ElfFixtures.elf(false, 40), RustAbi.ARM_V7)
    }

    @Test fun rejectsEmptyFile() {
        assertTrue(failure { ElfValidator.validate("a.so", ByteArray(0), RustAbi.ARM64) }.contains("empty"))
    }

    @Test fun rejectsBadMagic() {
        val data = ElfFixtures.elf(true, 183, magic = byteArrayOf(0, 1, 2, 3))
        assertTrue(failure { ElfValidator.validate("a.so", data, RustAbi.ARM64) }.contains("magic"))
    }

    @Test fun rejectsWrongClass() {
        assertTrue(failure { ElfValidator.validate("a.so", ElfFixtures.elf(false, 183), RustAbi.ARM64) }.contains("32-bit"))
    }

    @Test fun rejectsWrongMachine() {
        assertTrue(failure { ElfValidator.validate("a.so", ElfFixtures.elf(true, 62), RustAbi.ARM64) }.contains("e_machine"))
    }
}
