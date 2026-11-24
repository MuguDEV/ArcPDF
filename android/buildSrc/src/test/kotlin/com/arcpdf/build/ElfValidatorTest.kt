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

    private fun message(data: ByteArray, abi: RustAbi = RustAbi.ARM64) = failure { ElfValidator.validate("a.so", data, abi) }

    @Test fun rejects4kAlignedSegmentsOn64BitAbis() {
        val data = ElfFixtures.elf(true, 183, loads = listOf(ElfFixtures.Load(0, 0x100, 0x1000)))
        assertTrue(message(data).contains("16 KB"))
        val x64 = ElfFixtures.elf(true, 62, loads = listOf(ElfFixtures.Load(0, 0x100, 0x1000)))
        assertTrue(message(x64, RustAbi.X64).contains("p_align"))
    }

    @Test fun rejectsAlignmentThatIsNotAMultipleOf16k() {
        val data = ElfFixtures.elf(true, 183, loads = listOf(ElfFixtures.Load(0, 0x100, 0x6000)))
        assertTrue(message(data).contains("p_align"))
    }

    @Test fun acceptsLargerSixteenKAlignmentAnd4kOn32Bit() {
        ElfValidator.validate("a.so", ElfFixtures.elf(true, 183, loads = listOf(ElfFixtures.Load(0, 0x100, 0x10000))), RustAbi.ARM64)
        ElfValidator.validate("a.so", ElfFixtures.elf(false, 40, loads = listOf(ElfFixtures.Load(0, 0x100, 0x1000))), RustAbi.ARM_V7)
        assertTrue(message(ElfFixtures.elf(false, 40, loads = listOf(ElfFixtures.Load(0, 0x100, 0x200))), RustAbi.ARM_V7).contains("p_align"))
    }

    @Test fun rejectsProgramHeadersOutsideTheFile() {
        assertTrue(message(ElfFixtures.elf(true, 183, phoff = 0x1000)).contains("out of bounds"))
        assertTrue(message(ElfFixtures.elf(true, 183, phoff = 0x3f0, phnum = 1)).contains("exceeds file length"))
        assertTrue(message(ElfFixtures.elf(true, 183, phnum = 0, loads = emptyList())).contains("no program headers"))
    }

    @Test fun rejectsSegmentsBeyondFileLength() {
        val data = ElfFixtures.elf(true, 183, loads = listOf(ElfFixtures.Load(0x300, 0x200, 0x4000, vaddr = 0x300)))
        assertTrue(message(data).contains("exceeds file length"))
        val huge = ElfFixtures.elf(true, 183, loads = listOf(ElfFixtures.Load(0x10, Long.MAX_VALUE, 0x4000, vaddr = 0x10)))
        assertTrue(message(huge).contains("exceeds file length"))
    }

    @Test fun rejectsFileSizeAboveMemorySize() {
        val data = ElfFixtures.elf(true, 183, loads = listOf(ElfFixtures.Load(0, 0x100, 0x4000, memSize = 0x80)))
        assertTrue(message(data).contains("p_memsz"))
    }

    @Test fun rejectsMisalignedOffsetAndAddress() {
        val data = ElfFixtures.elf(true, 183, loads = listOf(ElfFixtures.Load(0x10, 0x100, 0x4000, vaddr = 0x20)))
        assertTrue(message(data).contains("congruent"))
    }

    @Test fun rejectsLibraryWithoutLoadSegment() {
        val data = ElfFixtures.elf(true, 183, loads = listOf(ElfFixtures.Load(0, 0x100, 0x4000)))
        data[64] = 2 // turn the only PT_LOAD into PT_DYNAMIC
        assertTrue(message(data).contains("no PT_LOAD"))
    }

    @Test fun rejectsTruncatedHeader() {
        assertTrue(message(ElfFixtures.elf(true, 183).copyOf(60)).contains("truncated"))
    }
}
