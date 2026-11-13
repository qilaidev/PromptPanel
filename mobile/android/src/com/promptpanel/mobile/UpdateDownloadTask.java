package com.promptpanel.mobile;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;

public class UpdateDownloadTask implements Runnable {
    private static final String GITHUB_LATEST_URL = "https://api.github.com/repos/qilaidev/PromptPanel/releases/latest";

    private final MainActivity activity;
    private final String syncEndpoint;
    private final int localVersionCode;
    private final String localVersionName;
    private final boolean manualTrigger;
    private final boolean autoDownload;

    public UpdateDownloadTask(
            MainActivity activity,
            String syncEndpoint,
            int localVersionCode,
            String localVersionName,
            boolean manualTrigger,
            boolean autoDownload
    ) {
        this.activity = activity;
        this.syncEndpoint = syncEndpoint != null ? syncEndpoint.trim() : "";
        this.localVersionCode = localVersionCode;
        this.localVersionName = localVersionName != null ? localVersionName.trim() : "1.0.0";
        this.manualTrigger = manualTrigger;
        this.autoDownload = autoDownload;
    }

    @Override
    public void run() {
        try {
            dispatchState("checking", localVersionName, localVersionCode, "", false);

            JSONObject candidate = resolveCandidate();
            String remoteVer = candidate.optString("version", "");
            int remoteBuild = candidate.optInt("build", 0);
            String sha256 = candidate.optString("sha256", "").toLowerCase(Locale.US);
            String primaryUrl = candidate.optString("primaryUrl", "");
            String fallbackUrl = candidate.optString("fallbackUrl", "");

            if (!isNewer(remoteVer, remoteBuild, localVersionName, localVersionCode)) {
                dispatchState("up_to_date", localVersionName, localVersionCode, "", true);
                return;
            }

            File stagedFile = UpdateApkProvider.getStagedApkFile(activity);
            if (!sha256.isEmpty() && stagedFile.exists() && stagedFile.length() > 100000) {
                String existingHash = computeFileSha256(stagedFile);
                if (sha256.equalsIgnoreCase(existingHash)) {
                    dispatchState("ready", remoteVer, remoteBuild, "", true);
                    return;
                }
            }

            if (!manualTrigger && !autoDownload) {
                dispatchState("available", remoteVer, remoteBuild, "", true);
                return;
            }

            if (sha256.isEmpty()) {
                throw new IllegalStateException("缺少新版本 APK 的 SHA-256 校验值");
            }

            dispatchState("downloading", remoteVer, remoteBuild, "", false);

            File parentDir = stagedFile.getParentFile();
            if (parentDir != null && !parentDir.exists()) {
                parentDir.mkdirs();
            }
            File partFile = new File(parentDir, "PromptPanel-latest.apk.part");
            if (partFile.exists()) {
                partFile.delete();
            }

            String downloadedHash = null;
            Exception firstErr = null;
            try {
                downloadedHash = downloadToFileAndHash(primaryUrl, partFile);
            } catch (Exception e) {
                firstErr = e;
            }
            if (downloadedHash == null && !fallbackUrl.isEmpty() && !fallbackUrl.equals(primaryUrl)) {
                downloadedHash = downloadToFileAndHash(fallbackUrl, partFile);
            }
            if (downloadedHash == null) {
                throw firstErr != null ? firstErr : new IllegalStateException("下载新版本安装包失败");
            }

            if (!sha256.equalsIgnoreCase(downloadedHash)) {
                partFile.delete();
                throw new IllegalStateException("安装包 SHA-256 校验不匹配，已拦截安装");
            }

            if (stagedFile.exists()) {
                stagedFile.delete();
            }
            if (!partFile.renameTo(stagedFile)) {
                copyFileFallback(partFile, stagedFile);
                partFile.delete();
            }

            dispatchState("ready", remoteVer, remoteBuild, "", true);
        } catch (Exception e) {
            String msg = MainActivity.translateNetworkException(e);
            dispatchState("error", localVersionName, localVersionCode, msg, true);
        }
    }

