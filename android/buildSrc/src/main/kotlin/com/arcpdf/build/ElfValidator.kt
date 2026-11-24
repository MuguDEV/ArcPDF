package com.arcpdf.build

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Validates native libraries before they are packaged into the APK. */
object ElfValidator {
    private const val ELF_HEADER_64 = 64
    private const val ELF_HEADER_32 = 52

    /** Throws [IllegalStateException] describing the first problem found. */
    fun validate(file: File, abi: RustAbi) {
        check(file.isFile) { "${file.name}: file does not exist at ${file.absolutePath}" }
        validate(file.name, file.readBytes(), abi)
    }

    fun validate(name: String, data: ByteArray, abi: RustAbi) {
        check(data.isNotEmpty()) { "$name: file is empty" }
        check(data.size >= ELF_HEADER_32 && data[0] == 0x7f.toByte() && data[1] == 'E'.code.toByte() &&
            data[2] == 'L'.code.toByte() && data[3] == 'F'.code.toByte()) { "$name: not an ELF file (bad magic)" }
        val elfClass = data[4].toInt()
        check(elfClass == 1 || elfClass == 2) { "$name: unsupported ELF class $elfClass" }
        check(data[5].toInt() == 1) { "$name: only little-endian ELF is supported" }
        val is64 = elfClass == 2
        check(is64 == abi.is64Bit) {
            "$name: ELF class is ${if (is64) 64 else 32}-bit but ${abi.abi} requires ${if (abi.is64Bit) 64 else 32}-bit"
        }
        val buf = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        val machine = buf.getShort(18).toInt() and 0xffff
        check(machine == abi.elfMachine) { "$name: e_machine is $machine but ${abi.abi} requires ${abi.elfMachine}" }
    }
}
