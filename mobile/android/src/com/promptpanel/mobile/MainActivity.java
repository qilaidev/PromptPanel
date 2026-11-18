package com.promptpanel.mobile;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.res.Configuration;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.graphics.Color;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.util.Log;
import android.view.KeyEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.ConnectException;
import java.net.HttpURLConnection;
import java.net.MalformedURLException;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.net.UnknownHostException;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.util.Iterator;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.Mac;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import javax.net.ssl.SSLException;

import org.json.JSONObject;

public class MainActivity extends Activity implements View.OnKeyListener, Runnable {
    private static final String PREFS_NAME = "promptpanel_mobile_prefs";
    private static final String KEY_LEGACY_STORE = "promptpanel_mobile_store_v2";
    private static final String KEY_ENDPOINT = "promptpanel_cloud_endpoint";
    private static final String KEY_LEGACY_API_KEY = "promptpanel_cloud_api_key";
    private static final String KEY_ENCRYPTED_API_KEY = "promptpanel_cloud_api_key_enc_v1";
    private static final String KEY_THEME = "promptpanel_app_theme";
    private static final String KEY_SORT_MODE = "promptpanel_entry_sort_mode";
    private static final String KEY_AUTO_SYNC = "promptpanel_cloud_sync_enabled";
    private static final String KEY_AUTO_UPDATE = "promptpanel_auto_update_enabled";

    private static final String KEYSTORE_PROVIDER = "AndroidKeyStore";
    private static final String KEY_ALIAS = "promptpanel_sync_token_master_key_v1";
    private static final String DB_NAME = "promptpanel_v2.db";
    private static final String DB_STORE_KEY = "envelope_v2";
    private static final long SNAPSHOT_INTERVAL_MS = 5 * 60 * 1000L; // 5 minutes throttle for rolling snapshots

    private static final int REQUEST_SELECT_FILE = 1001;

    private WebView webView;
    private SQLiteDatabase sqliteDb;
    private ValueCallback<Uri[]> filePathCallback;
    private volatile boolean hasOpenModal = false;
    private volatile String pendingThemeMode = "system";
    private volatile String cachedStoreJson = null;
    private volatile String lastPersistedStoreJson = null;
    private volatile String cachedApiKey = null;
    private volatile SecretKey cachedHardwareSecretKey = null;
    private volatile String cachedDerivedToken = null;
    private volatile byte[] cachedDerivedAeadKey = null;
    private volatile long lastSnapshotTimeMs = 0L;
    private volatile boolean isUpdateCheckRunning = false;
    private volatile boolean pendingInstallAfterUnknownSources = false;
    private volatile boolean isActivityDestroyed = false;

    private final ExecutorService httpExecutor = Executors.newFixedThreadPool(3);
    private final ExecutorService dbWriteExecutor = Executors.newSingleThreadExecutor();
    private final Object storeWriteLock = new Object();
    private String pendingStoreJson = null;
    private boolean isStoreWriteScheduled = false;

    private OnBackInvokedCallback backInvokedCallback = null;
    private boolean isBackCallbackRegistered = false;

    private volatile int safeTopDp = 0;
    private volatile int safeBottomDp = 0;
    private volatile int imeBottomDp = 0;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        initSqliteStorageAndMigrate();
        migrateLegacyPlaintextToken();
        if (Build.VERSION.SDK_INT >= 30) {
            getWindow().setDecorFitsSystemWindows(false);
        }
        applySystemBarAppearance(getThemeMode());

        final long currentVersionCode = getAppVersionCode();
        dbWriteExecutor.execute(new PruneUpdatesTask(this, currentVersionCode));

