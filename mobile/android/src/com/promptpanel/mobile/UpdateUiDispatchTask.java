package com.promptpanel.mobile;

public class UpdateUiDispatchTask implements Runnable {
    private final MainActivity activity;
    private final String payloadJson;
    private final boolean markFinished;

    public UpdateUiDispatchTask(MainActivity activity, String payloadJson, boolean markFinished) {
        this.activity = activity;
        this.payloadJson = payloadJson;
        this.markFinished = markFinished;
    }

    @Override
    public void run() {
        activity.deliverUpdateResultToWebView(payloadJson, markFinished);
    }
}
