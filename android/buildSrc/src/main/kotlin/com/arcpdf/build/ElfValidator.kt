package com.arcpdf.build

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Validates native libraries before they are packaged into the APK. */
object ElfValidator {
    private const val PT_LOAD = 1
    private const val PAGE_4K = 0x1000L
    private const val PAGE_16K = 0x4000L

    /** Throws [IllegalStateException] describing the first problem found. */
    fun validate(file: File, abi: RustAbi) {
        check(file.isFile) { "${file.name}: file does not exist at ${file.absolutePath}" }
        validate(file.name, file.readBytes(), abi)
    }

    fun validate(name: String, data: ByteArray, abi: RustAbi) {
        check(data.isNotEmpty()) { "$name: file is empty" }
        check(
            data.size >= 52 && data[0] == 0x7f.toByte() && data[1] == 'E'.code.toByte() &&
                data[2] == 'L'.code.toByte() && data[3] == 'F'.code.toByte(),
        ) { "$name: not an ELF file (bad magic)" }
        val elfClass = data[4].toInt()
        check(elfClass == 1 || elfClass == 2) { "$name: unsupported ELF class $elfClass" }
        check(data[5].toInt() == 1) { "$name: only little-endian ELF is supported" }
        val is64 = elfClass == 2
        check(is64 == abi.is64Bit) {
            "$name: ELF class is ${if (is64) 64 else 32}-bit but ${abi.abi} requires ${if (abi.is64Bit) 64 else 32}-bit"
        }
        val headerSize = if (is64) 64 else 52
        check(data.size >= headerSize) { "$name: truncated ELF header" }
        val buf = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        val machine = buf.getShort(18).toInt() and 0xffff
        check(machine == abi.elfMachine) { "$name: e_machine is $machine but ${abi.abi} requires ${abi.elfMachine}" }

        val phoff: Long
        val phentsize: Int
        val phnum: Int
        if (is64) {
            phoff = buf.getLong(32)
            phentsize = buf.getShort(54).toInt() and 0xffff
            phnum = buf.getShort(56).toInt() and 0xffff
        } else {
            phoff = buf.getInt(28).toLong() and 0xffffffffL
            phentsize = buf.getShort(42).toInt() and 0xffff
            phnum = buf.getShort(44).toInt() and 0xffff
        }
        val minEntry = if (is64) 56 else 32
        check(phnum > 0) { "$name: no program headers" }
        check(phentsize >= minEntry) { "$name: program header entry size $phentsize is below $minEntry" }
        val length = data.size.toLong()
        check(phoff >= headerSize && phoff <= length) { "$name: program header offset $phoff is out of bounds" }
        val tableSize = phentsize.toLong() * phnum
        check(tableSize <= length - phoff) {
            "$name: program header table ($phnum entries at $phoff) exceeds file length $length"
        }

        var loads = 0
        for (i in 0 until phnum) {
            val o = (phoff + i.toLong() * phentsize).toInt()
            if (buf.getInt(o) != PT_LOAD) continue
            loads++
            val offset: Long
            val vaddr: Long
            val fileSize: Long
            val memSize: Long
            val align: Long
            if (is64) {
                offset = buf.getLong(o + 8)
                vaddr = buf.getLong(o + 16)
                fileSize = buf.getLong(o + 32)
                memSize = buf.getLong(o + 40)
                align = buf.getLong(o + 48)
            } else {
                offset = buf.getInt(o + 4).toLong() and 0xffffffffL
                vaddr = buf.getInt(o + 8).toLong() and 0xffffffffL
                fileSize = buf.getInt(o + 16).toLong() and 0xffffffffL
                memSize = buf.getInt(o + 20).toLong() and 0xffffffffL
                align = buf.getInt(o + 28).toLong() and 0xffffffffL
            }
            check(offset >= 0 && fileSize >= 0 && memSize >= 0 && align >= 0 && vaddr >= 0) {
                "$name: PT_LOAD #$i has a field above the supported range"
            }
            check(offset <= length && fileSize <= length - offset) {
                "$name: PT_LOAD #$i (offset $offset, size $fileSize) exceeds file length $length"
            }
            check(fileSize <= memSize) { "$name: PT_LOAD #$i p_filesz $fileSize exceeds p_memsz $memSize" }
            val required = if (abi.is64Bit) PAGE_16K else PAGE_4K
            check(align >= required && align % required == 0L) {
                "$name: PT_LOAD #$i p_align 0x${align.toString(16)} must be a multiple of 0x${required.toString(16)}" +
                    if (abi.is64Bit) " (16 KB page size support)" else ""
            }
            check(vaddr % align == offset % align) {
                "$name: PT_LOAD #$i p_vaddr and p_offset are not congruent modulo p_align"
            }
        }
        check(loads > 0) { "$name: no PT_LOAD segments" }
    }
}
