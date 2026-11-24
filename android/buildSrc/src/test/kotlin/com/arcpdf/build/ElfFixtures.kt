package com.arcpdf.build

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Builds small synthetic ELF images for validator tests. */
object ElfFixtures {
    data class Load(val offset: Long, val fileSize: Long, val align: Long, val vaddr: Long = offset)

    fun elf(
        is64: Boolean,
        machine: Int,
        loads: List<Load> = listOf(Load(0, 0x100, if (is64) 0x4000 else 0x1000)),
        totalSize: Int = 0x400,
        phoff: Long? = null,
        phnum: Int = loads.size,
        magic: ByteArray = byteArrayOf(0x7f, 'E'.code.toByte(), 'L'.code.toByte(), 'F'.code.toByte()),
    ): ByteArray {
        val headerSize = if (is64) 64 else 52
        val phentsize = if (is64) 56 else 32
        val offset = phoff ?: headerSize.toLong()
        val buf = ByteBuffer.allocate(totalSize).order(ByteOrder.LITTLE_ENDIAN)
        buf.put(0, magic[0]).put(1, magic[1]).put(2, magic[2]).put(3, magic[3])
        buf.put(4, if (is64) 2 else 1).put(5, 1).put(6, 1)
        buf.putShort(18, machine.toShort())
        if (is64) {
            buf.putLong(32, offset)
            buf.putShort(52, 64)
            buf.putShort(54, phentsize.toShort())
            buf.putShort(56, phnum.toShort())
        } else {
            buf.putInt(28, offset.toInt())
            buf.putShort(40, 52)
            buf.putShort(42, phentsize.toShort())
            buf.putShort(44, phnum.toShort())
        }
        loads.forEachIndexed { i, l ->
            val o = (offset + i * phentsize).toInt()
            if (o < 0 || o + phentsize > totalSize) return@forEachIndexed
            buf.putInt(o, 1)
            if (is64) {
                buf.putLong(o + 8, l.offset)
                buf.putLong(o + 16, l.vaddr)
                buf.putLong(o + 24, l.vaddr)
                buf.putLong(o + 32, l.fileSize)
                buf.putLong(o + 40, l.fileSize)
                buf.putLong(o + 48, l.align)
            } else {
                buf.putInt(o + 4, l.offset.toInt())
                buf.putInt(o + 8, l.vaddr.toInt())
                buf.putInt(o + 12, l.vaddr.toInt())
                buf.putInt(o + 16, l.fileSize.toInt())
                buf.putInt(o + 20, l.fileSize.toInt())
                buf.putInt(o + 28, l.align.toInt())
            }
        }
        return buf.array()
    }
}