    private static void copyFileFallback(File src, File dst) throws Exception {
        try (FileInputStream fis = new FileInputStream(src);
             FileOutputStream fos = new FileOutputStream(dst)) {
            byte[] buf = new byte[32768];
            int n;
            while ((n = fis.read(buf)) > 0) {
                fos.write(buf, 0, n);
            }
            fos.flush();
        }
    }

    private void dispatchState(String state, String version, int build, String message, boolean finished) {
        try {
            JSONObject obj = new JSONObject();
            obj.put("state", state);
            obj.put("version", version != null ? version : "");
            obj.put("build", build);
            obj.put("manual", manualTrigger);
            obj.put("message", message != null ? message : "");
            activity.runOnUiThread(new UpdateUiDispatchTask(activity, obj.toString(), finished));
        } catch (Exception ignored) {
            if (finished) {
                activity.runOnUiThread(new UpdateUiDispatchTask(activity, "{\"state\":\"error\"}", true));
            }
        }
    }

    private JSONObject resolveCandidate() throws Exception {
        String mirrorUpdateUrl = buildMirrorUpdateUrl(syncEndpoint, manualTrigger);
        if (mirrorUpdateUrl != null) {
            try {
                String raw = httpGetText(mirrorUpdateUrl, 8000, 12000, "application/json");
                JSONObject json = new JSONObject(raw);
                JSONObject apkObj = json.optJSONObject("androidApk");
                String ver = json.optString("version", "").trim();
                int build = json.optInt("build", 0);
                if (!ver.isEmpty() && apkObj != null) {
                    String sha = apkObj.optString("sha256", "").trim().toLowerCase(Locale.US);
                    String ghUrl = apkObj.optString("githubUrl", "").trim();
                    String mirrorPath = apkObj.optString("mirrorPath", "").trim();
                    String mirrorApkUrl = "";
                    if (!mirrorPath.isEmpty()) {
                        URL base = new URL(mirrorUpdateUrl);
                        URL resolved = new URL(base.getProtocol(), base.getHost(), base.getPort(), mirrorPath);
                        mirrorApkUrl = resolved.toString();
                    }
                    String primary = !mirrorApkUrl.isEmpty() ? mirrorApkUrl : ghUrl;
                    if (!primary.isEmpty()) {
                        JSONObject out = new JSONObject();
                        out.put("version", ver);
                        out.put("build", build);
                        out.put("sha256", sha);
                        out.put("primaryUrl", primary);
                        out.put("fallbackUrl", ghUrl);
                        return out;
                    }
                }
            } catch (Exception ignored) {
                // Fall back to GitHub Releases directly
            }
        }
        return fetchFromGitHub();
    }

    private JSONObject fetchFromGitHub() throws Exception {
        String raw = httpGetText(GITHUB_LATEST_URL, 10000, 15000, "application/vnd.github+json");
        JSONObject rel = new JSONObject(raw);
        String tag = rel.optString("tag_name", "").trim();
        String ver = tag.startsWith("v") || tag.startsWith("V") ? tag.substring(1) : tag;
        int build = 0;
        JSONArray assets = rel.optJSONArray("assets");
        String apkName = "";
        String apkUrl = "";
        String apkSha = "";
        String sumsUrl = "";

        if (assets != null) {
            for (int i = 0; i < assets.length(); i++) {
                JSONObject a = assets.optJSONObject(i);
                if (a == null) continue;
                String name = a.optString("name", "");
                String dl = a.optString("browser_download_url", "");
                if ("SHA256SUMS.txt".equals(name)) {
                    sumsUrl = dl;
                } else if (name.endsWith("-android.apk")) {
                    apkName = name;
                    apkUrl = dl;
                    String digest = a.optString("digest", "");
                    if (digest.startsWith("sha256:")) {
                        apkSha = digest.substring("sha256:".length()).toLowerCase(Locale.US);
                    }
                    int plusIdx = name.indexOf('+');
                    int dashIdx = name.lastIndexOf("-android.apk");
                    if (name.startsWith("PromptPanel-") && plusIdx > 12 && dashIdx > plusIdx) {
                        ver = name.substring("PromptPanel-".length(), plusIdx);
                        try {
                            build = Integer.parseInt(name.substring(plusIdx + 1, dashIdx));
                        } catch (Exception ignored) {
                        }
                    }
                }
            }
        }

        if (apkUrl.isEmpty() || ver.isEmpty()) {
            throw new IllegalStateException("未在最新发行版中找到 Android 安装包");
        }

        if (apkSha.isEmpty() && !sumsUrl.isEmpty()) {
            try {
                String sumsText = httpGetText(sumsUrl, 8000, 12000, "text/plain");
                String[] lines = sumsText.split("\\r?\\n");
                for (int i = 0; i < lines.length; i++) {
                    String line = lines[i].trim();
                    if (line.length() < 66) continue;
                    int ws = line.indexOf(' ');
                    if (ws == 64) {
                        String hashPart = line.substring(0, 64);
                        String namePart = line.substring(ws).trim();
                        while (namePart.startsWith("*") || namePart.startsWith(".") || namePart.startsWith("/")) {
                            namePart = namePart.substring(1);
                        }
                        if (apkName.equals(namePart)) {
                            apkSha = hashPart.toLowerCase(Locale.US);
                            break;
                        }
                    }
                }
            } catch (Exception ignored) {
            }
        }

        JSONObject out = new JSONObject();
        out.put("version", ver);
        out.put("build", build);
        out.put("sha256", apkSha);
        out.put("primaryUrl", apkUrl);
        out.put("fallbackUrl", "");
        return out;
    }

