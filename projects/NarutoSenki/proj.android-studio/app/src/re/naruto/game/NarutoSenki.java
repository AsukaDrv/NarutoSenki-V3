package re.naruto.game;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.KeyEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;

import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import org.cocos2dx.lib.Cocos2dxActivity;
import org.cocos2dx.lib.Cocos2dxGLSurfaceView;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;
import okio.ByteString;

import re.naruto.game.net.BluetoothLink;
import re.naruto.game.net.HotspotManager;
import re.naruto.game.net.LanDiscovery;
import re.naruto.game.net.TcpLink;

public class NarutoSenki extends Cocos2dxActivity {
        private static final String TAG = "NarutoWs";
        private static final int REQ_PERMS_LINK = 0x5E51;
        private static final Object WS_LOCK = new Object();
        private static final ExecutorService WS_EXECUTOR = Executors.newSingleThreadExecutor(new ThreadFactory() {
                @Override
                public Thread newThread(Runnable r) {
                        Thread t = new Thread(r, "NarutoWs");
                        t.setDaemon(true);
                        return t;
                }
        });
        private static final OkHttpClient WS_CLIENT = new OkHttpClient.Builder()
                        .readTimeout(0, TimeUnit.MILLISECONDS)
                        .connectTimeout(30, TimeUnit.SECONDS)
                        .writeTimeout(30, TimeUnit.SECONDS)
                        .callTimeout(0, TimeUnit.MILLISECONDS)
                        .retryOnConnectionFailure(true)
                        .build();
        private static final String EVENT_OPEN = "open";
        private static final String EVENT_MESSAGE = "message";
        private static final String EVENT_ERROR = "error";
        private static final String EVENT_CLOSE = "close";

        private static volatile WebSocket sWebSocket = null;
        private static volatile boolean sIsConnected = false;
        static NarutoSenki sInstance = null;

        private static native void nativeWsJniBoot();

        protected void onCreate(Bundle savedInstanceState) {
                super.onCreate(savedInstanceState);
                nativeWsJniBoot();
                sInstance = this;
                BluetoothLink.setAppContext(getApplicationContext());
                getWindow().setFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                applyImmersiveMode();
        }

