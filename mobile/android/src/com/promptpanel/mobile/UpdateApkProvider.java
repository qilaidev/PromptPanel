package com.promptpanel.mobile;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;

public class UpdateApkProvider extends ContentProvider {
    public static final String AUTHORITY = "com.promptpanel.mobile.apkprovider";
    private static final String APK_MIME = "application/vnd.android.package-archive";

    public static File getStagedApkFile(Context context) {
        File dir = new File(context.getCacheDir(), "updates");
        if (!dir.exists()) {
            dir.mkdirs();
        }
        return new File(dir, "PromptPanel-latest.apk");
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public String getType(Uri uri) {
        return APK_MIME;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        Context ctx = getContext();
        if (ctx == null) {
            return null;
        }
        File file = getStagedApkFile(ctx);
        if (!file.exists()) {
            return null;
        }
        String[] cols = projection != null
                ? projection
                : new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE};
        String[] outCols = new String[cols.length];
        Object[] outVals = new Object[cols.length];
        int count = 0;
        for (int i = 0; i < cols.length; i++) {
            String col = cols[i];
            if (OpenableColumns.DISPLAY_NAME.equals(col)) {
                outCols[count] = OpenableColumns.DISPLAY_NAME;
                outVals[count] = file.getName();
                count++;
            } else if (OpenableColumns.SIZE.equals(col)) {
                outCols[count] = OpenableColumns.SIZE;
                outVals[count] = Long.valueOf(file.length());
                count++;
            }
        }
        String[] finalCols = new String[count];
        Object[] finalVals = new Object[count];
        System.arraycopy(outCols, 0, finalCols, 0, count);
        System.arraycopy(outVals, 0, finalVals, 0, count);
        MatrixCursor cursor = new MatrixCursor(finalCols, 1);
        cursor.addRow(finalVals);
        return cursor;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        Context ctx = getContext();
        if (ctx == null) {
            throw new FileNotFoundException("Missing provider context");
        }
        File file = getStagedApkFile(ctx);
        if (!file.exists() || !file.isFile()) {
            throw new FileNotFoundException("Staged update APK not found");
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException("Read-only provider");
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("Read-only provider");
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        throw new UnsupportedOperationException("Read-only provider");
    }
}