    static String buildMirrorUpdateUrl(String rawEndpoint, boolean force) {
        if (rawEndpoint == null) return null;
        String clean = rawEndpoint.trim();
        if (clean.isEmpty()) return null;
        String lower = clean.toLowerCase(Locale.US);
        if (!lower.startsWith("http://") && !lower.startsWith("https://")) {
            return null;
        }
        try {
            URL parsed = new URL(clean);
            String path = parsed.getPath() != null ? parsed.getPath() : "";
            while (path.length() > 1 && path.endsWith("/")) {
                path = path.substring(0, path.length() - 1);
            }
            String[] suffixes = new String[]{"/v1/sync", "/v1/promptpanel", "/v1/health", "/sync", "/health"};
            boolean replaced = false;
            for (int i = 0; i < suffixes.length; i++) {
                if (path.endsWith(suffixes[i])) {
                    path = path.substring(0, path.length() - suffixes[i].length()) + "/v1/update";
                    replaced = true;
                    break;
                }
            }
            if (!replaced) {
                if (path.isEmpty() || "/".equals(path)) {
                    path = "/v1/update";
                } else if (!path.endsWith("/v1/update")) {
                    path = path + "/v1/update";
                }
            }
            String file = force ? (path + "?force=1") : path;
            return new URL(parsed.getProtocol(), parsed.getHost(), parsed.getPort(), file).toString();
        } catch (Exception e) {
            return null;
        }
    }

    static boolean isNewer(String remoteVer, int remoteBuild, String localVer, int localBuild) {
        int[] r = parseSemver(remoteVer);
        int[] l = parseSemver(localVer);
        int max = Math.max(r.length, l.length);
        for (int i = 0; i < max; i++) {
            int rv = i < r.length ? r[i] : 0;
            int lv = i < l.length ? l[i] : 0;
            if (rv != lv) {
                return rv > lv;
            }
        }
        if (remoteBuild > 0 && localBuild > 0) {
            return remoteBuild > localBuild;
        }
        return false;
    }

    private static int[] parseSemver(String raw) {
        if (raw == null || raw.isEmpty()) return new int[]{0};
        String s = raw.trim();
        if (s.startsWith("v") || s.startsWith("V")) s = s.substring(1);
        int plus = s.indexOf('+');
        if (plus >= 0) s = s.substring(0, plus);
        String[] parts = s.split("\\.");
        int[] nums = new int[parts.length];
        for (int i = 0; i < parts.length; i++) {
            try {
                nums[i] = Integer.parseInt(parts[i].trim());
            } catch (Exception ignored) {
                nums[i] = 0;
            }
        }
        return nums;
    }

