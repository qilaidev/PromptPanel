package com.promptpanel.mobile;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

public class MainActivity extends Activity {
    private static final String PREFS_NAME = "promptpanel_mobile_prefs";
    private static final String KEY_STORE = "promptpanel_mobile_store_v2";
    private static final String KEY_ENDPOINT = "promptpanel_cloud_endpoint";
    private static final String KEY_API_KEY = "promptpanel_cloud_api_key";

    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        Window window = getWindow();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS);
            window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
            boolean isNight = (getResources().getConfiguration().uiMode
                    & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
            window.setStatusBarColor(Color.parseColor(isNight ? "#0F1115" : "#F6F7F9"));
            window.setNavigationBarColor(Color.parseColor(isNight ? "#161920" : "#FFFFFF"));
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !isNight) {
                window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
            }
        }

        webView = new WebView(this);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setTextZoom(100);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);

        webView.setWebChromeClient(new WebChromeClient());
        webView.setWebViewClient(new WebViewClient());
        webView.addJavascriptInterface(this, "AndroidBridge");

        setContentView(webView);
        webView.loadUrl("file:///android_asset/index.html");
    }

    private SharedPreferences prefs() {
        return getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    @JavascriptInterface
    public String loadStore() {
        return prefs().getString(KEY_STORE, "");
    }

    @JavascriptInterface
    public void saveStore(String json) {
        prefs().edit().putString(KEY_STORE, json != null ? json : "").apply();
    }

    @JavascriptInterface
    public String getEndpoint() {
        return prefs().getString(KEY_ENDPOINT, "");
    }

    @JavascriptInterface
    public String getApiKey() {
        return prefs().getString(KEY_API_KEY, "");
    }

    @JavascriptInterface
    public void saveSettings(String endpoint, String apiKey) {
        prefs().edit()
                .putString(KEY_ENDPOINT, endpoint != null ? endpoint.trim() : "")
                .putString(KEY_API_KEY, apiKey != null ? apiKey.trim() : "")
                .apply();
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
    public String httpRequest(String method, String urlStr, String bearerToken, String bodyJson) {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(urlStr);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod(method);
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(15000);
            conn.setRequestProperty("Accept", "application/json");
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            if (bearerToken != null && !bearerToken.trim().isEmpty()) {
                conn.setRequestProperty("Authorization", "Bearer " + bearerToken.trim());
            }
            if ("POST".equalsIgnoreCase(method) && bodyJson != null) {
                conn.setDoOutput(true);
                byte[] payload = bodyJson.getBytes(StandardCharsets.UTF_8);
                conn.setFixedLengthStreamingMode(payload.length);
                try (OutputStream os = conn.getOutputStream()) {
                    os.write(payload);
                    os.flush();
                }
            }
            int code = conn.getResponseCode();
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
            return code + "\n" + sb.toString().trim();
        } catch (Exception e) {
            return "0\n" + (e.getMessage() != null ? e.getMessage() : e.toString());
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }
}