        webView = new WebView(this);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        // Keep asset/file loading compatible across all OEM ROMs while blocking cross-file URL access
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setSaveFormData(false);
        settings.setGeolocationEnabled(false);
        settings.setSupportMultipleWindows(false);
        settings.setTextZoom(100);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);

        webView.setWebChromeClient(new SafeWebChromeClient(this));
        webView.setWebViewClient(new SafeWebViewClient());
        webView.addJavascriptInterface(this, "AndroidBridge");
        webView.setOnKeyListener(this);

        if (Build.VERSION.SDK_INT >= 33) {
            backInvokedCallback = new BackInvokedHandler(this);
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
            webView.setOnApplyWindowInsetsListener(new InsetsApplyListener(this));
        }

        setContentView(webView);
        webView.loadUrl("file:///android_asset/index.html");
    }

    private void injectSafeAreaInsetsToWebView() {
        if (webView == null || isActivityDestroyed) return;
        final String js = "try{var r=document.documentElement.style;"
                + "r.setProperty('--safe-top','" + safeTopDp + "px');"
                + "r.setProperty('--safe-bottom','" + safeBottomDp + "px');"
                + "r.setProperty('--ime-bottom','" + imeBottomDp + "px');"
                + "}catch(e){}";
        webView.post(new EvalJsTask(this, js));
    }

    void evalJsOnUiThread(String js) {
        if (webView != null && !isActivityDestroyed && js != null) {
            webView.evaluateJavascript(js, null);
        }
    }

    void handleInsetsChanged(WindowInsets insets) {
        float density = getResources().getDisplayMetrics().density;
        if (density <= 0f) density = 1f;
        int topPx = 0;
        int bottomPx = 0;
        int imePx = 0;
        if (Build.VERSION.SDK_INT >= 30) {
            Insets sysBars = insets.getInsets(WindowInsets.Type.systemBars());
            Insets imeInsets = insets.getInsets(WindowInsets.Type.ime());
            topPx = sysBars.top;
            bottomPx = sysBars.bottom;
            imePx = Math.max(0, imeInsets.bottom - sysBars.bottom);
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            topPx = insets.getSystemWindowInsetTop();
            bottomPx = insets.getSystemWindowInsetBottom();
        }
        safeTopDp = Math.round(topPx / density);
        safeBottomDp = Math.round(bottomPx / density);
        imeBottomDp = Math.round(imePx / density);
        injectSafeAreaInsetsToWebView();
    }

    boolean openQrImagePicker(ValueCallback<Uri[]> callback) {
        if (filePathCallback != null) {
            filePathCallback.onReceiveValue(null);
        }
        filePathCallback = callback;
        try {
            Intent pickIntent = new Intent(Intent.ACTION_GET_CONTENT);
            pickIntent.addCategory(Intent.CATEGORY_OPENABLE);
            pickIntent.setType("image/*");
            startActivityForResult(Intent.createChooser(pickIntent, "选择配对二维码图片"), REQUEST_SELECT_FILE);
            return true;
        } catch (Exception e) {
            filePathCallback = null;
            return false;
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQUEST_SELECT_FILE) {
            if (filePathCallback != null) {
                Uri[] results = null;
                if (resultCode == Activity.RESULT_OK && data != null && data.getData() != null) {
                    results = new Uri[]{data.getData()};
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    results = WebChromeClient.FileChooserParams.parseResult(resultCode, data);
                }
                filePathCallback.onReceiveValue(results);
                filePathCallback = null;
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (pendingInstallAfterUnknownSources) {
            pendingInstallAfterUnknownSources = false;
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || getPackageManager().canRequestPackageInstalls()) {
                installDownloadedUpdate();
            } else if (webView != null && !isActivityDestroyed) {
                webView.evaluateJavascript("if(window.__onInstallPermissionDenied)window.__onInstallPermissionDenied();", null);
            }
        }
        injectSafeAreaInsetsToWebView();
        if (webView != null && !isActivityDestroyed) {
            webView.evaluateJavascript("if(window.__onAppResume)window.__onAppResume();", null);
        }
    }

    @Override
    protected void onPause() {
        flushPendingStoreSync();
        super.onPause();
    }

    @Override
    protected void onStop() {
        flushPendingStoreSync();
        super.onStop();
    }

    @Override
    protected void onDestroy() {
        isActivityDestroyed = true;
        flushPendingStoreSync();
        if (Build.VERSION.SDK_INT >= 33 && isBackCallbackRegistered && backInvokedCallback != null) {
            try {
                getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(backInvokedCallback);
            } catch (Exception ignored) {
            }
            isBackCallbackRegistered = false;
        }
        httpExecutor.shutdownNow();
        dbWriteExecutor.shutdown();
        if (webView != null) {
            try {
                webView.stopLoading();
                webView.removeJavascriptInterface("AndroidBridge");
                webView.destroy();
            } catch (Exception ignored) {
            }
            webView = null;
        }
        if (sqliteDb != null && sqliteDb.isOpen()) {
            sqliteDb.close();
        }
        super.onDestroy();
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        if (hasOpenModal && webView != null && !isActivityDestroyed) {
            webView.evaluateJavascript("if(window.__handleBackPress)window.__handleBackPress();", null);
            return;
        }
        super.onBackPressed();
    }

    private void syncBackInvokedCallback(boolean shouldIntercept) {
        if (Build.VERSION.SDK_INT < 33 || backInvokedCallback == null || isActivityDestroyed) {
            return;
        }
        try {
            if (shouldIntercept && !isBackCallbackRegistered) {
                getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                        OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                        backInvokedCallback
                );
                isBackCallbackRegistered = true;
            } else if (!shouldIntercept && isBackCallbackRegistered) {
                getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(backInvokedCallback);
                isBackCallbackRegistered = false;
            }
        } catch (Exception ignored) {
        }
    }

    @Override
    public boolean onKey(View v, int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK
                && event.getAction() == KeyEvent.ACTION_UP
                && hasOpenModal) {
            if (webView != null && !isActivityDestroyed) {
                webView.evaluateJavascript("if(window.__handleBackPress)window.__handleBackPress();", null);
            }
            return true;
        }
        return false;
    }

    @Override
    public void run() {
        applySystemBarAppearance(pendingThemeMode);
    }

    private synchronized SQLiteDatabase getDb() {
        if (sqliteDb == null || !sqliteDb.isOpen()) {
            sqliteDb = openOrCreateDatabase(DB_NAME, Context.MODE_PRIVATE, null);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                sqliteDb.enableWriteAheadLogging();
            }
            execPragmaQuietly(sqliteDb, "PRAGMA busy_timeout=5000");
            execPragmaQuietly(sqliteDb, "PRAGMA synchronous=NORMAL");
            sqliteDb.execSQL(
                    "CREATE TABLE IF NOT EXISTS kv_store ("
                            + "k TEXT PRIMARY KEY, "
                            + "v TEXT NOT NULL, "
                            + "updated_at INTEGER NOT NULL)"
            );
            sqliteDb.execSQL(
                    "CREATE TABLE IF NOT EXISTS store_snapshots ("
                            + "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                            + "payload TEXT NOT NULL, "
                            + "created_at INTEGER NOT NULL)"
            );
        }
        return sqliteDb;
    }

    private void execPragmaQuietly(SQLiteDatabase db, String pragmaSql) {
        Cursor c = null;
        try {
            c = db.rawQuery(pragmaSql, null);
            if (c != null) {
                c.moveToFirst();
            }
        } catch (Exception ignored) {
        } finally {
            if (c != null) {
                c.close();
            }
        }
    }

    private String decodeStoredPayload(String rawVal) {
        if (rawVal == null || rawVal.isEmpty()) {
            return "";
        }
        if (rawVal.startsWith("v1:") || rawVal.startsWith("fb:")) {
            return decryptToken(rawVal);
        }
        return rawVal;
    }

    private void initSqliteStorageAndMigrate() {
        try {
            SQLiteDatabase db = getDb();
            SharedPreferences sp = prefs();
            String legacyJson = sp.getString(KEY_LEGACY_STORE, "");
            if (legacyJson != null && !legacyJson.trim().isEmpty()) {
                String existing = readSqliteStore(db);
                if (existing == null || existing.trim().isEmpty()) {
                    writeSqliteStore(db, legacyJson, true);
                }
                sp.edit().remove(KEY_LEGACY_STORE).apply();
            }
        } catch (Exception ignored) {
        }
    }

    private String readSqliteStore(SQLiteDatabase db) {
        if (cachedStoreJson != null) {
            return cachedStoreJson;
        }
        Cursor cursor = null;
        try {
            cursor = db.rawQuery("SELECT v FROM kv_store WHERE k = ? LIMIT 1", new String[]{DB_STORE_KEY});
            if (cursor != null && cursor.moveToFirst()) {
                String rawVal = cursor.getString(0);
                String decoded = decodeStoredPayload(rawVal);
                if (decoded != null && !decoded.isEmpty()) {
                    cachedStoreJson = decoded;
                    lastPersistedStoreJson = decoded;
                    return cachedStoreJson;
                }
            }
        } catch (Exception ignored) {
        } finally {
            if (cursor != null) {
                cursor.close();
            }
        }

        // Self-healing fallback: attempt recovery from rolling snapshots if primary row is missing or unreadable
        Cursor snapCursor = null;
        try {
            snapCursor = db.rawQuery("SELECT payload FROM store_snapshots ORDER BY id DESC LIMIT 5", null);
            if (snapCursor != null) {
                while (snapCursor.moveToNext()) {
                    String snapRaw = snapCursor.getString(0);
                    String recovered = decodeStoredPayload(snapRaw);
                    if (recovered != null && !recovered.trim().isEmpty()) {
                        cachedStoreJson = recovered;
                        writeSqliteStore(db, recovered, false);
                        return cachedStoreJson;
                    }
                }
            }
        } catch (Exception ignored) {
        } finally {
            if (snapCursor != null) {
                snapCursor.close();
            }
        }
        return "";
    }

    private void writeSqliteStore(SQLiteDatabase db, String json, boolean forceSnapshot) {
        String safeJson = json != null ? json : "";
        cachedStoreJson = safeJson;
        if (!forceSnapshot && safeJson.equals(lastPersistedStoreJson) && !safeJson.isEmpty()) {
            return;
        }
        String encryptedAtRest = safeJson.isEmpty() ? "" : encryptToken(safeJson);
        String toPersist = !encryptedAtRest.isEmpty() ? encryptedAtRest : safeJson;
        long now = System.currentTimeMillis();
        boolean takeSnapshot = !safeJson.isEmpty()
                && (forceSnapshot || (now - lastSnapshotTimeMs >= SNAPSHOT_INTERVAL_MS));

        db.beginTransactionNonExclusive();
        try {
            ContentValues values = new ContentValues();
            values.put("k", DB_STORE_KEY);
            values.put("v", toPersist);
            values.put("updated_at", now);
            db.insertWithOnConflict("kv_store", null, values, SQLiteDatabase.CONFLICT_REPLACE);

            if (takeSnapshot) {
                lastSnapshotTimeMs = now;
                ContentValues snap = new ContentValues();
                snap.put("payload", toPersist);
                snap.put("created_at", now);
                db.insert("store_snapshots", null, snap);
                db.execSQL(
                        "DELETE FROM store_snapshots WHERE id NOT IN ("
                                + "SELECT id FROM store_snapshots ORDER BY id DESC LIMIT 5)"
                );
            }
            db.setTransactionSuccessful();
            lastPersistedStoreJson = safeJson;
        } finally {
            db.endTransaction();
        }
    }

    private synchronized SecretKey getOrCreateHardwareSecretKey() throws Exception {
        if (cachedHardwareSecretKey != null) {
            return cachedHardwareSecretKey;
        }
        KeyStore ks = KeyStore.getInstance(KEYSTORE_PROVIDER);
        ks.load(null);
        if (ks.containsAlias(KEY_ALIAS)) {
            KeyStore.Entry entry = ks.getEntry(KEY_ALIAS, null);
            if (entry instanceof KeyStore.SecretKeyEntry) {
                cachedHardwareSecretKey = ((KeyStore.SecretKeyEntry) entry).getSecretKey();
                return cachedHardwareSecretKey;
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            KeyGenerator keyGen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER);
            KeyGenParameterSpec spec = new KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT
            )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build();
            keyGen.init(spec);
            cachedHardwareSecretKey = keyGen.generateKey();
            return cachedHardwareSecretKey;
        }
        return null;
    }

    private String encryptToken(String plainToken) {
        if (plainToken == null || plainToken.isEmpty()) {
            return "";
        }
        for (int attempt = 0; attempt < 2; attempt++) {
            try {
                SecretKey key = getOrCreateHardwareSecretKey();
                if (key != null) {
                    Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
                    cipher.init(Cipher.ENCRYPT_MODE, key);
                    byte[] iv = cipher.getIV();
                    byte[] cipherBytes = cipher.doFinal(plainToken.getBytes(StandardCharsets.UTF_8));
                    return "v1:"
                            + Base64.encodeToString(iv, Base64.NO_WRAP)
                            + ":"
                            + Base64.encodeToString(cipherBytes, Base64.NO_WRAP);
                }
                break;
            } catch (Exception ignored) {
                cachedHardwareSecretKey = null;
            }
        }
        // Graceful fallback if OEM KeyStore is unavailable on a custom ROM
        return "fb:" + Base64.encodeToString(plainToken.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
    }

    private String decryptToken(String encoded) {
        if (encoded == null || encoded.isEmpty()) {
            return "";
        }
        if (encoded.startsWith("fb:")) {
            try {
                byte[] raw = Base64.decode(encoded.substring(3), Base64.NO_WRAP);
                return new String(raw, StandardCharsets.UTF_8);
            } catch (Exception ignored) {
                return "";
            }
        }
        String payload = encoded.startsWith("v1:") ? encoded.substring(3) : encoded;
        int sep = payload.indexOf(':');
        if (sep <= 0) {
            return "";
        }
        for (int attempt = 0; attempt < 2; attempt++) {
            try {
                SecretKey key = getOrCreateHardwareSecretKey();
                if (key == null) {
                    return "";
                }
                byte[] iv = Base64.decode(payload.substring(0, sep), Base64.NO_WRAP);
                byte[] cipherBytes = Base64.decode(payload.substring(sep + 1), Base64.NO_WRAP);
                Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
                cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(128, iv));
                byte[] plain = cipher.doFinal(cipherBytes);
                return new String(plain, StandardCharsets.UTF_8);
            } catch (Exception ignored) {
                cachedHardwareSecretKey = null;
            }
        }
        return "";
    }

    private void migrateLegacyPlaintextToken() {
        SharedPreferences sp = prefs();
        String legacy = sp.getString(KEY_LEGACY_API_KEY, "");
        if (legacy != null && !legacy.trim().isEmpty()) {
            String clean = legacy.trim();
            String enc = encryptToken(clean);
            cachedApiKey = clean;
            SharedPreferences.Editor editor = sp.edit().remove(KEY_LEGACY_API_KEY);
            if (!enc.isEmpty()) {
                editor.putString(KEY_ENCRYPTED_API_KEY, enc);
            }
            editor.apply();
        }
    }

    @SuppressWarnings("deprecation")
    private void applySystemBarAppearance(String themeMode) {
        Window window = getWindow();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS);
            window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
            boolean sysNight = (getResources().getConfiguration().uiMode
                    & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
            boolean isNight = "dark".equals(themeMode) || (!"light".equals(themeMode) && sysNight);

            if (Build.VERSION.SDK_INT >= 30) {
                window.setStatusBarColor(Color.TRANSPARENT);
                window.setNavigationBarColor(Color.TRANSPARENT);
                WindowInsetsController controller = window.getInsetsController();
                if (controller != null) {
                    int lightMask = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                            | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                    controller.setSystemBarsAppearance(isNight ? 0 : lightMask, lightMask);
                }
            } else {
                window.setStatusBarColor(Color.parseColor(isNight ? "#17181C" : "#FFFFFF"));
                window.setNavigationBarColor(Color.parseColor(isNight ? "#141518" : "#F3F4F7"));
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    int flags = window.getDecorView().getSystemUiVisibility();
                    if (isNight) {
                        flags &= ~View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
                    } else {
                        flags |= View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
                    }
                    window.getDecorView().setSystemUiVisibility(flags);
                }
            }
        }
    }

    private SharedPreferences prefs() {
        return getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    @JavascriptInterface
    public void setModalOpen(final boolean open) {
        this.hasOpenModal = open;
        runOnUiThread(new SyncBackCallbackTask(this, open));
    }

    @JavascriptInterface
    public String getSafeAreaInsets() {
        return "{\"top\":" + safeTopDp + ",\"bottom\":" + safeBottomDp + ",\"ime\":" + imeBottomDp + "}";
    }

    @JavascriptInterface
    public synchronized String loadStore() {
        try {
            return readSqliteStore(getDb());
        } catch (Exception ignored) {
            return cachedStoreJson != null ? cachedStoreJson : "";
        }
    }

    @JavascriptInterface
    public void saveStore(String json) {
        final String safeJson = json != null ? json : "";
        cachedStoreJson = safeJson;
        synchronized (storeWriteLock) {
            pendingStoreJson = safeJson;
            if (!isStoreWriteScheduled && !isActivityDestroyed) {
                isStoreWriteScheduled = true;
                dbWriteExecutor.execute(new DrainStoreWritesTask(this));
            }
        }
    }

    void drainPendingStoreWrites() {
        while (true) {
            final String nextJson;
            synchronized (storeWriteLock) {
                if (pendingStoreJson == null) {
                    isStoreWriteScheduled = false;
                    return;
                }
                nextJson = pendingStoreJson;
                pendingStoreJson = null;
            }
            try {
                synchronized (MainActivity.this) {
                    writeSqliteStore(getDb(), nextJson, false);
                }
            } catch (final Exception e) {
                Log.e("PromptPanel", "SQLite saveStore failed", e);
                String errMsg = e.getMessage() != null ? e.getMessage() : e.toString();
                runOnUiThread(new EvalJsTask(
                        this,
                        "if(window.__onStorageError)window.__onStorageError(" + JSONObject.quote(errMsg) + ");"
                ));
            }
        }
    }

    private void flushPendingStoreSync() {
        boolean hasPending;
        synchronized (storeWriteLock) {
            hasPending = pendingStoreJson != null || isStoreWriteScheduled;
        }
        if (!hasPending) {
            return;
        }
        final CountDownLatch latch = new CountDownLatch(1);
        try {
            dbWriteExecutor.execute(new FlushLatchTask(this, latch));
            latch.await(1500, TimeUnit.MILLISECONDS);
        } catch (Exception ignored) {
        }
    }

    @JavascriptInterface
    public String getEndpoint() {
        return prefs().getString(KEY_ENDPOINT, "");
    }

    @JavascriptInterface
    public String getApiKey() {
        if (cachedApiKey != null) {
            return cachedApiKey;
        }
        String enc = prefs().getString(KEY_ENCRYPTED_API_KEY, "");
        cachedApiKey = decryptToken(enc);
        return cachedApiKey;
    }

    @JavascriptInterface
    public boolean getAutoSync() {
        return prefs().getBoolean(KEY_AUTO_SYNC, false);
    }

    @JavascriptInterface
    public void saveSettings(String endpoint, String apiKey) {
        String cleanEp = endpoint != null ? endpoint.trim() : "";
        String cleanKey = apiKey != null ? apiKey.trim() : "";
        cachedApiKey = cleanKey;
        String encKey = cleanKey.isEmpty() ? "" : encryptToken(cleanKey);
        prefs().edit()
                .putString(KEY_ENDPOINT, cleanEp)
                .putString(KEY_ENCRYPTED_API_KEY, encKey)
                .remove(KEY_LEGACY_API_KEY)
                .apply();
    }

    @JavascriptInterface
    public void setAutoSync(boolean enabled) {
        prefs().edit().putBoolean(KEY_AUTO_SYNC, enabled).apply();
    }

    @JavascriptInterface
    public boolean getAutoUpdate() {
        return prefs().getBoolean(KEY_AUTO_UPDATE, false);
    }

    @JavascriptInterface
    public void setAutoUpdate(boolean enabled) {
        prefs().edit().putBoolean(KEY_AUTO_UPDATE, enabled).apply();
    }

    private String getAppVersionName() {
        try {
            PackageInfo pi = getPackageManager().getPackageInfo(getPackageName(), 0);
            if (pi.versionName != null && !pi.versionName.isEmpty()) {
                return pi.versionName;
            }
        } catch (Exception ignored) {
        }
        return "0.0.0";
    }

    private int getAppVersionCode() {
        try {
            PackageInfo pi = getPackageManager().getPackageInfo(getPackageName(), 0);
            return Build.VERSION.SDK_INT >= 28 ? (int) pi.getLongVersionCode() : pi.versionCode;
        } catch (Exception ignored) {
            return 0;
        }
    }

    @JavascriptInterface
    public String getAppVersionInfo() {
        return getAppVersionName() + "+" + getAppVersionCode();
    }

    @JavascriptInterface
    public void checkAppUpdate(boolean manual, boolean autoDownload) {
        if (isUpdateCheckRunning) {
            return;
        }
        isUpdateCheckRunning = true;
        int code = getAppVersionCode();
        String name = getAppVersionName();
        Thread worker = new Thread(new UpdateDownloadTask(
                this,
                getEndpoint(),
                code,
                name,
                manual,
                autoDownload
        ));
        worker.setDaemon(true);
        worker.start();
    }

    void deliverUpdateResultToWebView(String payloadJson, boolean markFinished) {
        if (markFinished) {
            isUpdateCheckRunning = false;
        }
        if (webView != null && payloadJson != null) {
            String quoted = JSONObject.quote(payloadJson);
            webView.evaluateJavascript(
                    "if(window.__onUpdateCheckResult)window.__onUpdateCheckResult(" + quoted + ");",
                    null
            );
        }
    }

    @JavascriptInterface
    public String installDownloadedUpdate() {
        try {
            File stagedFile = UpdateApkProvider.getStagedApkFile(this);
            if (!stagedFile.exists() || stagedFile.length() < 100000L) {
                return "MISSING_APK";
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    && !getPackageManager().canRequestPackageInstalls()) {
                pendingInstallAfterUnknownSources = true;
                Intent permIntent = new Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + getPackageName())
                );
                permIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(permIntent);
                return "NEED_INSTALL_PERMISSION";
            }
            Intent installIntent = new Intent(Intent.ACTION_VIEW);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                Uri apkUri = Uri.parse("content://" + UpdateApkProvider.AUTHORITY + "/PromptPanel-latest.apk");
                installIntent.setDataAndType(apkUri, "application/vnd.android.package-archive");
                installIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            } else {
                installIntent.setDataAndType(Uri.fromFile(stagedFile), "application/vnd.android.package-archive");
            }
            installIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(installIntent);
            return "LAUNCHED";
        } catch (Exception e) {
            return "ERROR:" + (e.getMessage() != null ? e.getMessage() : e.toString());
        }
    }

    @JavascriptInterface
    public String getThemeMode() {
        return prefs().getString(KEY_THEME, "system");
    }

    @JavascriptInterface
    public void setThemeMode(String mode) {
        String resolved = (mode != null && !mode.isEmpty()) ? mode : "system";
        this.pendingThemeMode = resolved;
        prefs().edit().putString(KEY_THEME, resolved).apply();
        runOnUiThread(this);
    }

    @JavascriptInterface
    public String getSortMode() {
        return prefs().getString(KEY_SORT_MODE, "uses");
    }

    @JavascriptInterface
    public void setSortMode(String mode) {
        prefs().edit().putString(KEY_SORT_MODE, mode != null ? mode : "uses").apply();
    }

    @JavascriptInterface
    public void copyText(final String label, final String text) {
        runOnUiThread(new CopyTextTask(this, label, text));
    }

    void performCopyTextOnUi(String label, String text) {
        try {
            ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard != null) {
                ClipData clip = ClipData.newPlainText(label != null ? label : "PromptPanel", text != null ? text : "");
                clipboard.setPrimaryClip(clip);
            }
        } catch (Exception ignored) {
        }
    }

    @JavascriptInterface
    public boolean shareText(final String title, final String text) {
        if (text == null || text.isEmpty()) {
            return false;
        }
        runOnUiThread(new ShareTextTask(this, title, text));
        return true;
    }

    void performShareTextOnUi(String title, String text) {
        try {
            Intent sendIntent = new Intent(Intent.ACTION_SEND);
            sendIntent.setType("text/plain");
            sendIntent.putExtra(Intent.EXTRA_TEXT, text);
            if (title != null && !title.trim().isEmpty()) {
                sendIntent.putExtra(Intent.EXTRA_SUBJECT, title.trim());
            }
            String chooserTitle = (title != null && !title.trim().isEmpty()) ? title.trim() : "分享内容";
            Intent chooser = Intent.createChooser(sendIntent, chooserTitle);
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(chooser);
        } catch (Exception ignored) {
        }
    }

    @JavascriptInterface
    public String readClipboardText() {
        try {
            ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard != null && clipboard.hasPrimaryClip()) {
                ClipData clip = clipboard.getPrimaryClip();
                if (clip != null && clip.getItemCount() > 0) {
                    CharSequence cs = clip.getItemAt(0).coerceToText(this);
                    return cs != null ? cs.toString() : "";
                }
            }
        } catch (Exception ignored) {
        }
        return "";
    }

    private static final byte[] HKDF_SALT_V2 = "PromptPanel-HKDF-Salt-v2".getBytes(StandardCharsets.UTF_8);
    private static final byte[] HKDF_INFO_AEAD_V2 = "promptpanel-v2-aes256gcm-key\u0001".getBytes(StandardCharsets.UTF_8);
    private static final byte[] WIRE_AAD_V2 = "promptpanel-aead-v2".getBytes(StandardCharsets.UTF_8);
    private final SecureRandom secureRandom = new SecureRandom();

    private synchronized byte[] deriveSyncAeadKey(String token) throws Exception {
        String clean = token != null ? token.trim() : "";
        if (!clean.isEmpty() && clean.equals(cachedDerivedToken) && cachedDerivedAeadKey != null) {
            return cachedDerivedAeadKey;
        }
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(HKDF_SALT_V2, "HmacSHA256"));
        byte[] prk = mac.doFinal(clean.getBytes(StandardCharsets.UTF_8));
        mac.init(new SecretKeySpec(prk, "HmacSHA256"));
        byte[] derived = mac.doFinal(HKDF_INFO_AEAD_V2);
        cachedDerivedToken = clean;
        cachedDerivedAeadKey = derived;
        return derived;
    }

    static String translateNetworkException(Exception e) {
        if (e == null) {
            return "未知网络错误";
        }
        if (e instanceof MalformedURLException) {
            return "同步服务地址格式无效，请检查 http:// 或 https:// 地址";
        }
        if (e instanceof UnknownHostException) {
            return "无法解析服务器域名，请检查网络或同步地址是否正确";
        }
        if (e instanceof SocketTimeoutException) {
            return "连接同步服务器超时，请检查网络状况或服务是否在线";
        }
        if (e instanceof ConnectException) {
            return "连接被拒绝，请确认同步服务已启动且端口正确";
        }
        if (e instanceof SSLException) {
            return "HTTPS 安全连接校验失败，请检查证书或协议配置";
        }
        if (e instanceof IllegalArgumentException) {
            String msg = e.getMessage();
            if (msg != null && !msg.isEmpty()) {
                return msg;
            }
            return "请求参数或加密数据包格式无效";
        }
        if (e instanceof IOException) {
            String msg = e.getMessage();
            return "网络通信中断" + (msg != null && !msg.isEmpty() ? "：" + msg : "，请检查网络连接");
        }
        return e.getMessage() != null ? e.getMessage() : e.toString();
    }

    private String sealSyncEnvelope(String plainJson, String token) throws Exception {
        if (token == null || token.trim().length() < 12 || plainJson == null || plainJson.isEmpty()) {
            return plainJson;
        }
        byte[] aeadKey = deriveSyncAeadKey(token);
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        try (GZIPOutputStream gzos = new GZIPOutputStream(baos)) {
            gzos.write(plainJson.getBytes(StandardCharsets.UTF_8));
        }
        byte[] compressed = baos.toByteArray();

        byte[] nonce = new byte[12];
        secureRandom.nextBytes(nonce);

        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(aeadKey, "AES"), new GCMParameterSpec(128, nonce));
        cipher.updateAAD(WIRE_AAD_V2);
        byte[] ctAndTag = cipher.doFinal(compressed);

        byte[] combined = new byte[nonce.length + ctAndTag.length];
        System.arraycopy(nonce, 0, combined, 0, nonce.length);
        System.arraycopy(ctAndTag, 0, combined, nonce.length, ctAndTag.length);

        JSONObject wrapper = new JSONObject();
        wrapper.put("cipher", "aes-256-gcm+gzip");
        wrapper.put("v", 2);
        wrapper.put("data", Base64.encodeToString(combined, Base64.NO_WRAP));
        return wrapper.toString();
    }

    private String openSyncEnvelopeIfNeeded(String rawResponse, String token) throws Exception {
        if (rawResponse == null || rawResponse.isEmpty() || !rawResponse.contains("\"cipher\"")) {
            return rawResponse;
        }
        JSONObject obj = new JSONObject(rawResponse);
        String cipherName = obj.optString("cipher", "");
        if (!cipherName.startsWith("aes-256-gcm")) {
            return rawResponse;
        }
        String b64Data = obj.optString("data", "");
        if (b64Data.isEmpty() || token == null || token.trim().length() < 12) {
            throw new IllegalArgumentException("加密同步包缺少有效密钥或数据");
        }
        byte[] combined = Base64.decode(b64Data, Base64.DEFAULT);
        if (combined.length < 28) {
            throw new IllegalArgumentException("加密同步包密文长度异常");
        }
        byte[] aeadKey = deriveSyncAeadKey(token);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(aeadKey, "AES"), new GCMParameterSpec(128, combined, 0, 12));
        cipher.updateAAD(WIRE_AAD_V2);
        byte[] decrypted = cipher.doFinal(combined, 12, combined.length - 12);

        if ("aes-256-gcm+gzip".equals(cipherName)
                || (decrypted.length >= 2 && (decrypted[0] & 0xFF) == 0x1F && (decrypted[1] & 0xFF) == 0x8B)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            try (GZIPInputStream gzis = new GZIPInputStream(new ByteArrayInputStream(decrypted))) {
                byte[] buf = new byte[16384];
                int n;
                int total = 0;
                while ((n = gzis.read(buf)) > 0) {
                    total += n;
                    if (total > 16 * 1024 * 1024) {
                        throw new IllegalArgumentException("解压体积超出安全上限");
                    }
                    out.write(buf, 0, n);
                }
            }
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        }
        return new String(decrypted, StandardCharsets.UTF_8);
    }

    static boolean isAllowedRemoteUrl(URL url) {
        if (url == null) return false;
        String proto = url.getProtocol() != null ? url.getProtocol().toLowerCase(Locale.US) : "";
        String host = url.getHost() != null ? url.getHost().toLowerCase(Locale.US) : "";
        if (host.startsWith("[") && host.endsWith("]")) {
            host = host.substring(1, host.length() - 1);
        }
        if (host.isEmpty()) return false;
        if ("https".equals(proto)) return true;
        if ("http".equals(proto)) {
            return "localhost".equals(host)
                    || "127.0.0.1".equals(host)
                    || "::1".equals(host)
                    || "10.0.2.2".equals(host);
        }
        return false;
    }

    @JavascriptInterface
    public void httpRequestAsync(
            final String reqId,
            final String method,
            final String url,
            final String headersJson,
            final String body
    ) {
        if (isActivityDestroyed) {
            return;
        }
        httpExecutor.execute(new HttpAsyncTask(this, reqId, method, url, headersJson, body));
    }

    void executeHttpAsync(String reqId, String method, String url, String headersJson, String body) {
        String bearerToken = "";
        JSONObject extraHeaders = null;
        if (headersJson != null && !headersJson.trim().isEmpty()) {
            String trimmed = headersJson.trim();
            if (trimmed.startsWith("{")) {
                try {
                    extraHeaders = new JSONObject(trimmed);
                    String auth = extraHeaders.optString("Authorization", "");
                    if (auth.isEmpty()) {
                        auth = extraHeaders.optString("authorization", "");
                    }
                    if (auth.regionMatches(true, 0, "Bearer ", 0, 7)) {
                        bearerToken = auth.substring(7).trim();
                    } else if (!auth.isEmpty()) {
                        bearerToken = auth.trim();
                    }
                } catch (Exception ignored) {
                }
            } else {
                bearerToken = trimmed;
            }
        }

        String rawResult = executeHttpWithRetry(method, url, bearerToken, extraHeaders, body);
        int nl = rawResult.indexOf('\n');
        int status = 0;
        String respBody = rawResult;
        if (nl >= 0) {
            try {
                status = Integer.parseInt(rawResult.substring(0, nl).trim());
            } catch (Exception ignored) {
            }
            respBody = rawResult.substring(nl + 1);
        }

        final JSONObject out = new JSONObject();
        try {
            out.put("reqId", reqId != null ? reqId : "");
            out.put("status", status);
            out.put("ok", status >= 200 && status < 300);
            out.put("body", respBody);
        } catch (Exception ignored) {
        }
        final String payload = out.toString();
        runOnUiThread(new EvalJsTask(
                this,
                "window.__resolveNativeHttp && window.__resolveNativeHttp(" + JSONObject.quote(payload) + ")"
        ));
    }

    @JavascriptInterface
    public String httpRequest(String method, String urlStr, String bearerToken, String bodyJson) {
        return executeHttpWithRetry(method, urlStr, bearerToken, null, bodyJson);
    }

    private static boolean isRetryableStatus(int code) {
        return code == 429 || code == 502 || code == 503 || code == 504;
    }

    private String executeHttpWithRetry(
            String method,
            String urlStr,
            String bearerToken,
            JSONObject extraHeaders,
            String bodyJson
    ) {
        for (int attempt = 0; attempt < 2; attempt++) {
            HttpAttemptResult res = executeHttpOnce(method, urlStr, bearerToken, extraHeaders, bodyJson);
            if (attempt == 0 && res.retryable) {
                try {
                    Thread.sleep(450L + secureRandom.nextInt(300));
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    return res.code + "\n" + res.body;
                }
                continue;
            }
            return res.code + "\n" + res.body;
        }
        return "0\n未知网络错误";
    }

    private static final class HttpAttemptResult {
        final int code;
        final String body;
        final boolean retryable;

        HttpAttemptResult(int code, String body, boolean retryable) {
            this.code = code;
            this.body = body;
            this.retryable = retryable;
        }
    }

    private HttpAttemptResult executeHttpOnce(
            String method,
            String urlStr,
            String bearerToken,
            JSONObject extraHeaders,
            String bodyJson
    ) {
        if (urlStr == null || urlStr.trim().isEmpty()) {
            return new HttpAttemptResult(400, "请先填写同步服务地址", false);
        }
        HttpURLConnection conn = null;
        try {
            URL currentUrl = new URL(urlStr.trim());
            String initialProtocol = currentUrl.getProtocol() != null
                    ? currentUrl.getProtocol().toLowerCase(Locale.US)
                    : "";
            if (!"https".equals(initialProtocol) && !"http".equals(initialProtocol)) {
                return new HttpAttemptResult(400, "不支持的协议：" + initialProtocol, false);
            }
            if (!isAllowedRemoteUrl(currentUrl)) {
                return new HttpAttemptResult(400, "为保护同步数据与 Token 安全，远程同步仅允许 https:// 地址（仅本机调试允许 localhost / 127.0.0.1）", false);
            }

            String cleanToken = bearerToken != null ? bearerToken.trim() : "";
            boolean useWireCipher = cleanToken.length() >= 12
                    && !urlStr.endsWith("/health");
            String wireBody = (useWireCipher && "POST".equalsIgnoreCase(method) && bodyJson != null && !bodyJson.isEmpty())
                    ? sealSyncEnvelope(bodyJson, cleanToken)
                    : bodyJson;

            // Follow up to 2 safe redirects (never allow HTTPS -> HTTP protocol downgrade)
            int redirects = 0;
            while (redirects <= 2) {
                conn = (HttpURLConnection) currentUrl.openConnection();
                conn.setInstanceFollowRedirects(false);
                conn.setRequestMethod(method);
                conn.setConnectTimeout(8000);
                conn.setReadTimeout(15000);
                conn.setUseCaches(false);
                conn.setRequestProperty("Accept", "application/json");
                conn.setRequestProperty("Content-Type", "application/json; charset=utf-8");
                conn.setRequestProperty("User-Agent", "PromptPanel-Android/" + getAppVersionName());
                if (extraHeaders != null) {
                    Iterator<String> keys = extraHeaders.keys();
                    while (keys.hasNext()) {
                        String k = keys.next();
                        if (k == null || k.equalsIgnoreCase("Authorization") || k.equalsIgnoreCase("Host")) {
                            continue;
                        }
                        String v = extraHeaders.optString(k, "");
                        if (!v.isEmpty()) {
                            conn.setRequestProperty(k, v);
                        }
                    }
                }
                if (!cleanToken.isEmpty()) {
                    conn.setRequestProperty("Authorization", "Bearer " + cleanToken);
                }
                if (useWireCipher) {
                    conn.setRequestProperty("X-PromptPanel-Cipher", "aes-256-gcm+gzip");
                }
                if ("POST".equalsIgnoreCase(method) && wireBody != null) {
                    conn.setDoOutput(true);
                    byte[] payload = wireBody.getBytes(StandardCharsets.UTF_8);
                    conn.setFixedLengthStreamingMode(payload.length);
                    try (OutputStream os = conn.getOutputStream()) {
                        os.write(payload);
                        os.flush();
                    }
                }

                int code = conn.getResponseCode();
                if (code == 301 || code == 302 || code == 307 || code == 308) {
                    String location = conn.getHeaderField("Location");
                    conn.disconnect();
                    conn = null;
                    if (location == null || location.isEmpty()) {
                        return new HttpAttemptResult(code, "重定向缺少目标地址", false);
                    }
                    URL nextUrl = new URL(currentUrl, location);
                    String nextProto = nextUrl.getProtocol() != null
                            ? nextUrl.getProtocol().toLowerCase(Locale.US)
                            : "";
                    if (("https".equals(initialProtocol) && !"https".equals(nextProto))
                            || !isAllowedRemoteUrl(nextUrl)) {
                        return new HttpAttemptResult(400, "已拦截不安全的协议降级或明文 HTTP 重定向", false);
                    }
                    currentUrl = nextUrl;
                    redirects++;
                    continue;
                }

                InputStream is = (code >= 200 && code < 400) ? conn.getInputStream() : conn.getErrorStream();
                StringBuilder sb = new StringBuilder();
                if (is != null) {
                    try (BufferedReader reader = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
                        char[] buf = new char[8192];
                        int n;
                        int totalChars = 0;
                        while ((n = reader.read(buf)) > 0) {
                            totalChars += n;
                            if (totalChars > 16 * 1024 * 1024) {
                                throw new IllegalArgumentException("响应数据体积超出安全上限");
                            }
                            sb.append(buf, 0, n);
                        }
                    }
                }
                String rawResp = sb.toString().trim();
                if (code >= 200 && code < 300 && useWireCipher && !rawResp.isEmpty()) {
                    rawResp = openSyncEnvelopeIfNeeded(rawResp, cleanToken);
                }
                return new HttpAttemptResult(code, rawResp, isRetryableStatus(code));
            }
            return new HttpAttemptResult(400, "重定向次数过多", false);
        } catch (SocketTimeoutException ste) {
            return new HttpAttemptResult(0, translateNetworkException(ste), true);
        } catch (Exception e) {
            return new HttpAttemptResult(0, translateNetworkException(e), false);
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }

    private static final class PruneUpdatesTask implements Runnable {
        private final MainActivity activity;
        private final long versionCode;

        PruneUpdatesTask(MainActivity activity, long versionCode) {
            this.activity = activity;
            this.versionCode = versionCode;
        }

        @Override
        public void run() {
            UpdateApkProvider.pruneStagedApks(activity, versionCode);
        }
    }

    private static final class BackInvokedHandler implements OnBackInvokedCallback {
        private final MainActivity activity;

        BackInvokedHandler(MainActivity activity) {
            this.activity = activity;
        }

        @Override
        public void onBackInvoked() {
            activity.evalJsOnUiThread("if(window.__handleBackPress)window.__handleBackPress();");
        }
    }

    private static final class InsetsApplyListener implements View.OnApplyWindowInsetsListener {
        private final MainActivity activity;

        InsetsApplyListener(MainActivity activity) {
            this.activity = activity;
        }

        @Override
        public WindowInsets onApplyWindowInsets(View v, WindowInsets insets) {
            activity.handleInsetsChanged(insets);
            return insets;
        }
    }

    private static final class EvalJsTask implements Runnable {
        private final MainActivity activity;
        private final String js;

        EvalJsTask(MainActivity activity, String js) {
            this.activity = activity;
            this.js = js;
        }

        @Override
        public void run() {
            activity.evalJsOnUiThread(js);
        }
    }

    private static final class SyncBackCallbackTask implements Runnable {
        private final MainActivity activity;
        private final boolean open;

        SyncBackCallbackTask(MainActivity activity, boolean open) {
            this.activity = activity;
            this.open = open;
        }

        @Override
        public void run() {
            activity.syncBackInvokedCallback(open);
        }
    }

    private static final class DrainStoreWritesTask implements Runnable {
        private final MainActivity activity;

        DrainStoreWritesTask(MainActivity activity) {
            this.activity = activity;
        }

        @Override
        public void run() {
            activity.drainPendingStoreWrites();
        }
    }

    private static final class FlushLatchTask implements Runnable {
        private final MainActivity activity;
        private final CountDownLatch latch;

        FlushLatchTask(MainActivity activity, CountDownLatch latch) {
            this.activity = activity;
            this.latch = latch;
        }

        @Override
        public void run() {
            activity.drainPendingStoreWrites();
            latch.countDown();
        }
    }

    private static final class CopyTextTask implements Runnable {
        private final MainActivity activity;
        private final String label;
        private final String text;

        CopyTextTask(MainActivity activity, String label, String text) {
            this.activity = activity;
            this.label = label;
            this.text = text;
        }

        @Override
        public void run() {
            activity.performCopyTextOnUi(label, text);
        }
    }

    private static final class ShareTextTask implements Runnable {
        private final MainActivity activity;
        private final String title;
        private final String text;

        ShareTextTask(MainActivity activity, String title, String text) {
            this.activity = activity;
            this.title = title;
            this.text = text;
        }

        @Override
        public void run() {
            activity.performShareTextOnUi(title, text);
        }
    }

    private static final class HttpAsyncTask implements Runnable {
        private final MainActivity activity;
        private final String reqId;
        private final String method;
        private final String url;
        private final String headersJson;
        private final String body;

        HttpAsyncTask(MainActivity activity, String reqId, String method, String url, String headersJson, String body) {
            this.activity = activity;
            this.reqId = reqId;
            this.method = method;
            this.url = url;
            this.headersJson = headersJson;
            this.body = body;
        }

        @Override
        public void run() {
            activity.executeHttpAsync(reqId, method, url, headersJson, body);
        }
    }
}
