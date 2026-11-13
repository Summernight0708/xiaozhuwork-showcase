package com.xiaozhuzuoye.app;

import android.Manifest;
import android.app.DownloadManager;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;

import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@CapacitorPlugin(
    name = "XiaozhuDownload",
    permissions = {
        @Permission(alias = "storage", strings = { Manifest.permission.WRITE_EXTERNAL_STORAGE })
    }
)
public class XiaozhuDownloadPlugin extends Plugin {
    private static class BlobTransfer {
        final String fileName;
        final String mimeType;
        final File tempFile;
        final OutputStream output;

        BlobTransfer(String fileName, String mimeType, File tempFile, OutputStream output) {
            this.fileName = fileName;
            this.mimeType = mimeType;
            this.tempFile = tempFile;
            this.output = output;
        }
    }

    private final Map<String, BlobTransfer> transfers = new ConcurrentHashMap<>();

    @PluginMethod
    public void downloadUrl(PluginCall call) {
        String url = call.getString("url");
        String fileName = sanitizeFileName(call.getString("fileName", "download"));
        String mimeType = call.getString("mimeType");
        if (!isHttpUrl(url)) {
            call.reject("Only HTTP(S) download URLs are allowed");
            return;
        }

        try {
            DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url));
            request.setTitle(fileName);
            request.setDescription("小猪作业下载");
            request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
            request.setAllowedOverMetered(true);
            request.setAllowedOverRoaming(false);
            if (mimeType != null && !mimeType.isBlank()) request.setMimeType(mimeType);
            request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName);

            DownloadManager manager = (DownloadManager) getContext().getSystemService(Context.DOWNLOAD_SERVICE);
            long id = manager.enqueue(request);
            JSObject result = new JSObject();
            result.put("downloadId", Long.toString(id));
            call.resolve(result);
        } catch (Exception error) {
            call.reject("Unable to start system download", error);
        }
    }

    @PluginMethod
    public void beginBlobDownload(PluginCall call) {
        String fileName = sanitizeFileName(call.getString("fileName", "download"));
        String mimeType = call.getString("mimeType", "application/octet-stream");
        String transferId = UUID.randomUUID().toString();
        try {
            File directory = new File(getContext().getCacheDir(), "xiaozhu-downloads");
            if (!directory.exists() && !directory.mkdirs()) {
                call.reject("Unable to prepare download cache");
                return;
            }
            File tempFile = new File(directory, transferId + ".part");
            OutputStream output = new FileOutputStream(tempFile);
            transfers.put(transferId, new BlobTransfer(fileName, mimeType, tempFile, output));
            JSObject result = new JSObject();
            result.put("transferId", transferId);
            call.resolve(result);
        } catch (IOException error) {
            call.reject("Unable to prepare download", error);
        }
    }

    @PluginMethod
    public void appendBlobChunk(PluginCall call) {
        String transferId = call.getString("transferId");
        String encoded = call.getString("base64");
        BlobTransfer transfer = transfers.get(transferId);
        if (transfer == null || encoded == null) {
            call.reject("Unknown download transfer");
            return;
        }
        try {
            transfer.output.write(Base64.decode(encoded, Base64.DEFAULT));
            call.resolve();
        } catch (Exception error) {
            call.reject("Unable to write download chunk", error);
        }
    }

    @PluginMethod
    public void finishBlobDownload(PluginCall call) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && getPermissionState("storage") != PermissionState.GRANTED) {
            requestPermissionForAlias("storage", call, "storagePermissionCallback");
            return;
        }
        finishBlobDownloadInternal(call);
    }

    @PermissionCallback
    private void storagePermissionCallback(PluginCall call) {
        if (getPermissionState("storage") == PermissionState.GRANTED) {
            finishBlobDownloadInternal(call);
        } else {
            call.reject("Storage permission is required to save this download");
        }
    }

    private void finishBlobDownloadInternal(PluginCall call) {
        String transferId = call.getString("transferId");
        BlobTransfer transfer = transfers.remove(transferId);
        if (transfer == null) {
            call.reject("Unknown download transfer");
            return;
        }
        try {
            transfer.output.close();
            Uri uri = publishToDownloads(transfer);
            if (!transfer.tempFile.delete()) transfer.tempFile.deleteOnExit();
            JSObject result = new JSObject();
            result.put("uri", uri.toString());
            call.resolve(result);
        } catch (Exception error) {
            transfer.tempFile.delete();
            call.reject("Unable to save download", error);
        }
    }

    @PluginMethod
    public void cancelBlobDownload(PluginCall call) {
        String transferId = call.getString("transferId");
        BlobTransfer transfer = transfers.remove(transferId);
        if (transfer != null) {
            try {
                transfer.output.close();
            } catch (IOException ignored) {
                // Best-effort cleanup only.
            }
            transfer.tempFile.delete();
        }
        call.resolve();
    }

    private Uri publishToDownloads(BlobTransfer transfer) throws IOException {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContentResolver resolver = getContext().getContentResolver();
            ContentValues values = new ContentValues();
            values.put(MediaStore.Downloads.DISPLAY_NAME, transfer.fileName);
            values.put(MediaStore.Downloads.MIME_TYPE, transfer.mimeType);
            values.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/小猪作业");
            values.put(MediaStore.Downloads.IS_PENDING, 1);
            Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (uri == null) throw new IOException("Unable to create Downloads entry");
            try {
                try (InputStream input = new FileInputStream(transfer.tempFile); OutputStream output = resolver.openOutputStream(uri)) {
                    if (output == null) throw new IOException("Unable to open Downloads output");
                    copy(input, output);
                }
                ContentValues ready = new ContentValues();
                ready.put(MediaStore.Downloads.IS_PENDING, 0);
                resolver.update(uri, ready, null, null);
                return uri;
            } catch (Exception error) {
                resolver.delete(uri, null, null);
                throw error;
            }
        }

        File directory = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
        if (!directory.exists() && !directory.mkdirs()) throw new IOException("Unable to create Downloads directory");
        File target = uniqueFile(directory, transfer.fileName);
        try (InputStream input = new FileInputStream(transfer.tempFile); OutputStream output = new FileOutputStream(target)) {
            copy(input, output);
        }
        return Uri.fromFile(target);
    }

    private static void copy(InputStream input, OutputStream output) throws IOException {
        byte[] buffer = new byte[64 * 1024];
        int read;
        while ((read = input.read(buffer)) != -1) output.write(buffer, 0, read);
        output.flush();
    }

    private static File uniqueFile(File directory, String fileName) {
        File candidate = new File(directory, fileName);
        if (!candidate.exists()) return candidate;
        int dot = fileName.lastIndexOf('.');
        String base = dot > 0 ? fileName.substring(0, dot) : fileName;
        String extension = dot > 0 ? fileName.substring(dot) : "";
        for (int suffix = 1; suffix < 10_000; suffix++) {
            candidate = new File(directory, base + " (" + suffix + ")" + extension);
            if (!candidate.exists()) return candidate;
        }
        return new File(directory, UUID.randomUUID() + extension);
    }

    private static boolean isHttpUrl(String value) {
        if (value == null) return false;
        try {
            String scheme = Uri.parse(value).getScheme();
            return "http".equalsIgnoreCase(scheme) || "https".equalsIgnoreCase(scheme);
        } catch (Exception ignored) {
            return false;
        }
    }

    private static String sanitizeFileName(String input) {
        String cleaned = input == null ? "download" : input.replaceAll("[\\\\/:*?\"<>|\\p{Cntrl}]", "_").trim();
        while (cleaned.startsWith(".")) cleaned = cleaned.substring(1);
        if (cleaned.isBlank()) cleaned = "download";
        return cleaned.length() > 180 ? cleaned.substring(0, 180) : cleaned;
    }
}
