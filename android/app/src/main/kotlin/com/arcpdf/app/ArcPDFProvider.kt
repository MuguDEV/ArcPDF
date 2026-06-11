package com.arcpdf.app

import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.Bitmap
import android.graphics.Point
import android.graphics.pdf.PdfRenderer
import android.os.CancellationSignal
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.util.Log
import java.io.File
import java.io.FileNotFoundException

class ArcPDFProvider : DocumentsProvider() {

    companion object {
        private const val TAG = "ArcPDFProvider"
        private const val AUTHORITY = "com.arcpdf.app.documents"
        private const val ROOT_ID = "arcpdf_root"

        private val DEFAULT_ROOT_PROJECTION: Array<String> = arrayOf(
            Root.COLUMN_ROOT_ID,
            Root.COLUMN_MIME_TYPES,
            Root.COLUMN_FLAGS,
            Root.COLUMN_ICON,
            Root.COLUMN_TITLE,
            Root.COLUMN_SUMMARY,
            Root.COLUMN_DOCUMENT_ID
        )

        private val DEFAULT_DOCUMENT_PROJECTION: Array<String> = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS,
            Document.COLUMN_SIZE
        )
    }

    override fun onCreate(): Boolean {
        return true
    }

    private fun getBaseDirectory(): File {
        val docsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        val arcPdfDir = File(docsDir, "ArcPDF")
        if (!arcPdfDir.exists()) {
            arcPdfDir.mkdirs()
        }
        return arcPdfDir
    }

    private fun getFileForDocId(documentId: String): File {
        val baseDir = getBaseDirectory()
        return File(baseDir, documentId)
    }

    private fun getDocIdForFile(file: File): String {
        return file.name
    }

    override fun queryRoots(projection: Array<String>?): Cursor {
        val result = MatrixCursor(projection ?: DEFAULT_ROOT_PROJECTION)

        val row = result.newRow()
        row.add(Root.COLUMN_ROOT_ID, ROOT_ID)
        row.add(Root.COLUMN_SUMMARY, "ArcPDF Files")
        row.add(Root.COLUMN_FLAGS, Root.FLAG_SUPPORTS_SEARCH or Root.FLAG_SUPPORTS_RECENTS)
        row.add(Root.COLUMN_TITLE, "ArcPDF")
        row.add(Root.COLUMN_DOCUMENT_ID, getDocIdForFile(getBaseDirectory()))
        row.add(Root.COLUMN_MIME_TYPES, "application/pdf")
        row.add(Root.COLUMN_ICON, R.mipmap.ic_launcher)

        return result
    }

    override fun queryDocument(documentId: String, projection: Array<String>?): Cursor {
        val result = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        includeFile(result, getFileForDocId(documentId))
        return result
    }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<String>?,
        sortOrder: String?
    ): Cursor {
        val result = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        val parent = getFileForDocId(parentDocumentId)

        parent.listFiles()?.filter { it.extension.lowercase() == "pdf" }?.forEach { file ->
            includeFile(result, file)
        }

        return result
    }

    override fun queryRecentDocuments(
        rootId: String?,
        projection: Array<String>?
    ): Cursor {
        val result = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        val parent = getBaseDirectory()

        val files = parent.listFiles()?.filter { it.extension.lowercase() == "pdf" }
            ?.sortedByDescending { it.lastModified() }
            ?.take(20)

        files?.forEach { file ->
            includeFile(result, file)
        }

        return result
    }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?
    ): ParcelFileDescriptor {
        val file = getFileForDocId(documentId)
        val accessMode = ParcelFileDescriptor.parseMode(mode)
        return ParcelFileDescriptor.open(file, accessMode)
    }

    override fun openDocumentThumbnail(
        documentId: String?,
        sizeHint: Point?,
        signal: CancellationSignal?
    ): AssetFileDescriptor? {
        if (documentId == null || sizeHint == null) return super.openDocumentThumbnail(documentId, sizeHint, signal)

        val file = getFileForDocId(documentId)
        if (!file.exists()) throw FileNotFoundException("File not found")

        var pfd: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        var page: PdfRenderer.Page? = null

        try {
            pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = PdfRenderer(pfd)
            if (renderer.pageCount > 0) {
                page = renderer.openPage(0)

                // Calculate dimensions matching aspect ratio
                val ratio = page.width.toFloat() / page.height.toFloat()
                var w = sizeHint.x
                var h = sizeHint.y
                if (w / h.toFloat() > ratio) {
                    w = (h * ratio).toInt()
                } else {
                    h = (w / ratio).toInt()
                }

                val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                // Fill white background
                bitmap.eraseColor(android.graphics.Color.WHITE)
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

                val tempFile = File.createTempFile("thumb", ".png", context?.cacheDir)
                val out = java.io.FileOutputStream(tempFile)
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                out.close()
                bitmap.recycle()

                return AssetFileDescriptor(
                    ParcelFileDescriptor.open(tempFile, ParcelFileDescriptor.MODE_READ_ONLY),
                    0,
                    AssetFileDescriptor.UNKNOWN_LENGTH
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error generating thumbnail", e)
        } finally {
            page?.close()
            renderer?.close()
            pfd?.close()
        }

        return super.openDocumentThumbnail(documentId, sizeHint, signal)
    }

    private fun includeFile(result: MatrixCursor, file: File) {
        if (!file.exists()) return

        val row = result.newRow()
        row.add(Document.COLUMN_DOCUMENT_ID, getDocIdForFile(file))
        row.add(Document.COLUMN_DISPLAY_NAME, file.name)
        row.add(Document.COLUMN_SIZE, file.length())
        row.add(Document.COLUMN_LAST_MODIFIED, file.lastModified())

        if (file.isDirectory) {
            row.add(Document.COLUMN_MIME_TYPE, Document.MIME_TYPE_DIR)
            row.add(Document.COLUMN_FLAGS, 0)
        } else {
            row.add(Document.COLUMN_MIME_TYPE, "application/pdf")
            var flags = Document.FLAG_SUPPORTS_THUMBNAIL
            if (file.canWrite()) flags = flags or Document.FLAG_SUPPORTS_WRITE
            row.add(Document.COLUMN_FLAGS, flags)
            row.add(Document.COLUMN_ICON, R.mipmap.ic_launcher)
        }
    }
}
