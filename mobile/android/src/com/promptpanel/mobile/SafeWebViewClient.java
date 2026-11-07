package com.promptpanel.mobile;

import android.net.Uri;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class SafeWebViewClient extends WebViewClient {
    private static final String ALLOWED_ASSET_PREFIX = "file:///android_asset/";

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, String url) {
        return !isAllowedUrl(url);
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
        if (request == null || request.getUrl() == null) {
            return true;
        }
        return !isAllowedUrl(request.getUrl().toString());
    }

    private boolean isAllowedUrl(String url) {
        if (url == null) {
            return false;
        }
        return url.startsWith(ALLOWED_ASSET_PREFIX);
    }
}
