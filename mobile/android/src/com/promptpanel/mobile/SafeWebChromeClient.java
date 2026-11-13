package com.promptpanel.mobile;

import android.net.Uri;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebView;

public class SafeWebChromeClient extends WebChromeClient {
    private final MainActivity host;

    public SafeWebChromeClient(MainActivity host) {
        this.host = host;
    }

    @Override
    public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> filePathCallback, FileChooserParams fileChooserParams) {
        return host.openQrImagePicker(filePathCallback);
    }
}
