package com.promptpanel.mobile;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.view.KeyEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.util.Locale;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.Mac;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

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
    private volatile String cachedApiKey = null;
    private volatile long lastSnapshotTimeMs = 0L;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        initSqliteStorageAndMigrate();
        migrateLegacyPlaintextToken();
        applySystemBarAppearance(getThemeMode());

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

        setContentView(webView);
        webView.loadUrl("file:///android_asset/index.html");
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
        if (webView != null) {
            webView.evaluateJavascript("if(window.__onAppResume)window.__onAppResume();", null);
        }
    }

    @Override
    protected void onDestroy() {
        if (sqliteDb != null && sqliteDb.isOpen()) {
            sqliteDb.close();
        }
        super.onDestroy();
    }

    @Override
    public boolean onKey(View v, int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK
                && event.getAction() == KeyEvent.ACTION_UP
                && hasOpenModal) {
            if (webView != null) {
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
                if (rawVal != null && (rawVal.startsWith("v1:") || rawVal.startsWith("fb:"))) {
                    cachedStoreJson = decryptToken(rawVal);
                } else {
                    cachedStoreJson = rawVal != null ? rawVal : "";
                }
                return cachedStoreJson;
            }
        } catch (Exception ignored) {
        } finally {
            if (cursor != null) {
                cursor.close();
            }
        }
        return "";
    }

    private void writeSqliteStore(SQLiteDatabase db, String json, boolean forceSnapshot) {
        String safeJson = json != null ? json : "";
        cachedStoreJson = safeJson;
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
        } finally {
            db.endTransaction();
        }
    }

    private SecretKey getOrCreateHardwareSecretKey() throws Exception {
        KeyStore ks = KeyStore.getInstance(KEYSTORE_PROVIDER);
        ks.load(null);
        if (ks.containsAlias(KEY_ALIAS)) {
            KeyStore.Entry entry = ks.getEntry(KEY_ALIAS, null);
            if (entry instanceof KeyStore.SecretKeyEntry) {
                return ((KeyStore.SecretKeyEntry) entry).getSecretKey();
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
            return keyGen.generateKey();
        }
        return null;
    }

    private String encryptToken(String plainToken) {
        if (plainToken == null || plainToken.isEmpty()) {
            return "";
        }
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
        } catch (Exception ignored) {
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
            return "";
        }
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

    private void applySystemBarAppearance(String themeMode) {
        Window window = getWindow();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS);
            window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
            boolean sysNight = (getResources().getConfiguration().uiMode
                    & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
            boolean isNight = "dark".equals(themeMode) || (!"light".equals(themeMode) && sysNight);

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

    private SharedPreferences prefs() {
        return getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    @JavascriptInterface
    public void setModalOpen(boolean open) {
        this.hasOpenModal = open;
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
    public synchronized void saveStore(String json) {
        try {
            writeSqliteStore(getDb(), json != null ? json : "", false);
        } catch (Exception ignored) {
            prefs().edit().putString(KEY_LEGACY_STORE, json != null ? json : "").apply();
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
    public void copyText(String label, String text) {
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard != null) {
            ClipData clip = ClipData.newPlainText(label != null ? label : "PromptPanel", text != null ? text : "");
            clipboard.setPrimaryClip(clip);
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

    private byte[] deriveSyncAeadKey(String token) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(HKDF_SALT_V2, "HmacSHA256"));
        byte[] prk = mac.doFinal(token.trim().getBytes(StandardCharsets.UTF_8));
        mac.init(new SecretKeySpec(prk, "HmacSHA256"));
        return mac.doFinal(HKDF_INFO_AEAD_V2);
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

    @JavascriptInterface
    public String httpRequest(String method, String urlStr, String bearerToken, String bodyJson) {
        HttpURLConnection conn = null;
        try {
            URL currentUrl = new URL(urlStr);
            String initialProtocol = currentUrl.getProtocol() != null
                    ? currentUrl.getProtocol().toLowerCase(Locale.US)
                    : "";
            if (!"https".equals(initialProtocol) && !"http".equals(initialProtocol)) {
                return "400\n不支持的协议：" + initialProtocol;
            }

            String cleanToken = bearerToken != null ? bearerToken.trim() : "";
            boolean useWireCipher = cleanToken.length() >= 12
                    && (urlStr == null || !urlStr.endsWith("/health"));
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
                conn.setReadTimeout(12000);
                conn.setUseCaches(false);
                conn.setRequestProperty("Accept", "application/json");
                conn.setRequestProperty("Content-Type", "application/json; charset=utf-8");
                conn.setRequestProperty("User-Agent", "PromptPanel-Android/1.7.1");
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
                        return code + "\n重定向缺少目标地址";
                    }
                    URL nextUrl = new URL(currentUrl, location);
                    String nextProto = nextUrl.getProtocol() != null
                            ? nextUrl.getProtocol().toLowerCase(Locale.US)
                            : "";
                    if ("https".equals(initialProtocol) && !"https".equals(nextProto)) {
                        return "400\n已拦截不安全的协议降级重定向 (HTTPS -> HTTP)";
                    }
                    currentUrl = nextUrl;
                    redirects++;
                    continue;
                }

                InputStream is = (code >= 200 && code < 400) ? conn.getInputStream() : conn.getErrorStream();
                StringBuilder sb = new StringBuilder();
                if (is != null) {
                    try (BufferedReader reader = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
                        String line;
                        while ((line = reader.readLine()) != null) {
                            sb.append(line).append('\n');
                        }
                    }
                }
                String rawResp = sb.toString().trim();
                if (code >= 200 && code < 300 && useWireCipher && !rawResp.isEmpty()) {
                    rawResp = openSyncEnvelopeIfNeeded(rawResp, cleanToken);
                }
                return code + "\n" + rawResp;
            }
            return "400\n重定向次数过多";
        } catch (Exception e) {
            return "0\n" + (e.getMessage() != null ? e.getMessage() : e.toString());
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }
}