        /**
         * Fullscreen penuh: hilangkan TITLE BAR hitam "NarutoSenki", status bar
         * (jam/baterai) dan navigation bar yang menutupi area game.
         * Dipanggil ulang setiap window mendapat fokus (onWindowFocusChanged)
         * agar bar tidak muncul kembali setelah dialog/notifikasi.
         */
        private void applyImmersiveMode() {
                try {
                        final Window window = getWindow();
                        if (Build.VERSION.SDK_INT >= 28) {
                                WindowManager.LayoutParams lp = window.getAttributes();
                                lp.layoutInDisplayCutoutMode =
                                                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
                                window.setAttributes(lp);
                        }
                        final View decor = window.getDecorView();
                        if (Build.VERSION.SDK_INT >= 30) {
                                window.setDecorFitsSystemWindows(false);
                                final WindowInsetsController controller = window.getInsetsController();
                                if (controller != null) {
                                        controller.setSystemBarsBehavior(
                                                        WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
                                        controller.hide(WindowInsets.Type.statusBars()
                                                        | WindowInsets.Type.navigationBars()
                                                        | WindowInsets.Type.captionBar());
                                }
                        } else {
                                decor.setSystemUiVisibility(
                                                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                                                                | View.SYSTEM_UI_FLAG_FULLSCREEN
                                                                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                                                                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                                                                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                                                                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
                        }
                } catch (Exception e) {
                        Log.w(TAG, "applyImmersiveMode failed", e);
                }
        }

        @Override
        public void onWindowFocusChanged(boolean hasFocus) {
                super.onWindowFocusChanged(hasFocus);
                if (hasFocus) {
                        applyImmersiveMode();
                }
        }

        public Cocos2dxGLSurfaceView onCreateGLSurfaceView() {
                return new LuaGLSurfaceView(this);
        }

        @Override
        protected void onDestroy() {
                wsDisconnect();
                linkStop();
                super.onDestroy();
        }

        // ==================================================================
        //  WebSocket (online / relay server)
        // ==================================================================
        public static boolean wsConnect(final String url) {
                final String trimmed = url != null ? url.trim() : "";
                if (trimmed.isEmpty()) {
                        Log.w(TAG, "wsConnect: empty url");
                        return false;
                }

                WS_EXECUTOR.execute(new Runnable() {
                        @Override
                        public void run() {
                                synchronized (WS_LOCK) {
                                        if (sWebSocket != null) {
                                                sWebSocket.cancel();
                                                sWebSocket = null;
                                        }
                                        sIsConnected = false;

                                        try {
                                                Request request = new Request.Builder().url(trimmed).build();
                                                sWebSocket = WS_CLIENT.newWebSocket(request, new WebSocketListener() {
                                                        @Override
                                                        public void onOpen(WebSocket webSocket, Response response) {
                                                                sIsConnected = true;
                                                                dispatchWebSocketEvent(EVENT_OPEN, "");
                                                        }

                                                        @Override
                                                        public void onMessage(WebSocket webSocket, String text) {
                                                                dispatchWebSocketEvent(EVENT_MESSAGE, text != null ? text : "");
                                                        }

                                                        @Override
                                                        public void onMessage(WebSocket webSocket, ByteString bytes) {
                                                                dispatchWebSocketEvent(EVENT_MESSAGE, bytes != null ? bytes.hex() : "");
                                                        }

                                                        @Override
                                                        public void onFailure(WebSocket webSocket, Throwable t, Response response) {
                                                                sIsConnected = false;
                                                                synchronized (WS_LOCK) {
                                                                        if (sWebSocket == webSocket) {
                                                                                sWebSocket = null;
                                                                        }
                                                                }
                                                                final String summary = formatWsFailureMessage(t, response);
                                                                Log.e(TAG, "onFailure url=" + trimmed, t);
                                                                dispatchWebSocketEvent(EVENT_ERROR, summary);
                                                        }

                                                        @Override
                                                        public void onClosed(WebSocket webSocket, int code, String reason) {
                                                                sIsConnected = false;
                                                                synchronized (WS_LOCK) {
                                                                        if (sWebSocket == webSocket) {
                                                                                sWebSocket = null;
                                                                        }
                                                                }
                                                                dispatchWebSocketEvent(EVENT_CLOSE, reason != null ? reason : "");
                                                        }
                                                });
                                        } catch (IllegalArgumentException e) {
                                                sWebSocket = null;
                                                sIsConnected = false;
                                                Log.e(TAG, "wsConnect: bad url string", e);
                                                dispatchWebSocketEvent(EVENT_ERROR,
                                                                e.getMessage() != null ? e.getMessage() : e.toString());
                                        } catch (Exception e) {
                                                sWebSocket = null;
                                                sIsConnected = false;
                                                Log.e(TAG, "wsConnect: failed to create WebSocket url=" + trimmed, e);
                                                dispatchWebSocketEvent(EVENT_ERROR,
                                                                e.getMessage() != null ? e.getMessage() : e.toString());
                                        }
                                }
                        }
                });
                return true;
        }

        private static String formatWsFailureMessage(Throwable t, Response response) {
                String base = "unknown websocket error";
                if (t != null) {
                        base = t.getMessage();
                        if (base == null || base.trim().isEmpty()) {
                                base = t.toString();
                        }
                }
                if (response == null) {
                        return base;
                }
                StringBuilder sb = new StringBuilder(base);
                sb.append(" (HTTP ").append(response.code()).append(")");
                if (response.message() != null && !response.message().isEmpty()) {
                        sb.append(": ").append(response.message());
                }
                return sb.toString();
        }

        public static void wsSend(final String message) {
                WebSocket webSocket = sWebSocket;
                if (webSocket == null || !sIsConnected) {
                        return;
                }
                webSocket.send(message != null ? message : "");
        }

        public static void wsDisconnect() {
                synchronized (WS_LOCK) {
                        WebSocket webSocket = sWebSocket;
                        sWebSocket = null;
                        sIsConnected = false;
                        if (webSocket != null) {
                                webSocket.close(1000, "client_disconnect");
                        }
                }
        }

        public static boolean wsIsConnected() {
                return sIsConnected;
        }

        private static void dispatchWebSocketEvent(final String eventName, final String payload) {
                final NarutoSenki activity = sInstance;
                if (activity == null) {
                        nativeOnWebSocketEvent(eventName, payload);
                        return;
                }

                activity.runOnGLThread(new Runnable() {
                        @Override
                        public void run() {
                                nativeOnWebSocketEvent(eventName, payload);
                        }
                });
        }

        // ==================================================================
        //  Mabar lokal: WiFi LAN / Hotspot / Bluetooth (satu kanal event ke Lua)
        // ==================================================================
        /** Dipanggil dari semua transport lokal. Event & payload konsisten dengan WS. */
        public static void dispatchLinkEvent(final String eventName, final String payload) {
                final NarutoSenki activity = sInstance;
                if (activity == null) {
                        nativeOnWebSocketEvent(eventName, payload);
                        return;
                }
                activity.runOnGLThread(new Runnable() {
                        @Override
                        public void run() {
                                nativeOnWebSocketEvent(eventName, payload);
                        }
                });
        }

        /** Host room TCP di jaringan WiFi yang sedang aktif + mulai beacon LAN. */
        public static boolean lanHost(final String roomName, final int port) {
                TcpLink.stopAll();
                LanDiscovery.stopAll();
                boolean ok = TcpLink.startServer(port);
                if (ok) {
                        LanDiscovery.startHosting(roomName, port, 1, 4);
                }
                return ok;
        }

        /** Join room TCP via IP (LAN/Hotspot). */
        public static boolean lanJoin(final String host, final int port) {
                LanDiscovery.stopAll();
                TcpLink.stopAll();
                return TcpLink.connectClient(host, port);
        }

        /** Berhenti semua koneksi & beacon. */
        public static void lanStop() {
                LanDiscovery.stopAll();
                TcpLink.stopAll();
        }

        /** Mulai scan room LAN (event "lan_rooms"). */
        public static boolean lanScan() {
                return LanDiscovery.startScan();
        }

        public static void lanScanStop() {
                LanDiscovery.stopScan();
        }

        /** Nyalakan LocalOnlyHotspot (event "hotspot_started"). */
        public static boolean hotspotStart(final String ssidPrefix) {
                NarutoSenki activity = sInstance;
                if (activity == null) {
                        dispatchLinkEvent("hotspot_error", "activity belum siap");
                        return false;
                }
                return HotspotManager.start(activity.getApplicationContext());
        }

        public static void hotspotStop() {
                HotspotManager.stop();
        }

        public static boolean hotspotIsRunning() {
                return HotspotManager.isRunning();
        }

        /** Bluetooth: host (listen RFCOMM). */
        public static boolean btHost() {
                return BluetoothLink.host();
        }

        /** Bluetooth: connect ke device address "XX:XX:...". */
        public static boolean btConnect(final String address) {
                return BluetoothLink.connect(address);
        }

        /** Bluetooth: scan device sekitar (event "bt_devices"). */
        public static boolean btScan() {
                NarutoSenki activity = sInstance;
                if (activity == null) return false;
                return BluetoothLink.scan(activity.getApplicationContext());
        }

        public static void btScanStop() {
                BluetoothLink.stopScan();
        }

        /** Kirim pesan ke semua link aktif (TCP + Bluetooth). */
        public static boolean linkSend(final String message) {
                boolean any = false;
                try {
                        any = TcpLink.send(message) || any;
                } catch (Exception ignored) {}
                try {
                        any = BluetoothLink.send(message) || any;
                } catch (Exception ignored) {}
                return any;
        }

        /** Matikan semua transport lokal. */
        public static void linkStop() {
                try { TcpLink.stopAll(); } catch (Exception ignored) {}
                try { LanDiscovery.stopAll(); } catch (Exception ignored) {}
                try { HotspotManager.stop(); } catch (Exception ignored) {}
                try { BluetoothLink.stopAll(); } catch (Exception ignored) {}
        }

        public static boolean linkIsActive() {
                return TcpLink.isActive() || BluetoothLink.isConnected() || HotspotManager.isRunning();
        }

        /**
         * Minta runtime permission yang dibutuhkan mabar sesuai versi Android:
         *  - API 31+: BLUETOOTH_SCAN + BLUETOOTH_CONNECT, NEARBY_WIFI_DEVICES (API 33+)
         *  - API <31: ACCESS_FINE_LOCATION
         * Hasil dikirim ke Lua sebagai event "permissions" {"granted": true/false}.
         */
        public static void linkRequestPermissions() {
                NarutoSenki activity = sInstance;
                if (activity == null) {
                        dispatchLinkEvent("permissions", "{\"granted\":false}");
                        return;
                }
                List<String> wanted = new ArrayList<>();
                if (Build.VERSION.SDK_INT >= 31) {
                        wanted.add(Manifest.permission.BLUETOOTH_SCAN);
                        wanted.add(Manifest.permission.BLUETOOTH_CONNECT);
                } else {
                        wanted.add(Manifest.permission.ACCESS_FINE_LOCATION);
                }
                if (Build.VERSION.SDK_INT >= 33) {
                        wanted.add(Manifest.permission.NEARBY_WIFI_DEVICES);
                }

                List<String> missing = new ArrayList<>();
                for (String perm : wanted) {
                        if (ContextCompat.checkSelfPermission(activity, perm)
                                        != PackageManager.PERMISSION_GRANTED) {
                                missing.add(perm);
                        }
                }
                if (missing.isEmpty()) {
                        dispatchLinkEvent("permissions", "{\"granted\":true}");
                        return;
                }
                ActivityCompat.requestPermissions(activity,
                                missing.toArray(new String[0]), REQ_PERMS_LINK);
        }

        @Override
        public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
                super.onRequestPermissionsResult(requestCode, permissions, grantResults);
                if (requestCode == REQ_PERMS_LINK) {
                        boolean granted = grantResults != null && grantResults.length > 0;
                        if (granted) {
                                for (int result : grantResults) {
                                        if (result != PackageManager.PERMISSION_GRANTED) {
                                                granted = false;
                                                break;
                                        }
                                }
                        }
                        dispatchLinkEvent("permissions",
                                        "{\"granted\":" + (granted ? "true" : "false") + "}");
                }
        }

        private static native void nativeOnWebSocketEvent(String eventName, String payload);

        static {
                System.loadLibrary("cocos2dcpp");
        }
}

class LuaGLSurfaceView extends Cocos2dxGLSurfaceView {

        public LuaGLSurfaceView(Context context) {
                super(context);
        }

        public boolean onKeyDown(int keyCode, KeyEvent event) {
                // Stabilitas: tombol back hanya memindahkan app ke background,
                // tidak mematikan proses (sebelumnya killProcess -> data save hilang).
                if (keyCode == KeyEvent.KEYCODE_BACK) {
                        NarutoSenki activity = NarutoSenki.sInstance;
                        if (activity != null) {
                                activity.moveTaskToBack(true);
                        }
                        return true;
                }
                return super.onKeyDown(keyCode, event);
        }
}