    private static String httpGetText(String urlStr, int connectTimeout, int readTimeout, String accept) throws Exception {
        URL current = new URL(urlStr);
        String initProto = current.getProtocol() != null ? current.getProtocol().toLowerCase(Locale.US) : "";
        for (int hop = 0; hop <= 4; hop++) {
            HttpURLConnection conn = (HttpURLConnection) current.openConnection();
            try {
                conn.setInstanceFollowRedirects(false);
                conn.setRequestMethod("GET");
                conn.setConnectTimeout(connectTimeout);
                conn.setReadTimeout(readTimeout);
                conn.setUseCaches(false);
                conn.setRequestProperty("User-Agent", "PromptPanel-Android-Updater/1.7.4");
                conn.setRequestProperty("Accept", accept);
                int code = conn.getResponseCode();
                if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
                    String loc = conn.getHeaderField("Location");
                    if (loc == null || loc.isEmpty()) throw new IllegalStateException("重定向缺少地址");
                    URL next = new URL(current, loc);
                    if ("https".equals(initProto) && !"https".equalsIgnoreCase(next.getProtocol())) {
                        throw new IllegalStateException("拦截不安全的协议降级重定向");
                    }
                    current = next;
                    continue;
                }
                if (code < 200 || code >= 300) {
                    throw new IllegalStateException("HTTP " + code);
                }
                StringBuilder sb = new StringBuilder();
                try (BufferedReader br = new BufferedReader(new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8))) {
                    String line;
                    while ((line = br.readLine()) != null) {
                        sb.append(line).append('\n');
                    }
                }
                return sb.toString();
            } finally {
                conn.disconnect();
            }
        }
        throw new IllegalStateException("重定向次数过多");
    }

    private static String downloadToFileAndHash(String urlStr, File destFile) throws Exception {
        URL current = new URL(urlStr);
        String initProto = current.getProtocol() != null ? current.getProtocol().toLowerCase(Locale.US) : "";
        for (int hop = 0; hop <= 5; hop++) {
            HttpURLConnection conn = (HttpURLConnection) current.openConnection();
            try {
                conn.setInstanceFollowRedirects(false);
                conn.setRequestMethod("GET");
                conn.setConnectTimeout(12000);
                conn.setReadTimeout(60000);
                conn.setUseCaches(false);
                conn.setRequestProperty("User-Agent", "PromptPanel-Android-Updater/1.7.4");
                int code = conn.getResponseCode();
                if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
                    String loc = conn.getHeaderField("Location");
                    if (loc == null || loc.isEmpty()) throw new IllegalStateException("下载重定向缺少地址");
                    URL next = new URL(current, loc);
                    if ("https".equals(initProto) && !"https".equalsIgnoreCase(next.getProtocol())) {
                        throw new IllegalStateException("拦截不安全的下载协议降级");
                    }
                    current = next;
                    continue;
                }
                if (code < 200 || code >= 300) {
                    throw new IllegalStateException("下载返回 HTTP " + code);
                }
                MessageDigest md = MessageDigest.getInstance("SHA-256");
                long total = 0L;
                try (InputStream is = conn.getInputStream();
                     FileOutputStream fos = new FileOutputStream(destFile)) {
                    byte[] buf = new byte[32768];
                    int n;
                    while ((n = is.read(buf)) > 0) {
                        fos.write(buf, 0, n);
                        md.update(buf, 0, n);
                        total += n;
                        if (total > 120L * 1024L * 1024L) {
                            throw new IllegalStateException("安装包体积异常");
                        }
                    }
                    fos.flush();
                }
                if (total < 100000L) {
                    throw new IllegalStateException("安装包下载不完整");
                }
                return bytesToHex(md.digest());
            } finally {
                conn.disconnect();
            }
        }
        throw new IllegalStateException("下载重定向次数过多");
    }

    private static String computeFileSha256(File file) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        try (FileInputStream fis = new FileInputStream(file)) {
            byte[] buf = new byte[32768];
            int n;
            while ((n = fis.read(buf)) > 0) {
                md.update(buf, 0, n);
            }
        }
        return bytesToHex(md.digest());
    }

    private static String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (int i = 0; i < bytes.length; i++) {
            int v = bytes[i] & 0xFF;
            if (v < 16) sb.append('0');
            sb.append(Integer.toHexString(v));
        }
        return sb.toString();
    }
}
